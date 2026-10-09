import Foundation

/// Initials that stand in for a club or team: the app shows these, never a crest.
///
/// The API has no abbreviation field for clubs or teams, so they're derived from the
/// name. They're a visual cue only and aren't unique ("TSC A-Team" and "Tampa SC A"
/// are both "TA"); the full name is always shown beside them.
public enum ClubInitials {
    /// - "Blau Weiss Gottschee" → "BW" (first letters of the first two words)
    /// - "TSC A-Team" → "TA" (punctuation separates words)
    /// - "IFA" → "IFA" (a short all-caps name is already an abbreviation)
    /// - "Bayside" → "BA" (one word: its first two letters)
    /// - "" or "!!" → "" (nothing to show)
    public static func from(_ name: String) -> String {
        let words = name
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.contains(where: \.isLetter) }
        guard let first = words.first else { return "" }
        if words.count >= 2 {
            return words.prefix(2).map { String($0.first!) }.joined().uppercased()
        }
        if first.count <= 3, first.allSatisfy({ $0.isUppercase || $0.isNumber }) {
            return String(first)
        }
        return String(first.prefix(2)).uppercased()
    }
}
