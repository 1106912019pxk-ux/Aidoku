//
//  ReaderTapDelayPolicyTests.swift
//  AidokuTests
//

import Testing
@testable import Aidoku

@Suite struct ReaderTapDelayPolicyTests {
    @Test("Paged text taps never wait for double tap")
    func pagedTextIsImmediate() {
        #expect(!ReaderTapGesturePolicy.shouldDeferSingleTapForDoubleTap(
            isPagedTextReader: true,
            singleTapLookupEnabled: false,
            doubleTapDisabled: false
        ))
    }

    @Test("Manga retains upstream double-tap waiting behavior")
    func mangaRetainsDoubleTapDelay() {
        #expect(ReaderTapGesturePolicy.shouldDeferSingleTapForDoubleTap(
            isPagedTextReader: false,
            singleTapLookupEnabled: false,
            doubleTapDisabled: false
        ))
    }

    @Test("Global disable-double-tap setting remains effective for manga")
    func disabledDoubleTapIsImmediate() {
        #expect(!ReaderTapGesturePolicy.shouldDeferSingleTapForDoubleTap(
            isPagedTextReader: false,
            singleTapLookupEnabled: false,
            doubleTapDisabled: true
        ))
    }

    @Test("Single-tap dictionary lookup does not wait for double tap")
    func singleTapLookupIsImmediate() {
        #expect(!ReaderTapGesturePolicy.shouldDeferSingleTapForDoubleTap(
            isPagedTextReader: false,
            singleTapLookupEnabled: true,
            doubleTapDisabled: false
        ))
    }
}
