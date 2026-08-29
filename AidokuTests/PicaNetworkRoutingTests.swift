//
//  PicaNetworkRoutingTests.swift
//  AidokuTests
//

import Foundation
import Testing
@testable import Aidoku

@Suite(.serialized) struct PicaNetworkRoutingTests {
    @Test("Pica routing is limited to Picacomic hosts and enabled channels")
    func routeScope() throws {
        let defaults = UserDefaults.standard
        let key = "\(PicaNetworkRouting.sourceId).appChannel"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set("2", forKey: key)
        #expect(PicaNetworkRouting.shouldRoute(URLRequest(url: try #require(URL(string: "https://api.picacomic.com/comics")))))
        #expect(!PicaNetworkRouting.shouldRoute(URLRequest(url: try #require(URL(string: "https://example.com/comics")))))

        defaults.set("1", forKey: key)
        #expect(!PicaNetworkRouting.shouldRoute(URLRequest(url: try #require(URL(string: "https://api.picacomic.com/comics")))))
    }
}
