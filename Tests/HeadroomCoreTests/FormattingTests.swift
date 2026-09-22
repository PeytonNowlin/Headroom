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

    @Test("refresh clock reads m:ss under an hour")
    func clock() {
        #expect(Formatting.clock(to: now.addingTimeInterval(247), from: now) == "4:07")
        #expect(Formatting.clock(to: now.addingTimeInterval(9), from: now) == "0:09")
        #expect(Formatting.clock(to: now.addingTimeInterval(-3), from: now) == "0:00")
        #expect(Formatting.clock(to: now.addingTimeInterval(4000), from: now) == "1h 6m")
    }

    @Test("dollars read like the spec examples")
    func money() {
        #expect(Formatting.dollars(4.08) == "$4.08")
        #expect(Formatting.dollars(0.5) == "$0.50")
        #expect(Formatting.dollars(1234) == "$1,234.00")
    }

    @Test("extra usage row covers disabled, capped, uncapped, and labelled")
    func extra() {
        #expect(Formatting.extraUsage(ExtraUsage(isEnabled: false)) == "Disabled")
        #expect(Formatting.extraUsage(ExtraUsage(isEnabled: true, usedDollars: 3.2, limitDollars: 50)) == "$3.20 of $50.00")
        #expect(Formatting.extraUsage(ExtraUsage(isEnabled: true, usedDollars: 3.2, limitDollars: 0)) == "$3.20 used")
        #expect(Formatting.extraUsage(ExtraUsage(isEnabled: true, label: "2500 cap")) == "2500 cap")
    }
}
