import Foundation
import Testing
@testable import MTKit

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .current
    return c
}

private func day(_ s: String) -> Date { MTDate.date(fromDay: s)! }

@Suite struct MatchWeekTests {
    @Test(arguments: ["2026-10-05", "2026-10-07", "2026-10-11"])
    func everyDayMapsToItsMondayToSunday(today: String) {
        let week = MatchWeek(containing: day(today), calendar: calendar)
        #expect(week.startDay == "2026-10-05")  // Monday
        #expect(week.endDay == "2026-10-11")    // Sunday
    }

    @Test func sundayStepsBackSixDaysNotZero() {
        let week = MatchWeek(containing: day("2026-10-04"), calendar: calendar)  // a Sunday
        #expect(week.startDay == "2026-09-28")
        #expect(week.endDay == "2026-10-04")
    }

    @Test func offsetsMoveWholeWeeksAcrossMonths() {
        let today = day("2026-10-05")
        #expect(MatchWeek(containing: today, offset: -1, calendar: calendar).startDay == "2026-09-28")
        #expect(MatchWeek(containing: today, offset: 4, calendar: calendar).endDay == "2026-11-08")
    }

    @Test func containsIsInclusive() {
        let week = MatchWeek(containing: day("2026-10-05"), calendar: calendar)
        #expect(week.contains(day: "2026-10-05"))
        #expect(week.contains(day: "2026-10-11"))
        #expect(!week.contains(day: "2026-10-12"))
    }

    @Test func labelHasYearOnEndOnly() {
        let label = MatchWeek(containing: day("2026-10-05"), calendar: calendar).label
        #expect(label.hasSuffix("2026"))
        #expect(label.contains("–"))
    }
}
