import XCTest
@testable import VinylCore

final class ConditionTests: XCTestCase {
    func testRawValuesMatchGoldmineScale() {
        XCTAssertEqual(Condition.allCases.count, 8)
        XCTAssertEqual(Condition.veryGoodPlus.rawValue, "VG+")
        XCTAssertEqual(Condition(rawValue: "NM"), .nearMint)
        XCTAssertNil(Condition(rawValue: "ZZ"))
    }

    func testQualityRankOrdersBestToWorst() {
        let sorted = Condition.allCases.sorted { $0.qualityRank > $1.qualityRank }
        XCTAssertEqual(sorted.first, .mint)
        XCTAssertEqual(sorted.last, .poor)
        XCTAssertGreaterThan(Condition.veryGoodPlus.qualityRank, Condition.veryGood.qualityRank)
    }

    func testDisplayNameIncludesAbbreviation() {
        XCTAssertEqual(Condition.veryGoodPlus.displayName, "Very Good Plus (VG+)")
    }
}
