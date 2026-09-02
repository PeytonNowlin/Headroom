import SwiftUI

/// The island silhouette. With a non-zero flare the top corners curve outward so the shape
/// appears to grow out of the notch bezel; the bottom corners are rounded inward.
/// The flare lives inside the rect: the body spans `flare ... width - flare`.
struct IslandShape: Shape {
    var cornerRadius: CGFloat
    var flare: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(cornerRadius, rect.height / 2)
        let f = min(flare, rect.height / 2)
        let left = rect.minX + f
        let right = rect.maxX - f
        let top = rect.minY
        let bottom = rect.maxY

        p.move(to: CGPoint(x: rect.minX, y: top))
        if f > 0 {
            // Concave flare: bezier from the outer top corner inward and down to the body's left edge.
            p.addQuadCurve(to: CGPoint(x: left, y: top + f), control: CGPoint(x: left, y: top))
        }
        p.addLine(to: CGPoint(x: left, y: bottom - r))
        p.addArc(center: CGPoint(x: left + r, y: bottom - r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: right - r, y: bottom))
        p.addArc(center: CGPoint(x: right - r, y: bottom - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        if f > 0 {
            p.addLine(to: CGPoint(x: right, y: top + f))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: top), control: CGPoint(x: right, y: top))
        } else {
            p.addLine(to: CGPoint(x: right, y: top + r))
            p.addArc(center: CGPoint(x: right - r, y: top + r), radius: r,
                     startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
            p.addLine(to: CGPoint(x: left + r, y: top))
            p.addArc(center: CGPoint(x: left + r, y: top + r), radius: r,
                     startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
        }
        p.closeSubpath()
        return p
    }
}
