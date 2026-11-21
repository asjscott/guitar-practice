// PROTOTYPE — throwaway. Answers "what should the Phase 0 fretboard explorer window look like?"
// The theory here is a quick stub so the layouts have real-looking data. It is NOT TheoryCore
// and must not be reused: TheoryCore gets written test-first.

import SwiftUI

enum ProtoLabelMode: String, CaseIterable, Identifiable {
    case shown = "Shown", faded = "Faded", hidden = "Hidden"
    var id: String { rawValue }
}

enum ProtoDisplay: String, CaseIterable, Identifiable {
    case scale = "Scale", triad = "Triad"
    var id: String { rawValue }
}

enum ProtoScale: String, CaseIterable, Identifiable {
    case major = "Major", minor = "Natural minor", majorPent = "Major pentatonic",
         minorPent = "Minor pentatonic", blues = "Blues"
    var id: String { rawValue }
    var steps: [Int] {
        switch self {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .minor: [0, 2, 3, 5, 7, 8, 10]
        case .majorPent: [0, 2, 4, 7, 9]
        case .minorPent: [0, 3, 5, 7, 10]
        case .blues: [0, 3, 5, 6, 7, 10]
        }
    }
    var isMinor: Bool { [.minor, .minorPent, .blues].contains(self) }
    var isSevenNote: Bool { steps.count == 7 }
}

struct ProtoKey: Hashable, Identifiable {
    let name: String
    let pc: Int
    let flats: Bool
    var id: String { name }
    static let all: [ProtoKey] = [
        .init(name: "C", pc: 0, flats: false), .init(name: "G", pc: 7, flats: false),
        .init(name: "D", pc: 2, flats: false), .init(name: "A", pc: 9, flats: false),
        .init(name: "E", pc: 4, flats: false), .init(name: "B", pc: 11, flats: false),
        .init(name: "F♯", pc: 6, flats: false), .init(name: "D♭", pc: 1, flats: true),
        .init(name: "A♭", pc: 8, flats: true), .init(name: "E♭", pc: 3, flats: true),
        .init(name: "B♭", pc: 10, flats: true), .init(name: "F", pc: 5, flats: true),
    ]
}

struct ProtoTuning: Hashable, Identifiable {
    let name: String
    let open: [Int] // string 6 first
    var id: String { name }
    static let all: [ProtoTuning] = [
        .init(name: "Standard", open: [40, 45, 50, 55, 59, 64]),
        .init(name: "Drop D", open: [38, 45, 50, 55, 59, 64]),
        .init(name: "DADGAD", open: [38, 45, 50, 55, 57, 62]),
        .init(name: "Open G", open: [38, 43, 50, 55, 59, 62]),
        .init(name: "E♭ standard", open: [39, 44, 49, 54, 58, 63]),
    ]
}

enum ProtoSystem: String, CaseIterable, Identifiable {
    case caged = "CAGED", threeNPS = "3NPS"
    var id: String { rawValue }
}

struct ProtoPosition: Hashable, Identifiable {
    let name: String
    let cells: Set<ProtoCell>
    var id: String { name }
    var minFret: Int { cells.map(\.fret).min() ?? 0 }
    var maxFret: Int { cells.map(\.fret).max() ?? 0 }
}

struct ProtoCell: Hashable {
    let string: Int // 0 = string 6
    let fret: Int
}

let protoStringSets = ["E-A-D", "A-D-G", "D-G-B", "G-B-E"]
let protoInversions = ["Root", "1st", "2nd"]

@MainActor @Observable
final class PrototypeExplorerModel {
    var key = ProtoKey.all[0]
    var scale = ProtoScale.major
    var system = ProtoSystem.caged
    var positionIndex: Int? = 3 // E shape in CAGED order below; nil = whole neck
    var display = ProtoDisplay.scale
    var stringSet = 2
    var inversion = 0
    var tuning = ProtoTuning.all[0]
    var capo = 0
    var labelMode = ProtoLabelMode.shown
    var heatmap = false
    var heat: [ProtoCell: Double] = [:]

    let frets = 22

    // MARK: spelling (stub)
    private let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
    func name(_ pc: Int) -> String { (key.flats ? flatNames : sharpNames)[((pc % 12) + 12) % 12] }

    var tonicPC: Int { scale.isMinor ? (key.pc + 9) % 12 : key.pc } // relative minor of the key
    var keyTitle: String { scale.isMinor ? "\(name(tonicPC))m" : key.name }
    var scalePCs: Set<Int> { Set(scale.steps.map { (tonicPC + $0) % 12 }) }

    func pitch(_ c: ProtoCell) -> Int { tuning.open[c.string] + c.fret }
    func playable(_ c: ProtoCell) -> Bool { c.fret == 0 ? capo == 0 : c.fret >= capo }

    // MARK: positions (stub of ADR-0001)
    var effectiveSystem: ProtoSystem { scale.isSevenNote ? system : .caged }

    var positions: [ProtoPosition] {
        effectiveSystem == .caged ? cagedPositions : nnpsPositions
    }

    private var cagedPositions: [ProtoPosition] {
        let majorTonic = key.pc
        let pent = [0, 2, 4, 7, 9].map { (majorTonic + $0) % 12 }
        let names = ["E", "D", "C", "A", "G"]
        let standardIntervals = zip(tuning.open.dropFirst(), tuning.open).map { $0 - $1 } == [5, 5, 5, 4, 5]
        var out: [ProtoPosition] = []
        for (i, startPC) in pent.enumerated() {
            let cells = walk(startPC: startPC, pcs: Set(pent), perString: 2)
            var lo = cells.map(\.fret).min()!, hi = cells.map(\.fret).max()!
            var fill = Set<ProtoCell>()
            for s in tuning.open.indices {
                for f in max(lo - 1, 0)...min(hi + 1, frets) where scalePCs.contains(pitch(.init(string: s, fret: f)) % 12) {
                    if f >= lo - (scale.isSevenNote ? 1 : 0) && f <= hi + (scale.isSevenNote ? 1 : 0) { fill.insert(.init(string: s, fret: f)) }
                }
            }
            if !scale.isSevenNote { fill = Set(cells.filter { scalePCs.contains(pitch($0) % 12) }).union(fill.filter { $0.fret >= lo && $0.fret <= hi }) }
            lo = fill.map(\.fret).min() ?? lo; hi = fill.map(\.fret).max() ?? hi
            let label = standardIntervals || tuning.name == "Drop D" ? "\(names[i]) shape" : "Position \(i + 1)"
            out.append(.init(name: label, cells: fill))
        }
        return out.sorted { $0.minFret < $1.minFret }
    }

    private var nnpsPositions: [ProtoPosition] {
        let degrees = scale.steps.map { (tonicPC + $0) % 12 }
        return degrees.enumerated().map { i, pc in
            .init(name: "Pattern \(i + 1)", cells: walk(startPC: pc, pcs: scalePCs, perString: 3))
        }.sorted { $0.minFret < $1.minFret }
    }

    private func walk(startPC: Int, pcs: Set<Int>, perString: Int) -> Set<ProtoCell> {
        var startFret = (startPC - tuning.open[0] % 12 + 24) % 12
        while startFret < max(capo, 0) { startFret += 12 }
        var p = tuning.open[0] + startFret
        var cells: [ProtoCell] = []
        for s in tuning.open.indices {
            var taken = 0
            while taken < perString {
                if pcs.contains(p % 12) {
                    cells.append(.init(string: s, fret: p - tuning.open[s])); taken += 1
                }
                p += 1
            }
            // next string starts from the next scale note above
        }
        if cells.contains(where: { $0.fret < 0 }) { return Set(cells.map { .init(string: $0.string, fret: $0.fret + 12) }) }
        return Set(cells)
    }

    // MARK: triads (stub)
    var triadTones: [Int] {
        let third = scale.isMinor ? 3 : 4
        let tones = [tonicPC, (tonicPC + third) % 12, (tonicPC + 7) % 12]
        return Array(tones[inversion...] + tones[..<inversion])
    }

    var triadVoicings: [Set<ProtoCell>] {
        let base = stringSet
        guard base + 2 < tuning.open.count else { return [] }
        var out: [Set<ProtoCell>] = []
        for f0 in 0...frets where (tuning.open[base] + f0) % 12 == triadTones[0] {
            var p = tuning.open[base] + f0
            var cells = [ProtoCell(string: base, fret: f0)]
            for k in 1...2 {
                p += 1
                while p % 12 != triadTones[k] { p += 1 }
                cells.append(.init(string: base + k, fret: p - tuning.open[base + k]))
            }
            let fs = cells.map(\.fret)
            if fs.allSatisfy({ $0 >= 0 && $0 <= frets }), fs.max()! - fs.min()! <= 4, cells.allSatisfy(playable) {
                out.append(Set(cells))
            }
        }
        return out
    }

    // MARK: what the fretboard draws
    var highlighted: Set<ProtoCell> {
        switch display {
        case .triad:
            return triadVoicings.reduce(into: Set()) { $0.formUnion($1) }
        case .scale:
            if let i = positionIndex, positions.indices.contains(i) {
                return positions[i].cells.filter(playable)
            }
            var all = Set<ProtoCell>()
            for s in tuning.open.indices {
                for f in 0...frets {
                    let c = ProtoCell(string: s, fret: f)
                    if playable(c), scalePCs.contains(pitch(c) % 12) { all.insert(c) }
                }
            }
            return all
        }
    }

    func isRoot(_ c: ProtoCell) -> Bool { pitch(c) % 12 == tonicPC }

    func regenerateHeat() {
        var h: [ProtoCell: Double] = [:]
        for s in tuning.open.indices { for f in 0...frets { h[.init(string: s, fret: f)] = Double.random(in: 0...1) } }
        heat = h
    }
}
