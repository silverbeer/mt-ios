import Testing
@testable import MTKit

@Suite struct ClubInitialsTests {
    @Test(arguments: [
        ("Blau Weiss Gottschee", "BW"),
        ("Red Bull New York", "RB"),
        ("TSC A-Team", "TA"),
        ("TSC B-Team", "TB"),
        ("The Island FC East", "TI"),
        ("St. Mary's", "SM"),
        ("IFA", "IFA"),
        ("TSC", "TSC"),
        ("Bayside", "BA"),
        ("bayside", "BA"),
        ("NEFC2", "NE"),
        ("Élan FC", "ÉF"),
        ("  Metropolitan   Oval  ", "MO"),
        ("1. FC Köln", "FK"),
    ])
    func derivesFromName(name: String, expected: String) {
        #expect(ClubInitials.from(name) == expected)
    }

    @Test(arguments: ["", "   ", "!!", "123", "- / -"])
    func nothingToShowIsEmpty(name: String) {
        #expect(ClubInitials.from(name) == "")
    }

    @Test func longNamesStayShort() {
        let initials = ClubInitials.from(String(repeating: "Abcdefghij", count: 20) + " Academy")
        #expect(initials == "AA")
        #expect(ClubInitials.from(String(repeating: "x", count: 200)).count == 2)
    }
}
