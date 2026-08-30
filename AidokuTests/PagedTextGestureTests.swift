//
//  PagedTextGestureTests.swift
//  AidokuTests
//

import Testing
import UIKit
@testable import Aidoku

@MainActor
@Suite struct PagedTextGestureTests {
    @Test("Paged text reserves taps for immediate page turns")
    func pagedTextRejectsTapGestures() {
        let tap = UITapGestureRecognizer()

        #expect(!PagedSelectableTextView.allowsGesture(tap))
    }

    @Test("Paged text retains native long-press selection")
    func pagedTextAllowsLongPressGestures() {
        let longPress = UILongPressGestureRecognizer()

        #expect(PagedSelectableTextView.allowsGesture(longPress))
    }
}
