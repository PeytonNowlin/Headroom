import HeadroomCore
import SwiftUI

/// Monochrome, non-trademarked marks for each provider, drawn as paths so they scale crisply.
struct ProviderGlyph: View {
    let provider: ProviderID
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: canvasSize.width * 0.08, dy: canvasSize.height * 0.08)
            let path = Self.path(for: provider, in: rect)
            let stroke = StrokeStyle(lineWidth: max(1.4, size * 0.11), lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .foreground, style: stroke)
        }
        .frame(width: size, height: size)
    }

    private static func path(for provider: ProviderID, in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        switch provider {
        case .claude:
            // Eight-spoke burst.
            let outer = r.width / 2
            let inner = outer * 0.38
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                p.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
            }
        case .codex:
            // Terminal chevron and baseline.
            let w = r.width, h = r.height
            p.move(to: CGPoint(x: r.minX + w * 0.15, y: r.minY + h * 0.25))
            p.addLine(to: CGPoint(x: r.minX + w * 0.48, y: c.y))
            p.addLine(to: CGPoint(x: r.minX + w * 0.15, y: r.maxY - h * 0.25))
            p.move(to: CGPoint(x: r.minX + w * 0.55, y: r.maxY - h * 0.2))
            p.addLine(to: CGPoint(x: r.maxX - w * 0.1, y: r.maxY - h * 0.2))
        case .grok:
            // Diagonal slash with a short counter-stroke.
            p.move(to: CGPoint(x: r.maxX - r.width * 0.2, y: r.minY + r.height * 0.15))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.2, y: r.maxY - r.height * 0.15))
            p.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.15))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.45, y: r.minY + r.height * 0.42))
        }
        return p
    }
}
