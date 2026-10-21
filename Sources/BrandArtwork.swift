import AppKit

/// One vector drawing supplies the app icon, in-app marks, and menu-bar glyph.
enum BrandArtwork {
    enum Style { case applicationIcon, brandMark, menuBar }

    static let markImage = makeImage(size: NSSize(width: 128, height: 128), style: .brandMark)
    static let menuImage = makeImage(size: NSSize(width: 18, height: 18), style: .menuBar)

    static func makeImage(size: NSSize, style: Style) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            draw(in: bounds, style: style)
            return true
        }
        image.isTemplate = style == .menuBar
        image.accessibilityDescription = "缓芽 · huǎn yá"
        return image
    }

    static func draw(in bounds: NSRect, style: Style) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let source: CGRect
        switch style {
        case .applicationIcon: source = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        case .brandMark: source = CGRect(x: 80, y: 80, width: 864, height: 864)
        case .menuBar: source = CGRect(x: 300, y: 190, width: 424, height: 620)
        }
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        context.translateBy(x: bounds.midX - source.width * scale / 2, y: bounds.midY - source.height * scale / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -source.minX, y: -source.minY)

        if style != .menuBar {
            NSColor(calibratedRed: 0.153, green: 0.306, blue: 0.239, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190).fill()
            NSColor(calibratedRed: 0.84, green: 0.93, blue: 0.68, alpha: 1).set()
        } else {
            // A template preserves the silhouette and adapts to light/dark menu bars.
            NSColor.black.set()
        }
        NSBezierPath(ovalIn: NSRect(x: 466, y: 651, width: 92, height: 92)).fill()
        stroke([NSPoint(x: 512, y: 605), NSPoint(x: 512, y: 451)], width: 76)
        stroke([NSPoint(x: 512, y: 587), NSPoint(x: 396, y: 674), NSPoint(x: 344, y: 769)], width: 43)
        stroke([NSPoint(x: 512, y: 587), NSPoint(x: 628, y: 674), NSPoint(x: 680, y: 769)], width: 43)
        stroke([NSPoint(x: 497, y: 457), NSPoint(x: 442, y: 332), NSPoint(x: 402, y: 242)], width: 53)
        stroke([NSPoint(x: 527, y: 457), NSPoint(x: 582, y: 332), NSPoint(x: 622, y: 242)], width: 53)
        if style != .menuBar {
            NSColor(calibratedRed: 0.84, green: 0.93, blue: 0.68, alpha: 0.3).set()
            stroke([NSPoint(x: 730, y: 508), NSPoint(x: 764, y: 527)], width: 9)
            stroke([NSPoint(x: 738, y: 453), NSPoint(x: 781, y: 453)], width: 9)
            stroke([NSPoint(x: 294, y: 508), NSPoint(x: 260, y: 527)], width: 9)
            stroke([NSPoint(x: 286, y: 453), NSPoint(x: 243, y: 453)], width: 9)
        }
    }

    private static func stroke(_ points: [NSPoint], width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = width
        path.stroke()
    }

    static func png(size: Int, style: Style) -> Data? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(in: NSRect(x: 0, y: 0, width: size, height: size), style: style)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
