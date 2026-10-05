import SwiftUI
import MTKit

/// Home/Away lineups on a pitch (web FormationField), with any players whose
/// position the formation doesn't define listed underneath.
struct LineupSection: View {
    let match: Match
    let home: Lineup?
    let away: Lineup?
    @State private var side: Side = .home

    enum Side: Hashable { case home, away }

    private var current: Lineup? { side == .home ? home : away }

    var body: some View {
        Section {
            Picker("Team", selection: $side) {
                Text(match.homeTeamName).tag(Side.home)
                Text(match.awayTeamName).tag(Side.away)
            }
            .pickerStyle(.segmented)
            if let lineup = current, !lineup.isEmpty {
                let placed = lineup.placed()
                if !placed.onPitch.isEmpty {
                    Pitch(players: placed.onPitch)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                ForEach(placed.unplaced, id: \.self) { entry in
                    LabeledContent(entry.label, value: entry.position)
                }
            } else {
                Text("No lineup set").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Lineups")
                Spacer()
                if let formation = current?.formationName { Text(formation).textCase(nil) }
            }
        }
    }
}

private struct Pitch: View {
    let players: [(entry: Lineup.Entry, x: Double, y: Double)]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.green.gradient.opacity(0.85))
                PitchMarkings().stroke(.white.opacity(0.6), lineWidth: 1.5)
                ForEach(Array(players.enumerated()), id: \.offset) { _, player in
                    PlayerMarker(entry: player.entry)
                        .position(x: size.width * player.x / 100, y: size.height * player.y / 100)
                }
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .accessibilityElement(children: .contain)
    }
}

private struct PlayerMarker: View {
    let entry: Lineup.Entry

    var body: some View {
        VStack(spacing: 2) {
            Text(entry.jerseyNumber.map(String.init) ?? entry.position)
                .font(.caption.bold().monospacedDigit())
                .frame(width: 30, height: 30)
                .background(.white, in: Circle())
                .foregroundStyle(.black)
            Text(shortName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 76)
                .shadow(radius: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.position), \(entry.label)")
    }

    /// "Lucas S" → "Lucas S"; long names trimmed to the first word plus initial.
    private var shortName: String {
        let parts = entry.label.split(separator: " ")
        guard entry.label.count > 12, parts.count > 1 else { return entry.label }
        return "\(parts[0]) \(parts.last!.prefix(1))"
    }
}

/// Halfway line, centre circle and both penalty boxes.
private struct PitchMarkings: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.insetBy(dx: 8, dy: 8)
        path.addRoundedRect(in: r, cornerSize: CGSize(width: 6, height: 6))
        path.move(to: CGPoint(x: r.minX, y: r.midY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        let circle = r.width * 0.18
        path.addEllipse(in: CGRect(x: r.midX - circle, y: r.midY - circle, width: circle * 2, height: circle * 2))
        let boxW = r.width * 0.55, boxH = r.height * 0.14
        path.addRect(CGRect(x: r.midX - boxW / 2, y: r.minY, width: boxW, height: boxH))
        path.addRect(CGRect(x: r.midX - boxW / 2, y: r.maxY - boxH, width: boxW, height: boxH))
        return path
    }
}
