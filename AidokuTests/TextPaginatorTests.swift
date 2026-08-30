//
//  TextPaginatorTests.swift
//  Aidoku
//

import Testing
import UIKit
@testable import Aidoku

@Suite struct TextPaginatorTests {
    private let pageSize = CGSize(width: 320, height: 480)

    @Test("Text with emoji after sentence breaks paginates without crashing")
    func paginateEmojiAfterSentenceBreak() {
        // Regression test: the sentence-break search reads the UTF-16 code unit
        // following a sentence ender; when that character is an emoji (surrogate
        // pair), UnicodeScalar(UInt16) is nil and was previously force-unwrapped.
        // A single paragraph (no newlines) forces the sentence-break path.
        let sentence = "Some words that fill space before the period.\u{1F600} And then more words follow here. "
        let markdown = String(repeating: sentence, count: 200)
            .replacingOccurrences(of: "\n", with: " ")

        let paginator = TextPaginator()
        let pages = paginator.paginate(markdown: markdown, pageSize: pageSize)

        #expect(!pages.isEmpty)
        #expect(pages.count > 1)
    }

    @Test("Page ranges are contiguous and cover the whole text")
    func pageRangesAreContiguous() {
        let markdown = String(repeating: "A reasonably long paragraph of plain text to fill several pages.\n\n", count: 100)

        let paginator = TextPaginator()
        let pages = paginator.paginate(markdown: markdown, pageSize: pageSize)

        #expect(pages.count > 1)
        for (index, page) in pages.enumerated() {
            #expect(page.id == index)
            #expect(page.range.length > 0)
            if index > 0 {
                let previous = pages[index - 1]
                #expect(page.range.location == previous.range.location + previous.range.length)
            }
        }
    }

    @Test("Empty markdown does not crash")
    func paginateEmptyMarkdown() {
        let paginator = TextPaginator()
        _ = paginator.paginate(markdown: "", pageSize: pageSize)
    }

    @Test("Independent margins add to the existing horizontal padding")
    func asymmetricPaddingChangesContentSize() {
        var config = PaginationConfig()
        config.horizontalPadding = 20
        config.leftMargin = 12
        config.rightMargin = 28
        config.topPadding = 30
        config.bottomPadding = 50

        let size = TextPaginator(config: config).contentSize(for: pageSize)

        #expect(size.width == 240)
        #expect(size.height == 400)
    }

    @Test("Local TXT chapters use plain-text pagination")
    func localTxtUsesPlainTextPagination() {
        #expect(TextContentFormat.forLocalChapter(key: "book.txt/chapter-1") == .plainText)
        #expect(TextContentFormat.forLocalChapter(key: "book.epub/chapter-1.xhtml") == .markdown)
        #expect(TextContentFormat.forLocalChapter(key: nil) == .markdown)
    }

    @Test("Indented TXT body keeps the selected body font")
    func indentedTxtKeepsSelectedFont() throws {
        var config = PaginationConfig()
        config.fontWeight = .medium
        let text = "章节标题\n\n    中文正文保留行首空格"
        let pages = TextPaginator(config: config).paginate(
            markdown: text,
            pageSize: pageSize,
            format: .plainText
        )
        let page = try #require(pages.first)
        let bodyLocation = (page.attributedContent.string as NSString).range(of: "中文正文").location
        try #require(bodyLocation != NSNotFound)
        let bodyFont = try #require(
            page.attributedContent.attribute(.font, at: bodyLocation, effectiveRange: nil) as? UIFont
        )

        #expect(page.attributedContent.string == text)
        #expect(bodyFont.fontName == config.font.fontName)
    }

    @Test("First-line indent is measured in selected-font characters")
    func firstLineIndentUsesFontSize() {
        var config = PaginationConfig()
        config.fontSize = 18
        config.firstLineIndent = 2

        #expect(config.paragraphStyle.firstLineHeadIndent == 36)
    }

    @Test("A font family selection resolves to an installable face")
    func fontFamilyResolvesToFace() throws {
        #expect(TextReaderFontResolver.resolvedName(for: "System") == nil)

        let family = try #require(UIFont.familyNames.first)
        let resolvedName = try #require(TextReaderFontResolver.resolvedName(for: family))
        #expect(UIFont(name: resolvedName, size: 16) != nil)
    }

    @Test("Body weight exposes five real settings")
    func bodyWeightHasFiveLevels() {
        #expect(TextReaderFontWeight.allCases.map(\.rawValue) == [
            "light", "regular", "medium", "semibold", "bold"
        ])

        let regular = TextReaderFontResolver.font(for: "System", size: 16, weight: .regular)
        let bold = TextReaderFontResolver.font(for: "System", size: 16, weight: .bold)
        #expect(descriptorWeight(of: bold) > descriptorWeight(of: regular))
    }

    private func descriptorWeight(of font: UIFont) -> CGFloat {
        guard
            let traits = font.fontDescriptor.object(forKey: .traits)
                as? [UIFontDescriptor.TraitKey: Any],
            let value = traits[.weight] as? NSNumber
        else {
            return UIFont.Weight.regular.rawValue
        }
        return CGFloat(truncating: value)
    }
}
