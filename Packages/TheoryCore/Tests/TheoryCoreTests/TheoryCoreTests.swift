import Testing
@testable import TheoryCore

@Suite("TheoryCore package")
struct TheoryCorePackageTests {
    @Test func exposesVersion() {
        #expect(TheoryCore.version == "0.1.0")
    }
}
