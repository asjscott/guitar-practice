extension NoteName {
    /// A note name as typed: a letter A–G, then at most one accidental, # or b (♯ and ♭ too). Either case: a "b" after
    /// the letter means flat, so "bb" and "Bb" are B♭. Nil for anything else.
    public init?(typed text: String) {
        let characters = Array(text.uppercased())
        guard let first = characters.first, characters.count <= 2,
              let letter = Letter.allCases.first(where: { $0.symbol == String(first) }) else { return nil }
        switch characters.dropFirst().first {
        case nil: self.init(letter)
        case "#", "♯": self.init(letter, 1)
        case "B", "♭": self.init(letter, -1)
        default: return nil
        }
    }
}
