//
//  TextSinglePageViewController.swift
//  Aidoku
//

import UIKit

@MainActor
protocol PagedTextSelectionPresenting: AnyObject {
    func beginTextSelection(at point: CGPoint, onExit: @escaping () -> Void) -> Bool
    func endTextSelection()
}

/// A regular UITextView that is deliberately disabled during reading. It becomes
/// interactive only after the parent reader has already recognized a long press.
final class PagedTextContentView: UITextView {
    private lazy var selectionExitTapGesture = UITapGestureRecognizer(
        target: self,
        action: #selector(handleSelectionExitTap)
    )
    private var onSelectionExit: (() -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        addGestureRecognizer(selectionExitTapGesture)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addGestureRecognizer(selectionExitTapGesture)
    }

    func beginSelection(at point: CGPoint, onExit: @escaping () -> Void) -> Bool {
        guard bounds.contains(point), attributedText.length > 0 else { return false }

        onSelectionExit = onExit
        isSelectable = true
        isUserInteractionEnabled = true

        // While selection is active, a plain tap means "leave selection". Give
        // that tap precedence over UITextView's private single/double-tap
        // recognizers. These dependencies are irrelevant in reading mode because
        // the entire text view is disabled there.
        gestureRecognizers?
            .compactMap { $0 as? UITapGestureRecognizer }
            .filter { $0 !== selectionExitTapGesture }
            .forEach { $0.require(toFail: selectionExitTapGesture) }

        guard
            let characterRange = characterRange(at: point),
            let range = selectionRange(enclosing: characterRange.start)
        else {
            endSelection()
            return false
        }

        let selectionRect = firstRect(for: range)
        let hitRect = selectionRect.insetBy(dx: -12, dy: -12)
        guard
            !selectionRect.isNull,
            !selectionRect.isInfinite,
            hitRect.contains(point)
        else {
            endSelection()
            return false
        }

        selectedTextRange = range
        becomeFirstResponder()

        // The first touch was received by the non-interactive reading page, so
        // UIKit cannot create its menu from that touch itself. Once selection is
        // established, show the native menu explicitly; handles and range changes
        // remain managed by UITextView.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isFirstResponder, self.selectedTextRange != nil else { return }
            self.showEditMenu(anchorRect: selectionRect)
        }
        return true
    }

    func endSelection() {
        if isFirstResponder {
            hideEditMenu()
            resignFirstResponder()
        }
        selectedRange = NSRange(location: 0, length: 0)
        isUserInteractionEnabled = false
        onSelectionExit = nil
    }

    private func selectionRange(enclosing position: UITextPosition) -> UITextRange? {
        if let wordRange = tokenizer.rangeEnclosingPosition(
            position,
            with: .word,
            inDirection: UITextDirection.storage(.forward)
        ) {
            return wordRange
        }

        // Tokenizers can return nil for individual CJK characters or punctuation.
        return tokenizer.rangeEnclosingPosition(
            position,
            with: .character,
            inDirection: UITextDirection.storage(.forward)
        )
    }

    @objc private func handleSelectionExitTap() {
        onSelectionExit?()
    }

    private func showEditMenu(anchorRect: CGRect) {
        if #available(iOS 16.0, *),
           let interaction = interactions.compactMap({ $0 as? UIEditMenuInteraction }).first {
            interaction.presentEditMenu(
                with: UIEditMenuConfiguration(
                    identifier: nil,
                    sourcePoint: CGPoint(x: anchorRect.midX, y: anchorRect.midY)
                )
            )
        } else {
            UIMenuController.shared.showMenu(from: self, rect: anchorRect)
        }
    }

    private func hideEditMenu() {
        if #available(iOS 16.0, *) {
            interactions
                .compactMap { $0 as? UIEditMenuInteraction }
                .forEach { $0.dismissMenu() }
        } else {
            UIMenuController.shared.hideMenu()
        }
    }
}

class TextSinglePageViewController: UIViewController, PagedTextSelectionPresenting {
    let page: TextPage
    weak var parentReader: ReaderPagedTextViewController?

    private lazy var textView: PagedTextContentView = {
        let tv = PagedTextContentView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.isUserInteractionEnabled = false  // Let taps pass through to parent tap zones
        tv.backgroundColor = parentReader?.textTheme.backgroundColor ?? TextReaderTheme.current.backgroundColor
        tv.font = .systemFont(ofSize: 18)
        return tv
    }()

    init(page: TextPage, parentReader: ReaderPagedTextViewController? = nil) {
        self.page = page
        self.parentReader = parentReader
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = parentReader?.textTheme.backgroundColor ?? TextReaderTheme.current.backgroundColor
        view.addSubview(textView)

        textView.translatesAutoresizingMaskIntoConstraints = false

        // Pin to view edges (not safe area) so text doesn't shift when bars hide/show.
        // The paginator already accounts for toolbar/safe-area space via its buffer.
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Match the paginator's lineFragmentPadding = 0 so the text layout
        // width is identical. The default (5pt) causes lines to wrap earlier
        // than the paginator predicted, pushing words off the visible area.
        textView.textContainer.lineFragmentPadding = 0

        // Set the text content
        if page.attributedContent.length > 0 {
            textView.attributedText = page.attributedContent
        } else {
            textView.text = page.markdownContent
        }

        updateTextInsets()
    }

    /// Position the text content within the full-screen view using fixed insets
    /// derived from the parent reader's pagination geometry. These insets never
    /// change when bars hide/show, so text stays perfectly stable.
    private func updateTextInsets() {
        guard let parentReader else { return }
        let insets = parentReader.textInsets
        textView.textContainerInset = insets
    }

    func beginTextSelection(at point: CGPoint, onExit: @escaping () -> Void) -> Bool {
        textView.beginSelection(at: textView.convert(point, from: view), onExit: onExit)
    }

    func endTextSelection() {
        textView.endSelection()
    }
}
