extension String {
    /// "Natural minor" from "natural minor".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
