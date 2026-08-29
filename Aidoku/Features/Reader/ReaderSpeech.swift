//
//  ReaderSpeech.swift
//  Aidoku
//
//  Speech primitives shared by text readers.  Microsoft Edge online speech is
//  the default provider; Apple's synthesizer is kept as an automatic fallback.
//

import AVFoundation
import AidokuRunner
import Combine
import CryptoKit
import MediaPlayer
import SwiftUI
import UIKit
import ZIPFoundation

func readerSpeechLocalized(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
}

struct ReaderSpeechSegment: Identifiable, Sendable, Equatable {
    let id: String
    let chapterKey: String
    let pageIndex: Int
    let text: String
}

@MainActor
protocol ReaderSpeechTextProviding: AnyObject {
    func speechSegmentsFromCurrentPosition() -> [ReaderSpeechSegment]
    func prepareSpeechSegments(for chapter: AidokuRunner.Chapter) async -> [ReaderSpeechSegment]
    @discardableResult func revealSpeechSegment(_ segment: ReaderSpeechSegment) -> Bool
    func setSpeechNavigationLocked(_ locked: Bool)
}

extension ReaderSpeechTextProviding {
    func prepareSpeechSegments(for _: AidokuRunner.Chapter) async -> [ReaderSpeechSegment] { [] }
    @discardableResult func revealSpeechSegment(_: ReaderSpeechSegment) -> Bool { false }
    func setSpeechNavigationLocked(_: Bool) {}
}

/// Extracts only readable text. Image pages intentionally produce nil so a
/// comic chapter cannot accidentally be sent to an online speech provider.
enum ReaderSpeechTextExtractor {
    static func segments(
        from pages: [Page],
        chapterKey: String,
        startingAt pageIndex: Int = 0
    ) -> [ReaderSpeechSegment] {
        pages.enumerated().compactMap { index, page in
            guard index >= pageIndex, let text = text(from: page) else { return nil }
            return ReaderSpeechSegment(
                id: "\(chapterKey)|\(page.key)",
                chapterKey: chapterKey,
                pageIndex: index,
                text: text
            )
        }
    }

    static func text(from page: Page) -> String? {
        if let text = page.text { return text }
        guard
            let zipURLString = page.zipURL,
            let zipURL = URL(string: zipURLString),
            let filePath = page.imageURL
        else { return nil }
        return text(fromZip: zipURL, filePath: filePath)
    }

    static func text(from page: AidokuRunner.Page) -> String? {
        switch page.content {
            case let .text(text): return text
            case let .zipFile(url, filePath): return text(fromZip: url, filePath: filePath)
            case .url, .image: return nil
        }
    }

    private static func text(fromZip zipURL: URL, filePath: String) -> String? {
        do {
            var data = Data()
            let archive = try Archive(url: zipURL, accessMode: .read)
            guard let entry = archive.entry(at: filePath) else { return nil }
            _ = try archive.extract(entry, consumer: { data.append($0) })
            return String(data: data, encoding: .utf8)
        } catch {
            LogManager.logger.error("Unable to load text for speech: \(error)")
            return nil
        }
    }
}

enum ReaderSpeechProvider: String, CaseIterable, Identifiable, Sendable {
    case microsoft
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
            case .microsoft:
                readerSpeechLocalized("READER_TTS_PROVIDER_MICROSOFT", fallback: "Microsoft online speech")
            case .system:
                readerSpeechLocalized("READER_TTS_PROVIDER_SYSTEM", fallback: "Apple system speech")
        }
    }
}

enum MicrosoftSpeechVoice: String, CaseIterable, Identifiable, Sendable {
    case xiaoxiao = "zh-CN-XiaoxiaoNeural"
    case xiaoyi = "zh-CN-XiaoyiNeural"
    case xiaochen = "zh-CN-XiaochenNeural"
    case xiaohan = "zh-CN-XiaohanNeural"
    case yunxi = "zh-CN-YunxiNeural"
    case yunjian = "zh-CN-YunjianNeural"
    case yunyang = "zh-CN-YunyangNeural"
    case yunye = "zh-CN-YunyeNeural"

    var id: String { rawValue }

    var title: String {
        switch self {
            case .xiaoxiao: readerSpeechLocalized("MICROSOFT_TTS_XIAOXIAO", fallback: "Xiaoxiao")
            case .xiaoyi: readerSpeechLocalized("MICROSOFT_TTS_XIAOYI", fallback: "Xiaoyi")
            case .xiaochen: readerSpeechLocalized("MICROSOFT_TTS_XIAOCHEN", fallback: "Xiaochen")
            case .xiaohan: readerSpeechLocalized("MICROSOFT_TTS_XIAOHAN", fallback: "Xiaohan")
            case .yunxi: readerSpeechLocalized("MICROSOFT_TTS_YUNXI", fallback: "Yunxi")
            case .yunjian: readerSpeechLocalized("MICROSOFT_TTS_YUNJIAN", fallback: "Yunjian")
            case .yunyang: readerSpeechLocalized("MICROSOFT_TTS_YUNYANG", fallback: "Yunyang")
            case .yunye: readerSpeechLocalized("MICROSOFT_TTS_YUNYE", fallback: "Yunye")
        }
    }
}

@MainActor
final class ReaderSpeechSettingsStore: ObservableObject {
    static let shared = ReaderSpeechSettingsStore()

    @Published var provider: ReaderSpeechProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey) }
    }
    @Published var voice: MicrosoftSpeechVoice {
        didSet { UserDefaults.standard.set(voice.rawValue, forKey: Self.voiceKey) }
    }
    @Published var rate: Double {
        didSet { UserDefaults.standard.set(rate, forKey: Self.rateKey) }
    }
    @Published var allowsSystemFallback: Bool {
        didSet { UserDefaults.standard.set(allowsSystemFallback, forKey: Self.fallbackKey) }
    }

    private static let providerKey = "Reader.speechProvider"
    private static let voiceKey = "Reader.microsoftSpeechVoice"
    private static let rateKey = "Reader.microsoftSpeechRate"
    private static let fallbackKey = "Reader.speechSystemFallback"

    private init() {
        provider = UserDefaults.standard.string(forKey: Self.providerKey)
            .flatMap(ReaderSpeechProvider.init(rawValue:)) ?? .microsoft
        voice = UserDefaults.standard.string(forKey: Self.voiceKey)
            .flatMap(MicrosoftSpeechVoice.init(rawValue:)) ?? .xiaoxiao
        let storedRate = UserDefaults.standard.object(forKey: Self.rateKey) as? Double
        rate = min(1.6, max(0.6, storedRate ?? 1.0))
        allowsSystemFallback = UserDefaults.standard.object(forKey: Self.fallbackKey) as? Bool ?? true
    }
}

struct ReaderSpeechSynthesisRequest: Sendable {
    let text: String
    let rate: Double
}

protocol ReaderSpeechEngine: Sendable {
    var cacheIdentifier: String { get }
    func synthesize(_ request: ReaderSpeechSynthesisRequest) async throws -> Data
}

struct ReaderMicrosoftSpeechEngine: ReaderSpeechEngine {
    let voice: MicrosoftSpeechVoice

    var cacheIdentifier: String { "microsoft-edge|\(voice.rawValue)" }

    func synthesize(_ request: ReaderSpeechSynthesisRequest) async throws -> Data {
        try await MicrosoftSpeechService.synthesize(
            text: request.text,
            voice: voice,
            rate: request.rate
        )
    }
}

/// The free Edge endpoint is intentionally isolated behind this type.  It can
/// be replaced or disabled without changing the reader state machine.
enum MicrosoftSpeechService {
    private static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private static let chromiumVersion = "143.0.3650.75"
    private static let gecVersion = "1-143.0.3650.75"
    private static let endpoint = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"

    static func synthesize(
        text: String,
        voice: MicrosoftSpeechVoice,
        rate: Double
    ) async throws -> Data {
        let connectionId = identifier()
        let requestId = identifier()
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "TrustedClientToken", value: trustedClientToken),
            URLQueryItem(name: "ConnectionId", value: connectionId),
            URLQueryItem(name: "Sec-MS-GEC", value: securityToken()),
            URLQueryItem(name: "Sec-MS-GEC-Version", value: gecVersion)
        ]
        guard let url = components?.url else { throw ReaderSpeechError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/\(chromiumVersion)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("muid=\(identifier().uppercased())", forHTTPHeaderField: "Cookie")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer {
            socket.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        let ratePercent = Int(((rate - 1) * 100).rounded())
        let rateValue = ratePercent >= 0 ? "+\(ratePercent)%" : "\(ratePercent)%"
        let requestTimestamp = timestamp()
        let speechConfig = """
        X-Timestamp:\(requestTimestamp)\r
        Content-Type:application/json; charset=utf-8\r
        Path:speech.config\r
        \r
        {"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}
        """
        let ssmlBody = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>"
            + "<voice name='\(voice.rawValue)'><prosody pitch='+0Hz' rate='\(rateValue)' volume='+0%'>"
            + "\(xmlEscaped(text))</prosody></voice></speak>"
        let ssml = """
        X-RequestId:\(requestId)\r
        Content-Type:application/ssml+xml\r
        X-Timestamp:\(requestTimestamp)Z\r
        Path:ssml\r
        \r
        \(ssmlBody)
        """

        do {
            try await socket.send(.string(speechConfig))
            try await socket.send(.string(ssml))
        } catch {
            throw ReaderSpeechError.freeServiceUnavailable(detail: error.localizedDescription)
        }

        var audio = Data()
        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                throw ReaderSpeechError.freeServiceUnavailable(detail: error.localizedDescription)
            }
            switch message {
                case let .data(data):
                    if let chunk = audioPayload(from: data) { audio.append(chunk) }
                case let .string(message):
                    if messagePath(in: message) == "turn.end" {
                        guard !audio.isEmpty else { throw ReaderSpeechError.invalidResponse }
                        return audio
                    }
                @unknown default:
                    break
            }
        }
        throw CancellationError()
    }

    private static func identifier() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func securityToken(date: Date = Date()) -> String {
        let windowsEpochOffset: Int64 = 11_644_473_600
        let unixSeconds = Int64(date.timeIntervalSince1970)
        let roundedSeconds = ((unixSeconds + windowsEpochOffset) / 300) * 300
        let ticks = roundedSeconds * 10_000_000
        let input = Data("\(ticks)\(trustedClientToken)".utf8)
        return SHA256.hash(data: input).map { String(format: "%02X", $0) }.joined()
    }

    static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func timestamp(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return formatter.string(from: date)
    }

    static func audioPayload(from data: Data) -> Data? {
        guard data.count >= 2 else { return nil }
        let headerLength = (Int(data[data.startIndex]) << 8) | Int(data[data.startIndex + 1])
        let headerStart = data.startIndex + 2
        let payloadStart = headerStart + headerLength
        guard payloadStart <= data.endIndex else { return nil }
        guard
            let headers = String(data: data[headerStart..<payloadStart], encoding: .utf8),
            messagePath(in: headers) == "audio"
        else { return nil }
        return Data(data[payloadStart...])
    }

    static func messagePath(in headers: String) -> String? {
        guard let line = headers
            .components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("path:") })
        else { return nil }
        return String(line.dropFirst("path:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

enum ReaderSpeechError: LocalizedError, Equatable {
    case invalidResponse
    case playbackFailed
    case systemVoiceUnavailable
    case freeServiceUnavailable(detail: String?)

    var errorDescription: String? {
        switch self {
            case .invalidResponse:
                readerSpeechLocalized("MICROSOFT_TTS_INVALID_RESPONSE", fallback: "Microsoft returned invalid audio.")
            case .playbackFailed:
                readerSpeechLocalized("MICROSOFT_TTS_PLAYBACK_FAILED", fallback: "Speech playback failed.")
            case .systemVoiceUnavailable:
                readerSpeechLocalized("READER_TTS_SYSTEM_UNAVAILABLE", fallback: "No usable system voice is installed.")
            case let .freeServiceUnavailable(detail):
                let message = readerSpeechLocalized(
                    "MICROSOFT_TTS_FREE_UNAVAILABLE",
                    fallback: "Microsoft online speech is temporarily unavailable."
                )
                detail?.isEmpty == false ? "\(message) (\(detail!))" : message
        }
    }
}

enum ReaderSpeechSegmenter {
    static let unitCharacterLimit = 420

    /// Produces stable, bounded chunks while preserving the page/chapter anchor.
    /// Sentence splitting is intentionally kept separate from extraction so it
    /// can be tested on Windows without AVFoundation or a network connection.
    static func chunks(from segments: [ReaderSpeechSegment]) -> [ReaderSpeechSegment] {
        let fragments = segments.compactMap { segment -> (ReaderSpeechSegment, String)? in
            let text = normalizedText(segment.text)
            return text.isEmpty ? nil : (segment, text)
        }
        guard !fragments.isEmpty else { return [] }

        var combined = ""
        var anchors: [(offset: Int, segment: ReaderSpeechSegment)] = []
        for (segment, text) in fragments {
            if !combined.isEmpty { combined += boundarySeparator(previous: combined, next: text) }
            anchors.append((combined.count, segment))
            combined += text
        }

        var sentences: [(ReaderSpeechSegment, String)] = []
        combined.enumerateSubstrings(
            in: combined.startIndex..<combined.endIndex,
            options: [.bySentences, .substringNotRequired]
        ) { _, range, _, _ in
            let text = String(combined[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let offset = combined.distance(from: combined.startIndex, to: range.lowerBound)
            let anchor = anchors.last(where: { $0.offset <= offset })?.segment ?? fragments[0].0
            sentences.append((anchor, text))
        }
        if sentences.isEmpty { sentences = [(fragments[0].0, combined)] }

        var result: [ReaderSpeechSegment] = []
        var currentText = ""
        var currentAnchor: ReaderSpeechSegment?
        for (anchor, sentence) in sentences {
            for piece in splitLongText(sentence, limit: unitCharacterLimit) {
                if currentText.isEmpty {
                    currentAnchor = anchor
                    currentText = piece
                } else if currentAnchor?.id != anchor.id || currentText.count + piece.count + 1 > unitCharacterLimit {
                    result.append(ReaderSpeechSegment(
                        id: "\(currentAnchor!.id)#\(result.count)",
                        chapterKey: currentAnchor!.chapterKey,
                        pageIndex: currentAnchor!.pageIndex,
                        text: currentText
                    ))
                    currentAnchor = anchor
                    currentText = piece
                } else {
                    currentText += " " + piece
                }
            }
        }
        if let currentAnchor, !currentText.isEmpty {
            result.append(ReaderSpeechSegment(
                id: "\(currentAnchor.id)#\(result.count)",
                chapterKey: currentAnchor.chapterKey,
                pageIndex: currentAnchor.pageIndex,
                text: currentText
            ))
        }
        return result
    }

    static func normalizedText(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[`*_>#]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{FFFC}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boundarySeparator(previous: String, next: String) -> String {
        guard let previousCharacter = previous.last, let nextCharacter = next.first else { return "" }
        return isASCIIAlphaNumeric(previousCharacter) && isASCIIAlphaNumeric(nextCharacter) ? " " : ""
    }

    private static func isASCIIAlphaNumeric(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
        let value = scalar.value
        return (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
    }

    private static func splitLongText(_ text: String, limit: Int) -> [String] {
        guard text.count > limit else { return [text] }
        var result: [String] = []
        var remainder = text[...]
        while !remainder.isEmpty {
            let end = remainder.index(remainder.startIndex, offsetBy: min(limit, remainder.count))
            result.append(String(remainder[..<end]))
            remainder = remainder[end...]
        }
        return result
    }
}

@MainActor
final class ReaderSpeechController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var progressText = ""

    private struct PrefetchedAudio {
        let cacheKey: String
        let data: Data
    }

    var onStateChange: ((State) -> Void)?
    var revealSegment: ((ReaderSpeechSegment) -> Void)?
    var loadMoreSegments: ((String) async -> [ReaderSpeechSegment])?

    private var units: [ReaderSpeechSegment] = []
    private var unitIndex = 0
    private var player: AVAudioPlayer?
    private let systemSynthesizer = AVSpeechSynthesizer()
    private var synthesisTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchedAudio: [Int: PrefetchedAudio] = [:]
    private var audioCache: [String: Data] = [:]
    private var notificationObservers: [NSObjectProtocol] = []
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var pauseRequested = false
    private var usingSystemFallback = false

    private static let prefetchUnitCount = 3

    override init() {
        super.init()
        systemSynthesizer.usesApplicationAudioSession = true
        systemSynthesizer.delegate = self
        observeAudioSession()
    }

    deinit {
        synthesisTask?.cancel()
        prefetchTask?.cancel()
        player?.stop()
        systemSynthesizer.stopSpeaking(at: .immediate)
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        remoteCommandTargets.forEach { $0.0.removeTarget($0.1) }
        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    var isActive: Bool {
        switch state {
            case .idle, .failed: false
            case .loading, .playing, .paused: true
        }
    }

    var currentSegment: ReaderSpeechSegment? {
        guard units.indices.contains(unitIndex) else { return nil }
        return units[unitIndex]
    }

    func start(segments: [ReaderSpeechSegment], settings: ReaderSpeechSettingsStore = .shared) {
        stop()
        units = ReaderSpeechSegmenter.chunks(from: segments)
        guard !units.isEmpty else {
            updateState(.failed(readerSpeechLocalized("MICROSOFT_TTS_NO_TEXT", fallback: "There is no readable text here.")))
            return
        }
        unitIndex = 0
        usingSystemFallback = settings.provider == .system
        playCurrentUnit(settings: settings)
    }

    func toggle(segments: [ReaderSpeechSegment], settings: ReaderSpeechSettingsStore = .shared) {
        switch state {
            case .playing, .loading: pause()
            case .paused: resume(settings: settings)
            case .idle, .failed: start(segments: segments, settings: settings)
        }
    }

    func pause() {
        guard state == .playing || state == .loading else { return }
        pauseRequested = true
        if systemSynthesizer.isSpeaking { systemSynthesizer.pauseSpeaking(at: .immediate) }
        else { player?.pause() }
        updateState(.paused)
        updateNowPlayingPlaybackState()
    }

    func resume(settings: ReaderSpeechSettingsStore = .shared) {
        guard state == .paused else { return }
        pauseRequested = false
        do { try activateAudioSession() }
        catch { fail(error) ; return }
        if systemSynthesizer.isPaused {
            systemSynthesizer.continueSpeaking()
            updateState(.playing)
        } else if let player, player.play() {
            updateState(.playing)
        } else if synthesisTask != nil {
            updateState(.loading)
        } else {
            playCurrentUnit(settings: settings)
        }
        updateNowPlayingPlaybackState()
    }

    func stop() {
        synthesisTask?.cancel()
        synthesisTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        player?.stop()
        player = nil
        systemSynthesizer.stopSpeaking(at: .immediate)
        pauseRequested = false
        usingSystemFallback = false
        units = []
        prefetchedAudio = [:]
        unitIndex = 0
        progressText = ""
        updateState(.idle)
        endBackgroundTask()
        clearRemoteControls()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func playCurrentUnit(settings: ReaderSpeechSettingsStore) {
        guard units.indices.contains(unitIndex) else {
            loadNextBatch(settings: settings)
            return
        }
        let unit = units[unitIndex]
        if unitIndex > 0, units[unitIndex - 1].id != unit.id { revealSegment?(unit) }
        progressText = String(
            format: readerSpeechLocalized("MICROSOFT_TTS_PROGRESS", fallback: "Segment %d/%d"),
            unitIndex + 1,
            units.count
        )
        updateState(.loading)

        if settings.provider == .system || usingSystemFallback {
            do { try beginSystemPlayback(text: unit.text, rate: settings.rate) }
            catch { fail(error) }
            return
        }

        let engine = ReaderMicrosoftSpeechEngine(voice: settings.voice)
        let cacheKey = "\(engine.cacheIdentifier)|\(settings.rate)|\(unit.text)"
        synthesisTask?.cancel()
        beginBackgroundTask()
        synthesisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data: Data
                if let prefetched = prefetchedAudio.removeValue(forKey: unitIndex),
                   prefetched.cacheKey == cacheKey {
                    data = prefetched.data
                } else if let cached = audioCache[cacheKey] {
                    data = cached
                } else {
                    prefetchTask?.cancel()
                    prefetchTask = nil
                    let generated = try await engine.synthesize(.init(text: unit.text, rate: settings.rate))
                    guard !Task.isCancelled else { return }
                    audioCache[cacheKey] = generated
                    data = generated
                }
                guard !Task.isCancelled else { return }
                try beginPlayback(data: data)
                endBackgroundTask()
                prefetchUpcomingUnits(after: unitIndex, settings: settings)
            } catch is CancellationError {
                endBackgroundTask()
            } catch {
                endBackgroundTask()
                guard !Task.isCancelled else { return }
                if settings.allowsSystemFallback {
                    usingSystemFallback = true
                    do { try beginSystemPlayback(text: unit.text, rate: settings.rate) }
                    catch { fail(error) }
                } else {
                    fail(error)
                }
            }
        }
    }

    private func prefetchUpcomingUnits(
        after currentIndex: Int,
        settings: ReaderSpeechSettingsStore
    ) {
        guard settings.provider != .system, !usingSystemFallback else { return }
        let lastIndex = min(units.count - 1, currentIndex + Self.prefetchUnitCount)
        guard currentIndex < lastIndex else { return }

        let indices = Array((currentIndex + 1)...lastIndex)
        let rate = settings.rate
        let engine = ReaderMicrosoftSpeechEngine(voice: settings.voice)

        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            for nextIndex in indices {
                guard !Task.isCancelled, units.indices.contains(nextIndex) else { return }
                let unit = units[nextIndex]
                let cacheKey = "\(engine.cacheIdentifier)|\(rate)|\(unit.text)"
                if prefetchedAudio[nextIndex]?.cacheKey == cacheKey { continue }

                do {
                    let data: Data
                    if let cached = audioCache[cacheKey] {
                        data = cached
                    } else {
                        data = try await engine.synthesize(.init(text: unit.text, rate: rate))
                        guard !Task.isCancelled else { return }
                        audioCache[cacheKey] = data
                    }
                    guard
                        !Task.isCancelled,
                        units.indices.contains(nextIndex),
                        units[nextIndex] == unit
                    else {
                        return
                    }
                    prefetchedAudio[nextIndex] = PrefetchedAudio(cacheKey: cacheKey, data: data)
                } catch {
                    // Prefetch is only an optimization. Normal playback retries
                    // synthesis and reports an error if the retry also fails.
                }
            }
        }
    }

    private func loadNextBatch(settings: ReaderSpeechSettingsStore) {
        guard let chapterKey = units.last?.chapterKey, let loadMoreSegments else {
            finish()
            return
        }
        updateState(.loading)
        progressText = readerSpeechLocalized("MICROSOFT_TTS_LOADING_NEXT", fallback: "Loading next chapter")
        synthesisTask?.cancel()
        beginBackgroundTask()
        synthesisTask = Task { [weak self] in
            guard let self else { return }
            let additional = await loadMoreSegments(chapterKey)
            guard !Task.isCancelled else {
                endBackgroundTask()
                return
            }
            let nextUnits = ReaderSpeechSegmenter.chunks(from: additional)
            guard !nextUnits.isEmpty else { finish(); return }
            units.append(contentsOf: nextUnits)
            synthesisTask = nil
            endBackgroundTask()
            playCurrentUnit(settings: settings)
        }
    }

    private func beginPlayback(data: Data) throws {
        try activateAudioSession()
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        activateRemoteControls()
        if pauseRequested { updateState(.paused) }
        else {
            guard player.play() else { throw ReaderSpeechError.playbackFailed }
            updateState(.playing)
        }
        updateNowPlayingInfo(duration: player.duration, elapsed: player.currentTime)
    }

    private func beginSystemPlayback(text: String, rate: Double) throws {
        guard let voice = AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: Locale.current.languageCode ?? "en-US")
        else { throw ReaderSpeechError.systemVoiceUnavailable }
        try activateAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate))
        )
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        systemSynthesizer.speak(utterance)
        if pauseRequested {
            systemSynthesizer.pauseSpeaking(at: .immediate)
            updateState(.paused)
        } else {
            updateState(.playing)
        }
        activateRemoteControls()
        updateNowPlayingInfo(duration: nil, elapsed: 0)
    }

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [])
        try session.setActive(true, options: [])
    }

    private func advance() {
        player = nil
        unitIndex += 1
        usingSystemFallback = ReaderSpeechSettingsStore.shared.provider == .system
        playCurrentUnit(settings: .shared)
    }

    private func finish() {
        player = nil
        progressText = readerSpeechLocalized("MICROSOFT_TTS_CHAPTER_FINISHED", fallback: "Reading complete")
        updateState(.idle)
        endBackgroundTask()
        clearRemoteControls()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ error: Error) {
        updateState(.failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
        player = nil
        clearRemoteControls()
        endBackgroundTask()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateState(_ newState: State) {
        state = newState
        onStateChange?(newState)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   AVAudioSession.InterruptionType(rawValue: raw) == .began { pause() }
            }
        })
        notificationObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self,
                      let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
                else { return }
                pause()
            }
        })
    }

    private func activateRemoteControls() {
        guard remoteCommandTargets.isEmpty else { updateNowPlayingPlaybackState(); return }
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true
        commands.stopCommand.isEnabled = true
        remoteCommandTargets = [
            (commands.playCommand, commands.playCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.resume() }; return .success
            }),
            (commands.pauseCommand, commands.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.pause() }; return .success
            }),
            (commands.togglePlayPauseCommand, commands.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if state == .playing { pause() } else if state == .paused { resume() }
                }; return .success
            }),
            (commands.stopCommand, commands.stopCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }; return .success
            })
        ]
        updateNowPlayingPlaybackState()
    }

    private func clearRemoteControls() {
        remoteCommandTargets.forEach { $0.0.removeTarget($0.1) }
        remoteCommandTargets.removeAll()
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = false
        commands.pauseCommand.isEnabled = false
        commands.togglePlayPauseCommand.isEnabled = false
        commands.stopCommand.isEnabled = false
        UIApplication.shared.endReceivingRemoteControlEvents()
        let center = MPNowPlayingInfoCenter.default()
        center.playbackState = .stopped
        center.nowPlayingInfo = nil
    }

    private func updateNowPlayingInfo(duration: TimeInterval?, elapsed: TimeInterval) {
        guard units.indices.contains(unitIndex) else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: readerSpeechLocalized("MICROSOFT_TTS_TITLE", fallback: "Aidoku speech"),
            MPMediaItemPropertyArtist: String(units[unitIndex].text.prefix(80)),
            MPMediaItemPropertyAlbumTitle: "Aidoku",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
        ]
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = state == .playing ? .playing : .paused
    }

    private func updateNowPlayingPlaybackState() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let player {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
            info[MPMediaItemPropertyPlaybackDuration] = player.duration
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? 1.0 : 0.0
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = state == .playing ? .playing : .paused
    }

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Reader speech synthesis") { [weak self] in
            Task { @MainActor [weak self] in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

extension ReaderSpeechController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if flag { advance() } else { fail(ReaderSpeechError.playbackFailed) }
        }
    }
}

extension ReaderSpeechController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.advance() }
    }
}

@MainActor
struct ReaderSpeechControlView: View {
    @ObservedObject var controller: ReaderSpeechController
    @ObservedObject var settings: ReaderSpeechSettingsStore
    let segments: () -> [ReaderSpeechSegment]
    let onDone: () -> Void

    var body: some View {
        PlatformNavigationStack {
            Form {
                Section {
                    Picker(
                        readerSpeechLocalized("READER_TTS_ENGINE", fallback: "Speech engine"),
                        selection: $settings.provider
                    ) {
                        ForEach(ReaderSpeechProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    Toggle(
                        readerSpeechLocalized("READER_TTS_FALLBACK", fallback: "Use Apple speech if online fails"),
                        isOn: $settings.allowsSystemFallback
                    )
                }

                if settings.provider == .microsoft {
                    Picker(
                        readerSpeechLocalized("MICROSOFT_TTS_VOICE", fallback: "Voice"),
                        selection: $settings.voice
                    ) {
                        ForEach(MicrosoftSpeechVoice.allCases) { voice in
                            Text(voice.title).tag(voice)
                        }
                    }
                }

                Section {
                    HStack {
                        Text(readerSpeechLocalized("MICROSOFT_TTS_RATE", fallback: "Rate"))
                        Spacer()
                        Text(String(format: "%.1fx", settings.rate)).foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.rate, in: 0.6...1.6, step: 0.1)
                }

                Section {
                    if !controller.progressText.isEmpty {
                        Text(controller.progressText).foregroundStyle(.secondary)
                    }
                    if case let .failed(message) = controller.state {
                        Text(message).foregroundStyle(.red)
                    }
                    HStack(spacing: 12) {
                        Button {
                            controller.toggle(segments: segments(), settings: settings)
                        } label: {
                            Label(playTitle, systemImage: playImage)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.state == .loading && !controller.isActive)

                        Button(role: .destructive) {
                            controller.stop()
                        } label: {
                            Label(
                                readerSpeechLocalized("MICROSOFT_TTS_STOP", fallback: "Stop"),
                                systemImage: "stop.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!controller.isActive)
                    }
                } header: {
                    Text(readerSpeechLocalized("MICROSOFT_TTS_PLAYBACK", fallback: "Playback"))
                } footer: {
                    Text(readerSpeechLocalized(
                        "MICROSOFT_TTS_FREE_INFO",
                        fallback: "Microsoft speech sends the selected text to its online service. Apple speech is used as the offline fallback."
                    ))
                }
            }
            .navigationTitle(readerSpeechLocalized("MICROSOFT_TTS_TITLE", fallback: "Aidoku speech"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(readerSpeechLocalized("DONE", fallback: "Done"), action: onDone)
                }
            }
        }
    }

    private var playTitle: String {
        switch controller.state {
            case .playing: readerSpeechLocalized("MICROSOFT_TTS_PAUSE", fallback: "Pause")
            case .paused: readerSpeechLocalized("MICROSOFT_TTS_RESUME", fallback: "Resume")
            case .loading: readerSpeechLocalized("MICROSOFT_TTS_LOADING", fallback: "Preparing")
            case .idle, .failed: readerSpeechLocalized("MICROSOFT_TTS_START", fallback: "Start reading aloud")
        }
    }

    private var playImage: String {
        switch controller.state {
            case .playing: "pause.fill"
            case .loading: "waveform"
            case .idle, .paused, .failed: "play.fill"
        }
    }
}
