//
//  PicaNetworkRouting.swift
//  Aidoku
//
//  Routes only Picacomic API traffic through a local CONNECT tunnel so the
//  custom source can select a channel address without changing TLS hostnames.
//

import Foundation
import Network

enum PicaNetworkRouting {
    static let sourceId = "zh.picacomic"

    static func shouldRoute(_ request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        let isPicaHost = host == "picacomic.com" || host.hasSuffix(".picacomic.com")
        let channel = UserDefaults.standard.string(forKey: "\(sourceId).appChannel") ?? "2"
        return isPicaHost && channel != "1"
    }

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard shouldRoute(request) else {
            return try await URLSession.shared.data(for: request)
        }
        do {
            return try await PicaRoutedSession.shared.data(for: request)
        } catch {
            LogManager.logger.warn("Pica channel route failed, falling back to system networking: \(error)")
            return try await URLSession.shared.data(for: request)
        }
    }
}

private actor PicaRoutedSession {
    static let shared = PicaRoutedSession()
    private var session: URLSession?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let activeSession: URLSession
        if let session {
            activeSession = session
        } else {
            let port = try await PicaTunnelProxy.shared.start()
            let configuration = URLSessionConfiguration.default
            configuration.connectionProxyDictionary = [
                "HTTPSEnable": true,
                "HTTPSProxy": "127.0.0.1",
                "HTTPSPort": Int(port)
            ]
            configuration.httpMaximumConnectionsPerHost = 6
            configuration.timeoutIntervalForRequest = 30
            let newSession = URLSession(configuration: configuration)
            session = newSession
            activeSession = newSession
        }
        return try await activeSession.data(for: request)
    }
}

private final class PicaTunnelProxy: @unchecked Sendable {
    static let shared = PicaTunnelProxy()

    private let queue = DispatchQueue(label: "app.aidoku.pica-channel-proxy", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: UInt16?
    private var waiters: [CheckedContinuation<UInt16, any Error>] = []

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let port {
                lock.unlock()
                continuation.resume(returning: port)
                return
            }

            waiters.append(continuation)
            guard listener == nil else {
                lock.unlock()
                return
            }

            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                let newListener = try NWListener(using: parameters, on: .any)
                listener = newListener
                lock.unlock()

                newListener.newConnectionHandler = { connection in
                    PicaProxyTunnel(connection: connection, queue: self.queue).start()
                }
                newListener.stateUpdateHandler = { state in
                    switch state {
                        case .ready:
                            guard let port = newListener.port?.rawValue else {
                                self.finishStart(.failure(PicaNetworkError.missingListenerPort))
                                return
                            }
                            self.finishStart(.success(port))
                        case .failed(let error):
                            self.finishStart(.failure(error))
                        default:
                            break
                    }
                }
                newListener.start(queue: queue)
            } catch {
                listener = nil
                lock.unlock()
                finishStart(.failure(error))
            }
        }
    }

    private func finishStart(_ result: Result<UInt16, any Error>) {
        lock.lock()
        if case .success(let port) = result {
            self.port = port
        } else {
            listener = nil
        }
        let waiters = waiters
        self.waiters.removeAll()
        lock.unlock()
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }
}

private final class PicaProxyTunnel: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var connectBuffer = Data()
    private var remoteConnection: NWConnection?
    private var finished = false

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { state in
            switch state {
                case .ready: self.receiveConnectRequest()
                case .failed, .cancelled: self.finish()
                default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveConnectRequest() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { connectBuffer.append(data) }

            guard let headerRange = connectBuffer.range(of: Data("\r\n\r\n".utf8)) else {
                if error != nil || isComplete || connectBuffer.count >= 64 * 1024 {
                    sendProxyErrorAndFinish(status: "400 Bad Request")
                } else {
                    receiveConnectRequest()
                }
                return
            }

            let headerData = connectBuffer[..<headerRange.lowerBound]
            let trailingData = connectBuffer[headerRange.upperBound...]
            guard
                let header = String(data: headerData, encoding: .utf8),
                let firstLine = header.components(separatedBy: "\r\n").first,
                let authority = parseConnectAuthority(firstLine)
            else {
                sendProxyErrorAndFinish(status: "400 Bad Request")
                return
            }

            Task {
                let targetHost = await PicaChannelResolver.shared.targetHost(for: authority.host)
                self.queue.async {
                    self.connectRemote(
                        targetHost: targetHost,
                        originalHost: authority.host,
                        port: authority.port,
                        trailingData: Data(trailingData),
                        hasRetriedSystemHost: false
                    )
                }
            }
        }
    }

    private func parseConnectAuthority(_ firstLine: String) -> (host: String, port: UInt16)? {
        let fields = firstLine.split(separator: " ")
        guard fields.count >= 2, fields[0].uppercased() == "CONNECT" else { return nil }
        let authority = String(fields[1])

        if authority.hasPrefix("["), let bracket = authority.firstIndex(of: "]") {
            let host = String(authority[authority.index(after: authority.startIndex)..<bracket])
            let portStart = authority.index(after: bracket)
            let portText = portStart < authority.endIndex && authority[portStart] == ":"
                ? String(authority[authority.index(after: portStart)...])
                : "443"
            return UInt16(portText).map { (host, $0) }
        }

        if let separator = authority.lastIndex(of: ":") {
            let host = String(authority[..<separator])
            let portText = String(authority[authority.index(after: separator)...])
            return UInt16(portText).map { (host, $0) }
        }
        return (authority, 443)
    }

    private func connectRemote(
        targetHost: String,
        originalHost: String,
        port: UInt16,
        trailingData: Data,
        hasRetriedSystemHost: Bool
    ) {
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            sendProxyErrorAndFinish(status: "400 Bad Request")
            return
        }

        let remote = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(targetHost), port: networkPort),
            using: .tcp
        )
        remoteConnection = remote
        remote.stateUpdateHandler = { [weak self, weak remote] state in
            guard let self, let remote else { return }
            switch state {
                case .ready:
                    establishTunnel(remote: remote, trailingData: trailingData)
                case .failed:
                    remote.cancel()
                    if targetHost != originalHost && !hasRetriedSystemHost {
                        connectRemote(
                            targetHost: originalHost,
                            originalHost: originalHost,
                            port: port,
                            trailingData: trailingData,
                            hasRetriedSystemHost: true
                        )
                    } else {
                        sendProxyErrorAndFinish(status: "502 Bad Gateway")
                    }
                case .cancelled:
                    if !finished && remoteConnection === remote { finish() }
                default:
                    break
            }
        }
        remote.start(queue: queue)
    }

    private func establishTunnel(remote: NWConnection, trailingData: Data) {
        let response = Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)
        connection.send(content: response, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                finish()
                return
            }

            let startPumps = {
                self.pipe(from: self.connection, to: remote)
                self.pipe(from: remote, to: self.connection)
            }
            if trailingData.isEmpty {
                startPumps()
            } else {
                remote.send(content: trailingData, completion: .contentProcessed { error in
                    if error == nil { startPumps() } else { self.finish() }
                })
            }
        })
    }

    private func pipe(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self, !finished else { return }
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil || error != nil || isComplete {
                        self.finish()
                    } else {
                        self.pipe(from: source, to: destination)
                    }
                })
            } else if error != nil || isComplete {
                finish()
            } else {
                pipe(from: source, to: destination)
            }
        }
    }

    private func sendProxyErrorAndFinish(status: String) {
        let response = Data("HTTP/1.1 \(status)\r\nConnection: close\r\n\r\n".utf8)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.finish()
        })
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        remoteConnection?.stateUpdateHandler = nil
        connection.cancel()
        remoteConnection?.cancel()
        remoteConnection = nil
    }
}

private actor PicaChannelResolver {
    static let shared = PicaChannelResolver()

    private static let initURL = URL(string: "http://68.183.234.72/init")
    private static let bootstrapAddresses = ["104.19.53.76"]
    private static let cacheAddressesKey = "PicaChannel.addresses"
    private static let cacheDateKey = "PicaChannel.updatedAt"
    private static let cacheLifetime: TimeInterval = 24 * 60 * 60
    private static let refreshRetryInterval: TimeInterval = 5 * 60

    private var addresses: [String]?
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshAttempt: Date?

    func targetHost(for originalHost: String) async -> String {
        let host = originalHost.lowercased()
        guard host == "picacomic.com" || host.hasSuffix(".picacomic.com") else {
            return originalHost
        }
        let channel = UserDefaults.standard.string(forKey: "\(PicaNetworkRouting.sourceId).appChannel") ?? "2"
        guard channel != "1" else { return originalHost }

        let addresses = cachedAddresses()
        refreshAddressesIfNeeded()
        guard !addresses.isEmpty else { return originalHost }
        let preferredIndex = channel == "3" ? 1 : 0
        let target = addresses.indices.contains(preferredIndex) ? addresses[preferredIndex] : addresses[0]
        LogManager.logger.log("Pica channel \(channel): \(originalHost) -> \(target)")
        return target
    }

    private func cachedAddresses() -> [String] {
        if let addresses { return addresses }
        let cached = UserDefaults.standard.stringArray(forKey: Self.cacheAddressesKey) ?? []
        let initial = cached.isEmpty ? Self.bootstrapAddresses : cached
        addresses = initial
        return initial
    }

    private func refreshAddressesIfNeeded() {
        let defaults = UserDefaults.standard
        let cacheDate = defaults.double(forKey: Self.cacheDateKey)
        let cacheIsFresh = Date().timeIntervalSince1970 - cacheDate < Self.cacheLifetime
        guard !cacheIsFresh, refreshTask == nil else { return }
        if let lastRefreshAttempt,
           Date().timeIntervalSince(lastRefreshAttempt) < Self.refreshRetryInterval
        {
            return
        }
        lastRefreshAttempt = Date()

        refreshTask = Task {
            let fetched = await Self.fetchAddresses()
            if !fetched.isEmpty {
                defaults.set(fetched, forKey: Self.cacheAddressesKey)
                defaults.set(Date().timeIntervalSince1970, forKey: Self.cacheDateKey)
                addresses = fetched
                LogManager.logger.log("Pica channel addresses updated in background")
            }
            refreshTask = nil
        }
    }

    private static func fetchAddresses() async -> [String] {
        guard let initURL else { return [] }
        var request = URLRequest(url: initURL)
        request.timeoutInterval = 3
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("okhttp/3.8.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let response = response as? HTTPURLResponse,
                (200..<300).contains(response.statusCode),
                let payload = try? JSONDecoder().decode(PicaChannelResponse.self, from: data),
                payload.status == "ok"
            else { return [] }
            return payload.addresses.filter { IPv4Address($0) != nil || IPv6Address($0) != nil }
        } catch {
            LogManager.logger.warn("Unable to update Pica channel addresses: \(error)")
            return []
        }
    }
}

private struct PicaChannelResponse: Decodable {
    let status: String
    let addresses: [String]
}

private enum PicaNetworkError: LocalizedError {
    case missingListenerPort

    var errorDescription: String? {
        switch self {
            case .missingListenerPort: "Pica channel proxy did not receive a local port"
        }
    }
}
