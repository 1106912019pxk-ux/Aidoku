//
//  ReaderSpeechTests.swift
//  Aidoku
//

import Foundation
import Testing
@testable import Aidoku

@Suite struct ReaderSpeechTests {
    @Test("Speech normalization removes images and collapses whitespace")
    func normalizesMarkdownText() {
        let text = ReaderSpeechSegmenter.normalizedText(
            "  第一段\n\n![cover](cover.png)   第二段  "
        )

        #expect(text == "第一段 第二段")
    }

    @Test("Speech chunks stay bounded and retain page anchors")
    func chunksStayBounded() {
        let source = ReaderSpeechSegment(
            id: "page-3",
            chapterKey: "chapter-a",
            pageIndex: 3,
            text: String(repeating: "这是一段用于朗读分段的文字。", count: 80)
        )

        let chunks = ReaderSpeechSegmenter.chunks(from: [source])

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.text.count <= ReaderSpeechSegmenter.unitCharacterLimit })
        #expect(chunks.allSatisfy { $0.chapterKey == "chapter-a" && $0.pageIndex == 3 })
        #expect(Set(chunks.map(\.id)).count == chunks.count)
    }

    @Test("Speech chunks add a separator between adjacent ASCII fragments")
    func separatesAsciiFragments() {
        let first = ReaderSpeechSegment(id: "a", chapterKey: "c", pageIndex: 0, text: "chapter")
        let second = ReaderSpeechSegment(id: "b", chapterKey: "c", pageIndex: 1, text: "two")

        let chunks = ReaderSpeechSegmenter.chunks(from: [first, second])

        #expect(chunks.count == 1)
        #expect(chunks[0].text == "chapter two")
    }

    @Test("Microsoft message helpers reject malformed audio frames")
    func parsesAudioFramesSafely() {
        #expect(MicrosoftSpeechService.messagePath(in: "Path:audio\r\n") == "audio")
        #expect(MicrosoftSpeechService.messagePath(in: "Content-Type:text/plain\r\n") == nil)
        #expect(MicrosoftSpeechService.audioPayload(from: Data([0, 10, 1, 2])) == nil)

        let header = Data("Path:audio\r\n".utf8)
        let payload = Data([9, 8, 7])
        var frame = Data([UInt8(header.count >> 8), UInt8(header.count & 0xff)])
        frame.append(header)
        frame.append(payload)

        #expect(MicrosoftSpeechService.audioPayload(from: frame) == payload)
    }

    @Test("Microsoft request text is XML escaped")
    func escapesSsmlText() {
        #expect(
            MicrosoftSpeechService.xmlEscaped("A&B <C> \"D\" 'E'")
                == "A&amp;B &lt;C&gt; &quot;D&quot; &apos;E&apos;"
        )
    }

    @Test("Microsoft security token is deterministic for a fixed time")
    func securityTokenIsStable() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = MicrosoftSpeechService.securityToken(date: date)
        let second = MicrosoftSpeechService.securityToken(date: date)

        #expect(first == second)
        #expect(first.range(of: "^[0-9A-F]{64}$", options: .regularExpression) != nil)
    }

    @Test("Next speech batch retries after foreground activation")
    func nextBatchRetriesAfterForegroundActivation() {
        var state = ReaderSpeechNextBatchRecoveryState()
        state.beginLoading(after: "chapter-4")

        #expect(state.takeForegroundRetryChapterKey() == "chapter-4")
        #expect(state.takeForegroundRetryChapterKey() == nil)
    }

    @Test("Expired next speech batch retains its chapter anchor")
    func expiredNextBatchRetainsAnchor() {
        var state = ReaderSpeechNextBatchRecoveryState()
        state.beginLoading(after: "chapter-4")

        #expect(state.deferUntilForeground())
        #expect(state.takeForegroundRetryChapterKey() == "chapter-4")
    }

    @Test("Completed or stopped speech batch does not restart")
    func completedBatchDoesNotRestart() {
        var state = ReaderSpeechNextBatchRecoveryState()
        state.beginLoading(after: "chapter-4")
        state.complete()

        #expect(!state.deferUntilForeground())
        #expect(state.takeForegroundRetryChapterKey() == nil)
    }
}
