import AppKit

/// Menu bar icons, drawn in code — a fountain-pen nib (this is a lawyer's
/// dictation app, after all) with a variant per app state:
///
/// - loading:      dimmed outline nib
/// - idle:         outline nib (template — adapts to light/dark)
/// - recording:    white nib on a red disc (colour, so state is unmissable)
/// - transcribing: filled nib (template)
/// - paused:       outline nib with a slash
/// - failed:       system warning triangle
@MainActor
enum MenuBarIcon {
    private static let size = NSSize(width: 18, height: 18)

    static let idle = template { ctx in
        strokeNib(ctx)
    }

    static let loading = template { ctx in
        ctx.setAlpha(0.4)
        strokeNib(ctx)
    }

    static let transcribing = template { ctx in
        fillNib(ctx)
    }

    static let paused = template { ctx in
        strokeNib(ctx)
        ctx.move(to: CGPoint(x: 3, y: 3))
        ctx.addLine(to: CGPoint(x: 15, y: 15))
        ctx.setLineWidth(1.6)
        ctx.strokePath()
    }

    static let recording: NSImage = {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Red disc
            ctx.setFillColor(NSColor.systemRed.cgColor)
            ctx.fillEllipse(in: CGRect(x: 0.5, y: 0.5, width: 17, height: 17))
            // White nib, slightly inset
            ctx.translateBy(x: 9, y: 9.2)
            ctx.scaleBy(x: 0.62, y: 0.62)
            ctx.translateBy(x: -9, y: -9)
            ctx.setFillColor(NSColor.white.cgColor)
            fillNib(ctx, knockoutColor: NSColor.systemRed.cgColor)
            return true
        }
        image.isTemplate = false
        return image
    }()

    static let failed: NSImage = {
        NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
            ?? idle
    }()

    // MARK: - Drawing

    private static func template(_ draw: @escaping (CGContext) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            draw(ctx)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Nib outline: pointed tip at the bottom, flared shoulders, tapering to
    /// a flat top where the nib would meet the pen — plus slit and breather
    /// hole. The flat top is what stops it reading as a map pin.
    private static func nibPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 9, y: 2.0))  // tip
        // Left edge: flare out to the shoulder…
        p.addCurve(
            to: CGPoint(x: 4.8, y: 9.8),
            control1: CGPoint(x: 7.0, y: 4.2), control2: CGPoint(x: 4.8, y: 7.0))
        // …then taper gently inward toward the flat top.
        p.addCurve(
            to: CGPoint(x: 6.0, y: 15.4),
            control1: CGPoint(x: 4.8, y: 12.4), control2: CGPoint(x: 5.3, y: 14.4))
        // Flat top with slightly rounded corners.
        p.addQuadCurve(to: CGPoint(x: 6.9, y: 16.0), control: CGPoint(x: 6.3, y: 16.0))
        p.addLine(to: CGPoint(x: 11.1, y: 16.0))
        p.addQuadCurve(to: CGPoint(x: 12.0, y: 15.4), control: CGPoint(x: 11.7, y: 16.0))
        // Right edge, mirrored.
        p.addCurve(
            to: CGPoint(x: 13.2, y: 9.8),
            control1: CGPoint(x: 12.7, y: 14.4), control2: CGPoint(x: 13.2, y: 12.4))
        p.addCurve(
            to: CGPoint(x: 9, y: 2.0),
            control1: CGPoint(x: 13.2, y: 7.0), control2: CGPoint(x: 11.0, y: 4.2))
        p.closeSubpath()
        return p
    }

    private static func strokeNib(_ ctx: CGContext) {
        ctx.addPath(nibPath())
        ctx.setLineWidth(1.4)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        // Slit
        ctx.move(to: CGPoint(x: 9, y: 3.4))
        ctx.addLine(to: CGPoint(x: 9, y: 8.4))
        ctx.setLineWidth(1.1)
        ctx.setLineCap(.round)
        ctx.strokePath()
        // Breather hole
        ctx.strokeEllipse(in: CGRect(x: 7.85, y: 8.8, width: 2.3, height: 2.3))
    }

    private static func fillNib(_ ctx: CGContext, knockoutColor: CGColor? = nil) {
        ctx.addPath(nibPath())
        ctx.fillPath()
        // Punch out slit + hole so the silhouette still reads as a nib.
        if let knockoutColor {
            ctx.setStrokeColor(knockoutColor)
            ctx.setFillColor(knockoutColor)
        } else {
            ctx.setBlendMode(.clear)
        }
        ctx.move(to: CGPoint(x: 9, y: 3.4))
        ctx.addLine(to: CGPoint(x: 9, y: 8.4))
        ctx.setLineWidth(1.1)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.fillEllipse(in: CGRect(x: 7.85, y: 8.8, width: 2.3, height: 2.3))
        ctx.setBlendMode(.normal)
    }
}
