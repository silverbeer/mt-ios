import Foundation
import Testing
@testable import MTKit

@Suite struct StandingsFormatTests {
    @Test(arguments: [
        (2.25, "2.25"),
        (2.2, "2.20"),
        (3.0, "3.00"),
        (0.666666, "0.67"),
        (1.004, "1.00"),
        (-1.5, "-1.50"),
        (12.345678, "12.35"),
    ])
    func rateHasExactlyTwoDecimals(value: Double, expected: String) {
        #expect(StandingsFormat.rate(value) == expected)
    }

    @Test func missingRateIsADashNeverZero() {
        #expect(StandingsFormat.rate(nil) == "–")
        #expect(StandingsFormat.rate(nil, signed: true) == "–")
        #expect(StandingsFormat.rate(.nan) == "–")
        #expect(StandingsFormat.missing == "\u{2013}")
    }

    @Test(arguments: [
        (1.25, "+1.25"),
        (0.5, "+0.50"),
        (-0.75, "-0.75"),
        (0.0, "0.00"),
        (-0.0, "0.00"),
        (-0.001, "0.00"),
        (0.004, "0.00"),
    ])
    func signedRate(value: Double, expected: String) {
        #expect(StandingsFormat.rate(value, signed: true) == expected)
    }

    @Test func zeroRateIsUnsignedZero() {
        #expect(StandingsFormat.rate(0) == "0.00")
        #expect(StandingsFormat.rate(-0.0) == "0.00")
    }

    @Test(arguments: [(3, "+3"), (0, "0"), (-2, "-2")])
    func goalDifferenceSign(value: Int, expected: String) {
        #expect(StandingsFormat.goalDifference(value) == expected)
    }

    /// A comma-decimal locale must not leak into the output.
    @Test func ignoresCurrentLocale() {
        let german = String(format: "%.2f", locale: Locale(identifier: "de_DE"), 2.25)
        #expect(german == "2,25") // the trap the formatter avoids
        #expect(StandingsFormat.rate(2.25) == "2.25")
        #expect(StandingsFormat.rate(1.5, signed: true) == "+1.50")
    }
}
