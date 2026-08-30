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

enum TextReaderFontWeight: String, CaseIterable {
    case light
    case regular
    case medium
    case semibold
    case bold

    static var current: TextReaderFontWeight {
        UserDefaults.standard.string(forKey: "Reader.textFontWeight")
            .flatMap(TextReaderFontWeight.init(rawValue:)) ?? .regular
    }

    var title: String {
        switch self {
            case .light: textReaderLocalized("TEXT_FONT_WEIGHT_LIGHT", fallback: "Light")
            case .regular: textReaderLocalized("TEXT_FONT_WEIGHT_REGULAR", fallback: "Regular")
            case .medium: textReaderLocalized("TEXT_FONT_WEIGHT_MEDIUM", fallback: "Medium")
            case .semibold: textReaderLocalized("TEXT_FONT_WEIGHT_SEMIBOLD", fallback: "Semibold")
            case .bold: textReaderLocalized("TEXT_FONT_WEIGHT_BOLD", fallback: "Bold")
        }
    }

    var uiWeight: UIFont.Weight {
        switch self {
            case .light: .light
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
        }
    }

    /// A stronger semantic level for headings and emphasized text.
    var emphasized: TextReaderFontWeight {
        switch self {
            case .light: .medium
            case .regular: .semibold
            case .medium, .semibold, .bold: .bold
        }
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

    static func font(
        for selection: String,
        size: CGFloat,
        weight: TextReaderFontWeight = .regular
    ) -> UIFont {
        guard let name = resolvedName(for: selection), let baseFont = UIFont(name: name, size: size) else {
            return UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        }

        let familyNames = UIFont.fontNames(forFamilyName: baseFont.familyName)
        var candidates = [baseFont]
        candidates.append(contentsOf: familyNames.compactMap { fontName in
            guard fontName != baseFont.fontName else { return nil }
            return UIFont(name: fontName, size: size)
        })

        // Prefer upright faces for body text. If a family only exposes italic
        // faces, retain them instead of silently switching to the system font.
        let uprightCandidates = candidates.filter {
            !$0.fontDescriptor.symbolicTraits.contains(.traitItalic)
        }
        let availableCandidates = uprightCandidates.isEmpty ? candidates : uprightCandidates
        let targetWeight = weight.uiWeight.rawValue

        // Select the nearest face the family actually provides. This avoids
        // synthesizing an in-between weight for single-face imported fonts.
        return availableCandidates.min { lhs, rhs in
            abs(descriptorWeight(of: lhs) - targetWeight) < abs(descriptorWeight(of: rhs) - targetWeight)
        } ?? baseFont
    }

    private static func descriptorWeight(of font: UIFont) -> CGFloat {
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
