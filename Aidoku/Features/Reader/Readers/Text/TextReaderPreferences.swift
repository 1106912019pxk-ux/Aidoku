//
//  TextReaderPreferences.swift
//  Aidoku
//

import UIKit

func textReaderLocalized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
}

enum TextReaderTheme: String, CaseIterable {
    case system
    case white
    case warmPaper
    case softGreen
    case mistBlue
    case softGray
    case black

    static var current: TextReaderTheme {
        UserDefaults.standard.string(forKey: "Reader.textBackgroundColor")
            .flatMap(TextReaderTheme.init(rawValue:)) ?? .system
    }

    var title: String {
        switch self {
            case .system: textReaderLocalized("TEXT_BACKGROUND_SYSTEM", fallback: "Follow System")
            case .white: textReaderLocalized("TEXT_BACKGROUND_WHITE", fallback: "White")
            case .warmPaper: textReaderLocalized("TEXT_BACKGROUND_WARM_PAPER", fallback: "Warm Paper")
            case .softGreen: textReaderLocalized("TEXT_BACKGROUND_SOFT_GREEN", fallback: "Soft Green")
            case .mistBlue: textReaderLocalized("TEXT_BACKGROUND_MIST_BLUE", fallback: "Mist Blue")
            case .softGray: textReaderLocalized("TEXT_BACKGROUND_SOFT_GRAY", fallback: "Soft Gray")
            case .black: textReaderLocalized("TEXT_BACKGROUND_BLACK", fallback: "Black")
        }
    }

    var backgroundColor: UIColor {
        switch self {
            case .system: .systemBackground
            case .white: .white
            case .warmPaper: UIColor(red: 0.969, green: 0.941, blue: 0.855, alpha: 1)
            case .softGreen: UIColor(red: 0.910, green: 0.949, blue: 0.898, alpha: 1)
            case .mistBlue: UIColor(red: 0.902, green: 0.933, blue: 0.957, alpha: 1)
            case .softGray: UIColor(red: 0.910, green: 0.898, blue: 0.871, alpha: 1)
            case .black: UIColor(red: 0.055, green: 0.055, blue: 0.059, alpha: 1)
        }
    }

    var foregroundColor: UIColor {
        switch self {
            case .system: .label
            case .black: UIColor(white: 0.92, alpha: 1)
            default: UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1)
        }
    }

    var secondaryForegroundColor: UIColor {
        foregroundColor.withAlphaComponent(0.65)
    }
}

/// Resolves a font-picker family name to a concrete PostScript face.
enum TextReaderFontResolver {
    static func resolvedName(for selection: String) -> String? {
        guard selection != "System", selection != "San Francisco" else { return nil }
        if UIFont(name: selection, size: 16) != nil {
            return selection
        }

        let names = UIFont.fontNames(forFamilyName: selection)
        guard !names.isEmpty else { return nil }
        let preferredSuffixes = ["-regular", " regular", "-roman", " roman", "-book", " book"]
        if let regular = names.first(where: { name in
            preferredSuffixes.contains { name.lowercased().hasSuffix($0) }
        }) {
            return regular
        }

        let styledTokens = ["bold", "italic", "oblique", "semibold", "heavy", "black", "light", "thin"]
        return names.first(where: { name in
            let lowercased = name.lowercased()
            return !styledTokens.contains { lowercased.contains($0) }
        }) ?? names[0]
    }

    static func font(for selection: String, size: CGFloat, bold: Bool = false) -> UIFont {
        guard let name = resolvedName(for: selection), let baseFont = UIFont(name: name, size: size) else {
            return UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
        guard bold, let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) else {
            return baseFont
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}
