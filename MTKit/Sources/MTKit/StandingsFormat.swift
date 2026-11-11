import Foundation

/// Text for the Table's stat cells. Pure and locale-independent, so "2.25" never becomes "2,25".
public enum StandingsFormat {
    /// What a missing value shows as. Missing is never rendered as zero.
    public static let missing = "–"

    /// A per-match rate to exactly two decimals ("2.25"); `signed` adds "+" to positive values
    /// (goal difference per match). `nil` is the en dash.
    public static func rate(_ value: Double?, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return missing }
        var rounded = (value * 100).rounded() / 100
        if rounded == 0 { rounded = 0 } // no "-0.00"
        let text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        return signed && rounded > 0 ? "+" + text : text
    }

    /// Goal difference with an explicit "+" for positive values ("+3", "0", "-2").
    public static func goalDifference(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}
