import Foundation
import HeadroomCore
import Testing

@Suite("JSON")
struct JSONTests {
    @Test("int truncates numeric values and numeric strings")
    func truncates() throws {
        let json = try JSON.parse(Data(#"{"n": 12.9, "s": "42", "neg": -7.2}"#.utf8))
        #expect(json["n"].int == 12)
        #expect(json["s"].int == 42)
        #expect(json["neg"].int == -7)
    }

    @Test("int rejects non-finite and out-of-range values instead of trapping")
    func rejectsUnsafeValues() throws {
        let json = try JSON.parse(Data(#"{"big": 1e300, "inf": "1e400"}"#.utf8))
        #expect(json["big"].int == nil)
        #expect(json["inf"].int == nil)
        #expect(json["missing"].int == nil)
    }
}
