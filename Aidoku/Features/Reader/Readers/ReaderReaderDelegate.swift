//
//  ReaderReaderDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/16/22.
//

import UIKit
import AidokuRunner

@MainActor
// swiftlint:disable:next class_delegate_protocol
protocol ReaderReaderDelegate: UIViewController {
    var readingMode: ReadingMode { get set }
    var delegate: ReaderHoldingDelegate? { get set }

    func moveLeft()
    func moveRight()
    func toggleOffset()

    func sliderMoved(value: CGFloat)
    func sliderStopped(value: CGFloat)
    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int)
}

extension ReaderReaderDelegate {
    func toggleOffset() {
        // do nothing by default
    }
}

/// Paged text keeps its normal tap path separate from temporary UIKit text selection.
/// In reading mode the page text views do not participate in hit testing; selection
/// mode is entered only after the reader's dedicated long press has succeeded.
enum PagedTextInteractionMode: Equatable {
    case reading
    case selecting

    var allowsPageNavigation: Bool {
        self == .reading
    }

    mutating func beginSelection() {
        self = .selecting
    }

    @discardableResult
    mutating func endSelection() -> Bool {
        guard self == .selecting else { return false }
        self = .reading
        return true
    }
}

@MainActor
protocol ReaderTextSelectionHandling: AnyObject {
    var isTextSelectionActive: Bool { get }

    @discardableResult
    func dismissTextSelection() -> Bool
}

/// A reader that can be driven by the reader-level automatic scrolling control.
/// Image readers and text readers share the control, while each implementation
/// remains responsible for its own scroll geometry and lifecycle.
@MainActor
protocol ReaderAutoScrolling: AnyObject {
    var isAutoScrolling: Bool { get }
    var autoScrollingDidReachEnd: (() -> Void)? { get set }

    func startAutoScrolling(speed: Double)
    func updateAutoScrollingSpeed(_ speed: Double)
    func pauseAutoScrolling()
    func resumeAutoScrolling()
    func stopAutoScrolling()
}

@available(iOS 18.0, *)
protocol ReaderDictionaryReader: ReaderReaderDelegate {
    /// Returns recognized text at the given point (in the reader's view coordinates)
    /// along with the character rect for popup positioning and per-character rects for highlighting.
    func recognizedText(at point: CGPoint) -> TextRecognizer.Result?
    func setDictionaryOverlayTapHandler(_ handler: ((String, String, CGRect, [CGRect]) -> Void)?)
    func setDictionaryOverlayInteractionMode(_ mode: DictionaryOverlayInteractionMode)
    func dismissActiveDictionaryOverlay() -> Bool
}
