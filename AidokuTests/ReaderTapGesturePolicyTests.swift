//
//  ReaderTapGesturePolicyTests.swift
//  AidokuTests
//

import Testing
import UIKit
@testable import Aidoku

@MainActor
@Suite struct ReaderTapGesturePolicyTests {
    @Test("Selectable text taps can coexist with reader tap zones")
    func selectableTextTapIsAllowed() {
        let textView = UITextView()
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer()
        textView.addGestureRecognizer(tap)

        #expect(ReaderTapGesturePolicy.allowsSimultaneousTextTap(tap))
    }

    @Test("Long press selection remains exclusive")
    func longPressIsNotAllowed() {
        let textView = UITextView()
        let longPress = UILongPressGestureRecognizer()
        textView.addGestureRecognizer(longPress)

        #expect(!ReaderTapGesturePolicy.allowsSimultaneousTextTap(longPress))
    }

    @Test("Double-tap text selection remains exclusive")
    func doubleTapIsNotAllowed() {
        let textView = UITextView()
        textView.isSelectable = true
        let doubleTap = UITapGestureRecognizer()
        doubleTap.numberOfTapsRequired = 2
        textView.addGestureRecognizer(doubleTap)

        #expect(!ReaderTapGesturePolicy.allowsSimultaneousTextTap(doubleTap))
    }

    @Test("Nonselectable text does not change reader gesture policy")
    func nonselectableTextTapIsNotAllowed() {
        let textView = UITextView()
        textView.isSelectable = false
        let tap = UITapGestureRecognizer()
        textView.addGestureRecognizer(tap)

        #expect(!ReaderTapGesturePolicy.allowsSimultaneousTextTap(tap))
    }
}
