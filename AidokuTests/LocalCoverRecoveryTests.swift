//
//  LocalCoverRecoveryTests.swift
//  AidokuTests
//

import Foundation
import Testing
@testable import Aidoku

@Suite struct LocalCoverRecoveryTests {
    @Test("Stable local cover URL resolves inside the current Documents container")
    func resolvesStableCoverURL() throws {
        let storedURL = try #require(URL(string: "aidoku-image:///Local/Test%20Book/cover.png"))
        let expectedURL = FileManager.default.documentDirectory
            .appendingPathComponent("Local/Test Book/cover.png")

        #expect(LocalCoverRecovery.fileURL(for: storedURL).standardizedFileURL == expectedURL.standardizedFileURL)
    }

    @Test("Recovered cover is stored without the app container path")
    func storesStableCoverURL() throws {
        let coverURL = FileManager.default.documentDirectory
            .appendingPathComponent("Local/Test Book/cover.png")
        let storedURL = try #require(LocalCoverRecovery.stableURLString(for: coverURL))

        #expect(storedURL == "aidoku-image:///Local/Test%20Book/cover.png")
        #expect(!storedURL.contains(FileManager.default.documentDirectory.path))
    }

    @Test("Non-local file URLs remain unchanged when checking existence")
    func preservesRegularFileURL() {
        let fileURL = URL(fileURLWithPath: "/tmp/cover.png")

        #expect(LocalCoverRecovery.fileURL(for: fileURL) == fileURL)
    }
}
