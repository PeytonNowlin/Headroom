import Foundation
import HeadroomCore
import Testing
@testable import Headroom

@Suite("Compact band")
struct CompactBandTests {
    private let anchors: [IslandAnchor] = [.simulatedNotch(height: 32), .notch(width: 200, height: 32)]

    @Test("every gauge is hittable, sits on its own side of the notch, and is never clipped")
    func targetsMatchLayout() {
        for anchor in anchors {
            let layout = IslandLayout.make(for: anchor)
            let center = layout.panel.width / 2
            for mainCount in 0...2 {
                for sideCount in 0...3 {
                    let main = Array(ProviderID.allCases.prefix(mainCount))
                    let side = Array(ProviderID.allCases.dropFirst(mainCount).prefix(sideCount))
                    let size = layout.compactSize(main: mainCount, secondary: sideCount)
                    let band = CGRect(x: center - size.width / 2, y: 0, width: size.width, height: size.height)
                    var hits: [ProviderID: CGFloat] = [:]
                    for x in stride(from: CGFloat(0), through: layout.panel.width, by: 0.5) {
                        let point = CGPoint(x: x, y: 16)
                        guard let id = IslandGeometry.compactProvider(at: point, layout: layout,
                                                                     main: main, secondary: side) else { continue }
                        hits[id] = x
                        // A target outside the band would be clipped away and unclickable.
                        #expect(band.contains(point))
                    }
                    #expect(Set(hits.keys) == Set(main).union(side))
                    // Tier is position: main agents left of the notch, side providers right of it.
                    for id in main { #expect((hits[id] ?? 0) < center) }
                    for id in side { #expect((hits[id] ?? .greatestFiniteMagnitude) > center) }
                    // The notch's own band stays clear, and so does everything below it.
                    #expect(IslandGeometry.compactProvider(at: CGPoint(x: center, y: 16), layout: layout,
                                                           main: main, secondary: side) == nil)
                    #expect(IslandGeometry.compactProvider(at: CGPoint(x: center, y: 40), layout: layout,
                                                           main: main, secondary: side) == nil)
                }
            }
        }
    }

    @Test("the band grows to hold its gauges and never shrinks below the bezel band")
    func bandGrowsToFit() {
        for anchor in anchors {
            let layout = IslandLayout.make(for: anchor)
            #expect(layout.compactSize(main: 0, secondary: 0).width == layout.compact.width)
            #expect(layout.compactSize(main: 1, secondary: 1).width == layout.compact.width)
            #expect(layout.compactSize(main: 2, secondary: 3).width > layout.compact.width)
            #expect(layout.compactSize(main: 5, secondary: 0).width
                    > layout.compactSize(main: 2, secondary: 0).width)
            #expect(layout.compactSize(main: 3, secondary: 0).height == layout.compact.height)
        }
    }

    @Test("a dormant island has no silhouette but keeps a hover target at the notch")
    func dormantHasNoSilhouette() {
        for anchor in anchors {
            let layout = IslandLayout.make(for: anchor)
            let dormant = layout.size(for: .dormant, content: IslandContent())
            #expect(dormant.height == 0)
            #expect(IslandGeometry.islandRect(layout: layout, size: dormant).height == 0)
            let zone = IslandGeometry.hoverZone(layout: layout, size: dormant)
            #expect(zone.height == layout.compact.height)
            #expect(zone.contains(CGPoint(x: layout.panel.width / 2, y: 4)))
        }
    }
}
