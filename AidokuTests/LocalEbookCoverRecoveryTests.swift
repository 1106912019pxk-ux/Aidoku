//
//  LocalEbookCoverRecoveryTests.swift
//  AidokuTests
//

import Foundation
import Testing
import ZIPFoundation
@testable import Aidoku

@Suite struct LocalEbookCoverRecoveryTests {
    @Test("Stable cover URLs survive a Documents container change")
    func stableURLSurvivesContainerChange() throws {
        let oldDocuments = URL(fileURLWithPath: "/old/App/Documents", isDirectory: true)
        let newDocuments = URL(fileURLWithPath: "/new/App/Documents", isDirectory: true)
        let oldCover = oldDocuments.appendingPathComponent("Local/Test Book/cover.png")
        let stableURL = try #require(
            LocalEbookCoverRecovery.stableURL(for: oldCover, documentsDirectory: oldDocuments)
        )

        #expect(stableURL.absoluteString == "aidoku-image:///Local/Test%20Book/cover.png")
        #expect(
            LocalEbookCoverRecovery.resolvedFileURL(
                for: stableURL,
                documentsDirectory: newDocuments
            ).standardizedFileURL
                == newDocuments.appendingPathComponent("Local/Test Book/cover.png").standardizedFileURL
        )
    }

    @Test("Recovery finds normalized folders and case-insensitive cover names")
    func findsExistingCover() throws {
        let documents = try makeTemporaryDocuments()
        defer { try? FileManager.default.removeItem(at: documents) }
        let localFolder = documents.appendingPathComponent("Local", isDirectory: true)
        let mangaFolder = localFolder.appendingPathComponent("Café", isDirectory: true)
        try FileManager.default.createDirectory(at: mangaFolder, withIntermediateDirectories: true)
        let coverURL = mangaFolder.appendingPathComponent("Cover.PNG")
        try Data([0x01]).write(to: coverURL)

        let foundFolder = try #require(
            LocalEbookCoverRecovery.mangaFolder(for: "Cafe\u{301}", in: localFolder)
        )
        let foundCover = try #require(LocalEbookCoverRecovery.existingCoverFile(in: foundFolder))

        #expect(foundFolder.standardizedFileURL == mangaFolder.standardizedFileURL)
        #expect(foundCover.standardizedFileURL == coverURL.standardizedFileURL)
    }

    @Test("Missing cover file is rebuilt from the embedded EPUB cover")
    func rebuildsEmbeddedEpubCover() throws {
        let documents = try makeTemporaryDocuments()
        defer { try? FileManager.default.removeItem(at: documents) }
        let mangaFolder = documents.appendingPathComponent("Local/Test Book", isDirectory: true)
        try FileManager.default.createDirectory(at: mangaFolder, withIntermediateDirectories: true)
        try makeEpub(at: mangaFolder.appendingPathComponent("book.epub"))

        let recoveredCover = try #require(LocalEbookCoverRecovery.recoverCoverFile(in: mangaFolder))

        #expect(recoveredCover.lastPathComponent == "cover.png")
        #expect(recoveredCover.exists)
        #expect((try Data(contentsOf: recoveredCover)).count > 0)
    }

    private func makeTemporaryDocuments() throws -> URL {
        let documents = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    private func makeEpub(at url: URL) throws {
        let archive = try Archive(url: url, accessMode: .create)
        try add(
            "META-INF/container.xml",
            data: Data(
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
                  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
                </container>
                """.utf8
            ),
            to: archive
        )
        try add(
            "OEBPS/content.opf",
            data: Data(
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
                  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Test Book</dc:title></metadata>
                  <manifest>
                    <item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>
                    <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
                  </manifest>
                  <spine><itemref idref="chapter"/></spine>
                </package>
                """.utf8
            ),
            to: archive
        )
        try add(
            "OEBPS/chapter.xhtml",
            data: Data("<html xmlns=\"http://www.w3.org/1999/xhtml\"><body>Text</body></html>".utf8),
            to: archive
        )
        let png = try #require(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
        )
        try add("OEBPS/cover.png", data: png, to: archive)
    }

    private func add(_ path: String, data: Data, to archive: Archive) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            provider: { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        )
    }
}
