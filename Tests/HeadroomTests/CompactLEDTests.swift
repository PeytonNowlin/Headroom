import Foundation
import HeadroomCore
import Testing
@testable import Headroom

@Suite("Compact LED targets")
struct CompactLEDTests {
    @Test func targetsMatchLayoutAndLeaveNotchClear() {
        for anchor in [IslandAnchor.simulatedNotch(height: 32), .notch(width: 200, height: 32)] {
            let layout = IslandLayout.make(for: anchor)
            for count in 1...4 {
                let providers = Array(ProviderID.allCases.prefix(count))
                var hits: Set<ProviderID> = []
                for x in stride(from: CGFloat(0), through: layout.panel.width, by: 1) {
                    if let id = IslandGeometry.compactProvider(at: CGPoint(x: x, y: 16), layout: layout, providers: providers) {
                        hits.insert(id)
                    }
                }
                #expect(hits == Set(providers))
                #expect(IslandGeometry.compactProvider(at: CGPoint(x: layout.panel.width / 2, y: 16), layout: layout, providers: providers) == nil)
                #expect(IslandGeometry.compactProvider(at: CGPoint(x: layout.panel.width / 2, y: 40), layout: layout, providers: providers) == nil)
            }
        }
    }
}
