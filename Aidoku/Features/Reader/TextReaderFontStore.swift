//
//  TextReaderFontStore.swift
//  Aidoku
//

import CoreText
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Registers fonts imported by the text reader. The legacy directory is kept so
/// fonts survive an in-place update from the previous personal build.
@MainActor
final class TextReaderFontStore: ObservableObject {
    struct FontOption: Identifiable, Hashable {
        let name: String
        let imported: Bool

        var id: String { name }
    }

    static let shared = TextReaderFontStore()

    @Published private(set) var options: [FontOption] = []

    private let fileManager = FileManager.default
    private var legacyFamilyIdentifiers: [String: String] = [:]

    private var fontDirectory: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("EBooks", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)
    }

    private init() {
        refresh()
    }

    /// Resolves the family-name value stored by older builds to the concrete
    /// PostScript identifier used by the current picker.
    func identifier(forLegacyFamily familyName: String) -> String? {
        legacyFamilyIdentifiers[familyName]
    }

    func refresh() {
        let importedFonts = registerStoredFonts()
        legacyFamilyIdentifiers = Dictionary(
            importedFonts.map { ($0.familyName, $0.identifier) },
            uniquingKeysWith: { first, _ in first }
        )
        if
            let storedSelection = UserDefaults.standard.string(forKey: "Reader.textFontFamily"),
            let identifier = legacyFamilyIdentifiers[storedSelection],
            storedSelection != identifier
        {
            UserDefaults.standard.set(identifier, forKey: "Reader.textFontFamily")
            NotificationCenter.default.post(name: .init("Reader.textFontFamily"), object: identifier)
        }
        let importedNames = Set(importedFonts.map(\.identifier))
        let systemNames = UIFont.familyNames
            .filter { !importedNames.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        options = [FontOption(name: "System", imported: false)]
            + importedNames.sorted().map { FontOption(name: $0, imported: true) }
            + systemNames.map { FontOption(name: $0, imported: false) }
    }

    @discardableResult
    func importFonts(from urls: [URL]) -> String? {
        guard let directory = fontDirectory else { return nil }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var firstImportedName: String?
        for url in urls where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            var destination = directory.appendingPathComponent(url.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                destination = directory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            }

            do {
                try fileManager.copyItem(at: url, to: destination)
                CTFontManagerRegisterFontsForURL(destination as CFURL, .process, nil)
                firstImportedName = firstImportedName ?? Self.postScriptName(for: destination)
            } catch {
                LogManager.logger.error("Unable to import text reader font: \(error)")
            }
        }

        refresh()
        if let firstImportedName {
            UserDefaults.standard.set(firstImportedName, forKey: "Reader.textFontFamily")
            NotificationCenter.default.post(name: .init("Reader.textFontFamily"), object: firstImportedName)
        }
        return firstImportedName
    }

    private func registerStoredFonts() -> [(identifier: String, familyName: String)] {
        guard let directory = fontDirectory else { return [] }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            guard ["ttf", "otf"].contains(url.pathExtension.lowercased()) else { return nil }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            guard let identifier = Self.postScriptName(for: url) else { return nil }
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
            let familyName = descriptors?.first.flatMap {
                CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
            } ?? identifier
            return (identifier, familyName)
        }
    }

    private static func postScriptName(for url: URL) -> String? {
        guard
            let provider = CGDataProvider(url: url as CFURL),
            let font = CGFont(provider),
            let name = font.postScriptName
        else {
            return nil
        }
        return name as String
    }
}

@MainActor
struct TextReaderFontSettingView: View {
    let title: String

    @AppStorage("Reader.textFontFamily") private var selection = "System"
    @ObservedObject private var store = TextReaderFontStore.shared
    @State private var showImporter = false

    var body: some View {
        NavigationLink {
            List {
                if store.options.contains(where: \.imported) {
                    fontSection(
                        store.options.filter(\.imported),
                        title: textReaderLocalized("IMPORTED_FONTS", fallback: "Imported Fonts")
                    )
                }
                fontSection(store.options.filter { !$0.imported }, title: nil)

                Button {
                    showImporter = true
                } label: {
                    Label(
                        textReaderLocalized("IMPORT_TTF_OTF_FONT", fallback: "Import TTF/OTF Font"),
                        systemImage: "text.badge.plus"
                    )
                }
            }
            .navigationTitle(title)
            .onAppear { store.refresh() }
            .sheet(isPresented: $showImporter) {
                DocumentPickerView(
                    allowedContentTypes: [
                        UTType(filenameExtension: "ttf") ?? .data,
                        UTType(filenameExtension: "otf") ?? .data
                    ],
                    allowsMultipleSelection: true
                ) { urls in
                    showImporter = false
                    _ = store.importFonts(from: urls)
                }
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(selection)
                    .foregroundStyle(Color.secondaryLabel)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func fontSection(_ options: [TextReaderFontStore.FontOption], title: String?) -> some View {
        Section {
            ForEach(options) { option in
                Button {
                    selection = option.name
                    NotificationCenter.default.post(name: .init("Reader.textFontFamily"), object: option.name)
                } label: {
                    HStack {
                        Text(option.name)
                        Spacer()
                        if selection == option.name {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        } header: {
            if let title { Text(title) }
        }
    }
}
