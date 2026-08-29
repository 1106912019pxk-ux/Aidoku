//
//  MarkdownView.swift
//  Aidoku
//
//  Created by Skitty on 5/20/25.
//

import MarkdownUI
import SwiftUI

struct MarkdownView: View {
    @State private var markdownString: String
    @State private var safariUrl: URL?
    @State private var showSafari = false

    let fontFamily: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let paragraphSpacing: CGFloat
    let theme: TextReaderTheme

    init(
        _ markdownString: String,
        fontFamily: String = "System",
        fontSize: CGFloat = 18,
        lineSpacing: CGFloat = 8,
        horizontalPadding: CGFloat = 16,
        topPadding: CGFloat = 32,
        bottomPadding: CGFloat = 32,
        paragraphSpacing: CGFloat = 12,
        firstLineIndent: CGFloat = 0,
        theme: TextReaderTheme = .current
    ) {
        self.markdownString = Self.indentParagraphs(in: markdownString, by: firstLineIndent)
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.paragraphSpacing = paragraphSpacing
        self.theme = theme
    }

    private var resolvedFontFamily: String {
        TextReaderFontResolver.resolvedName(for: fontFamily) ?? ".AppleSystemUIFont"
    }

    var body: some View {
        Markdown {
            markdownString
        }
        .markdownImageProvider(LocalFileImageProvider())
        .markdownTextStyle {
            FontFamily(.custom(resolvedFontFamily))
            FontSize(fontSize)
        }
        .markdownBlockStyle(\.paragraph) { configuration in
            configuration.label
                .lineSpacing(lineSpacing)
                .padding(.bottom, paragraphSpacing)
        }
        .environment(
            \.openURL,
            OpenURLAction { url in
                if url.scheme == "http" || url.scheme == "https" {
                    safariUrl = url
                    showSafari = true
                }
                return .handled
            }
        )
        .foregroundStyle(Color(uiColor: theme.foregroundColor))
        .textSelection(.enabled)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .background(Color(uiColor: theme.backgroundColor))
        .fullScreenCover(isPresented: $showSafari) {
            SafariView(url: $safariUrl)
                .ignoresSafeArea()
        }
    }

    /// MarkdownUI has no first-line-indent modifier. Prefix only ordinary prose
    /// paragraphs so headings, lists, quotes and images retain their native layout.
    private static func indentParagraphs(in markdown: String, by indent: CGFloat) -> String {
        let count = max(0, Int(indent.rounded()))
        guard count > 0 else { return markdown }
        let prefix = String(repeating: "　", count: count)
        var startsParagraph = true

        return markdown.components(separatedBy: .newlines).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            defer { startsParagraph = trimmed.isEmpty }
            guard startsParagraph, !trimmed.isEmpty, isPlainParagraph(trimmed) else { return line }
            return prefix + line
        }.joined(separator: "\n")
    }

    private static func isPlainParagraph(_ line: String) -> Bool {
        let markdownPrefixes = ["#", ">", "- ", "* ", "+ ", "![", "```", "~~~", "<"]
        if markdownPrefixes.contains(where: { line.hasPrefix($0) }) { return false }
        if line.first?.isNumber == true,
           line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }
}

/// Loads file urls (e.g. images extracted from epubs) directly from disk,
/// since the default provider only handles network urls.
private struct LocalFileImageProvider: ImageProvider {
    @ViewBuilder
    func makeImage(url: URL?) -> some View {
        if let url, url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            DefaultImageProvider.default.makeImage(url: url)
        }
    }
}
