import AppKit
import SleepyCore

/// The day and night world map that sits at the top of the Sleepy menu: a
/// grey-on-black plate, a caption row, and an hour scale along the bottom.
@MainActor
final class DayNightMapView: NSView {
    static let preferredSize = NSSize(width: 268, height: 170)

    private enum Layout {
        static let horizontalInset: CGFloat = 12
        static let topInset: CGFloat = 8
        static let captionHeight: CGFloat = 11
        static let captionGap: CGFloat = 7
        static let tickLength: CGFloat = 3
        static let scaleHeight: CGFloat = 14
        static let bottomInset: CGFloat = 7
        static let cornerRadius: CGFloat = 6

        static var chromeHeight: CGFloat {
            topInset + captionHeight + captionGap + scaleHeight + bottomInset
        }
    }

    private enum Ink {
        static let border = NSColor(white: 1, alpha: 0.10)
        static let graticule = NSColor(white: 1, alpha: 0.055)
        static let equator = NSColor(white: 1, alpha: 0.10)
        static let meridian = NSColor(white: 1, alpha: 0.22)
        static let sun = NSColor(white: 0.93, alpha: 1)
        static let sunRim = NSColor(white: 0, alpha: 0.65)
    }

    private let captionFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
    private let readoutFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)

    private var solar = SolarPositionCalculator.position(at: Date())
    private var terrain: NSImage?
    private var renderedMinute: Date?
    private var clock = ""

    override var allowsVibrancy: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        render(at: Date())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Redraws the shading for the current moment. The terrain image only
    /// changes once a minute, which is far finer than the terminator moves.
    func refresh(at date: Date = Date()) {
        let minute = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
        if renderedMinute != minute {
            render(at: date)
            renderedMinute = minute
        }
        needsDisplay = true
    }

    private func render(at date: Date) {
        solar = SolarPositionCalculator.position(at: date)
        terrain = DayNightMap.image(for: solar)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        clock = formatter.string(from: date)
    }

    override func draw(_ dirtyRect: NSRect) {
        let mapRect = mapFrame()
        let plate = NSBezierPath(
            roundedRect: mapRect,
            xRadius: Layout.cornerRadius,
            yRadius: Layout.cornerRadius
        )

        drawCaption(above: mapRect)

        NSGraphicsContext.saveGraphicsState()
        plate.addClip()

        NSColor(white: DayNightMap.Palette.oceanNight, alpha: 1).setFill()
        mapRect.fill()

        if let terrain {
            NSGraphicsContext.current?.imageInterpolation = .high
            terrain.draw(in: mapRect)
        }

        drawGraticule(in: mapRect)
        drawNoonMeridian(in: mapRect)
        drawSun(in: mapRect)

        NSGraphicsContext.restoreGraphicsState()

        Ink.border.setStroke()
        plate.lineWidth = 1
        plate.stroke()

        drawHourScale(below: mapRect)
    }

    /// A plate that keeps the projection's proportions whatever width the menu
    /// hands the view, with the caption and hour scale in the space left over.
    private func mapFrame() -> NSRect {
        let width = min(
            (bounds.width - Layout.horizontalInset * 2).rounded(),
            ((bounds.height - Layout.chromeHeight) * DayNightMap.aspectRatio).rounded()
        )
        let height = (width / DayNightMap.aspectRatio).rounded()
        return NSRect(
            x: ((bounds.width - width) / 2).rounded(),
            y: (bounds.height - Layout.topInset - Layout.captionHeight - Layout.captionGap - height).rounded(),
            width: width,
            height: height
        )
    }

    private func drawCaption(above mapRect: NSRect) {
        let baseline = mapRect.maxY + Layout.captionGap

        let title = NSAttributedString(
            string: "DAY & NIGHT",
            attributes: [
                .font: captionFont,
                .kern: 0.8,
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        title.draw(at: NSPoint(x: mapRect.minX, y: baseline))

        let readout = NSAttributedString(
            string: clock,
            attributes: [
                .font: readoutFont,
                .kern: 0.3,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        readout.draw(at: NSPoint(x: mapRect.maxX - readout.size().width, y: baseline))
    }

    private func drawGraticule(in mapRect: NSRect) {
        let lines = NSBezierPath()
        for longitude in stride(from: -120.0, through: 120.0, by: 60) {
            let x = point(latitude: 0, longitude: longitude, in: mapRect).x
            lines.move(to: NSPoint(x: x, y: mapRect.minY))
            lines.line(to: NSPoint(x: x, y: mapRect.maxY))
        }
        for latitude in [-60.0, -30.0, 30.0, 60.0] {
            let y = point(latitude: latitude, longitude: 0, in: mapRect).y
            lines.move(to: NSPoint(x: mapRect.minX, y: y))
            lines.line(to: NSPoint(x: mapRect.maxX, y: y))
        }
        Ink.graticule.setStroke()
        lines.lineWidth = 0.5
        lines.stroke()

        let equator = NSBezierPath()
        let y = point(latitude: 0, longitude: 0, in: mapRect).y
        equator.move(to: NSPoint(x: mapRect.minX, y: y))
        equator.line(to: NSPoint(x: mapRect.maxX, y: y))
        Ink.equator.setStroke()
        equator.lineWidth = 0.5
        equator.stroke()
    }

    /// The meridian the sun is standing over: noon everywhere along it.
    private func drawNoonMeridian(in mapRect: NSRect) {
        let x = point(latitude: 0, longitude: solar.subsolarLongitude, in: mapRect).x
        let meridian = NSBezierPath()
        meridian.move(to: NSPoint(x: x.rounded() + 0.5, y: mapRect.minY))
        meridian.line(to: NSPoint(x: x.rounded() + 0.5, y: mapRect.maxY))
        meridian.lineWidth = 1
        meridian.setLineDash([1, 3], count: 2, phase: 0)
        Ink.meridian.setStroke()
        meridian.stroke()
    }

    private func drawSun(in mapRect: NSRect) {
        let center = point(
            latitude: solar.subsolarLatitude,
            longitude: solar.subsolarLongitude,
            in: mapRect
        )

        // Drawing the wrapped copies too keeps the marker whole when the sun
        // stands over the antimeridian.
        for offset in [-mapRect.width, 0, mapRect.width] {
            let dot = NSBezierPath(
                ovalIn: circle(around: NSPoint(x: center.x + offset, y: center.y), radius: 2.5)
            )

            Ink.sun.setFill()
            dot.fill()

            // A dark rim keeps the marker legible where it crosses lit land.
            Ink.sunRim.setStroke()
            dot.lineWidth = 1
            dot.stroke()
        }
    }

    /// Hour stamps along the bottom: apparent solar time, so 12 always sits
    /// under the sun and 00 under the far side of the world.
    private func drawHourScale(below mapRect: NSRect) {
        let ticks = NSBezierPath()

        for hour in stride(from: 0, to: 24, by: 3) {
            let x = point(
                latitude: 0,
                longitude: solar.longitude(forSolarHour: Double(hour)),
                in: mapRect
            ).x

            ticks.move(to: NSPoint(x: x.rounded() + 0.5, y: mapRect.minY))
            ticks.line(to: NSPoint(x: x.rounded() + 0.5, y: mapRect.minY - Layout.tickLength))

            let stamp = NSAttributedString(
                string: String(format: "%02d", hour),
                attributes: [
                    .font: readoutFont,
                    .kern: 0.4,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
            )
            let size = stamp.size()

            // Stamps sit under their tick, nudged only enough to stay inside
            // the view when a tick lands on the edge of the map.
            let left = min(
                max(x - size.width / 2, bounds.minX + 1),
                bounds.maxX - size.width - 1
            )
            stamp.draw(
                at: NSPoint(
                    x: left.rounded(),
                    y: mapRect.minY - Layout.tickLength - size.height - 1
                )
            )
        }

        NSColor.quaternaryLabelColor.setStroke()
        ticks.lineWidth = 1
        ticks.stroke()
    }

    private func point(latitude: Double, longitude: Double, in mapRect: NSRect) -> NSPoint {
        NSPoint(
            x: mapRect.minX + (longitude + 180) / 360 * mapRect.width,
            y: mapRect.minY
                + (latitude + DayNightMap.visibleLatitude)
                / (DayNightMap.visibleLatitude * 2) * mapRect.height
        )
    }

    private func circle(around center: NSPoint, radius: Double) -> NSRect {
        NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}
