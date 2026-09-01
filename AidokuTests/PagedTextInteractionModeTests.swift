//
//  PagedTextInteractionModeTests.swift
//  AidokuTests
//

import Testing
@testable import Aidoku

@Suite struct PagedTextInteractionModeTests {
    @Test("Reading mode leaves page navigation enabled")
    func readingAllowsPageNavigation() {
        let mode = PagedTextInteractionMode.reading
        #expect(mode.allowsPageNavigation)
    }

    @Test("Selection mode locks page navigation until dismissed")
    func selectionLocksAndRestoresPageNavigation() {
        var mode = PagedTextInteractionMode.reading

        mode.beginSelection()
        #expect(mode == .selecting)
        #expect(!mode.allowsPageNavigation)

        #expect(mode.endSelection())
        #expect(mode == .reading)
        #expect(mode.allowsPageNavigation)
    }

    @Test("Dismissing reading mode is a no-op")
    func dismissingReadingModeDoesNotConsumeTap() {
        var mode = PagedTextInteractionMode.reading
        #expect(!mode.endSelection())
        #expect(mode == .reading)
    }
}
