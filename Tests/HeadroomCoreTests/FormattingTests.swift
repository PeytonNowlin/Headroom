import Foundation
import HeadroomCore
import Testing

@Suite("Formatting")
struct FormattingTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("countdowns pick the two most significant units")
    func countdowns() {
        #expect(Formatting.countdown(to: now.addingTimeInterval(45), from: now) == "45s")
        #expect(Formatting.countdown(to: now.addingTimeInterval(7 * 60), from: now) == "7m")
        #expect(Formatting.countdown(to: now.addingTimeInterval(3 * 3600 + 12 * 60), from: now) == "3h 12m")
        #expect(Formatting.countdown(to: now.addingTimeInterval(2 * 86400 + 5 * 3600 + 59 * 60), from: now) == "2d 5h")
        #expect(Formatting.countdown(to: now.addingTimeInterval(3 * 86400), from: now) == "3d")
        #expect(Formatting.countdown(to: now.addingTimeInterval(-10), from: now) == "now")
    }

    @Test("dollars and tokens read like the spec examples")
    func money() {
        #expect(Formatting.dollars(4.08) == "$4.08")
        #expect(Formatting.dollars(0.5) == "$0.50")
        #expect(Formatting.dollars(1234) == "$1,234.00")
        #expect(Formatting.tokens(1_200_000) == "1.2M")
        #expect(Formatting.tokens(845_000) == "845K")
        #expect(Formatting.tokens(312) == "312")
        #expect(Formatting.tokens(2_000_000) == "2M")
        #expect(Formatting.tokens(999_949_999) == "999.9M")
        #expect(Formatting.tokens(1_024_000_000) == "1B")
        #expect(Formatting.tokens(1_250_000_000) == "1.3B")
        #expect(Formatting.tokens(12_700_000_000) == "12.7B")
    }

    @Test("extra usage row covers disabled, capped, uncapped, and labelled")
    func extra() {
        #expect(Formatting.extraUsage(ExtraUsage(isEnabled: false)) == "Disabled")
        #expect(Formatting.extraUsage(ExtraUsage(isEnabled: true, usedDollars: 3.2, limitDollars: 50)) == "$3.20 of $50.00")
        #expect(Formatting.extraUsage(ExtraUsage(isEnabled: true, usedDollars: 3.2, limitDollars: 0)) == "$3.20 used")
        #expect(Formatting.extraUsage(ExtraUsage(isEnabled: true, label: "2500 cap")) == "2500 cap")
    }
}
