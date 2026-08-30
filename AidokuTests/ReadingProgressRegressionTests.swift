//
//  ReadingProgressRegressionTests.swift
//  AidokuTests
//

import Foundation
import Testing
@testable import Aidoku

@Suite struct ReadingProgressRegressionTests {
    @Test("Completed history wins over a newer incomplete duplicate")
    func completedHistoryWins() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)

        #expect(HistoryDuplicateResolver.prefersCandidate(
            completed: true,
            date: older,
            progress: 10,
            over: false,
            date: newer,
            progress: 20
        ))
    }

    @Test("Newest history wins when completion state matches")
    func newestHistoryWins() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)

        #expect(HistoryDuplicateResolver.prefersCandidate(
            completed: false,
            date: newer,
            progress: 2,
            over: false,
            date: older,
            progress: 20
        ))
    }

    @Test("Highest page breaks equal-date history ties")
    func highestPageWinsDateTie() {
        let date = Date(timeIntervalSince1970: 100)

        #expect(HistoryDuplicateResolver.prefersCandidate(
            completed: false,
            date: date,
            progress: 20,
            over: false,
            date: date,
            progress: 10
        ))
    }
}
