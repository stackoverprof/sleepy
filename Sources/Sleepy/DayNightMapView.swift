import AppKit
import SleepyCore

/// The day and night world map that sits at the top of the Sleepy menu: a
/// grey-on-black plate, a caption row, and an hour scale along the bottom.
@MainActor
final class DayNightMapView: NSView {
    static let preferredSize = NSSize(width: 268, height: 190)

    private enum Layout {
        static let horizontalInset: CGFloat = 12
        static let topInset: CGFloat = 8
        static let captionHeight: CGFloat = 11
        static let captionGap: CGFloat = 7
        static let tickLength: CGFloat = 3
        static let scaleHeight: CGFloat = 14
        static let prayerRowHeight: CGFloat = 28
        static let bottomInset: CGFloat = 6
        static let cornerRadius: CGFloat = 6

        static var chromeHeight: CGFloat {
            topInset + captionHeight + captionGap + scaleHeight + prayerRowHeight + bottomInset
        }
    }

    private enum Ink {
        static let border = NSColor(white: 1, alpha: 0.10)
        static let graticule = NSColor(white: 1, alpha: 0.055)
        static let equator = NSColor(white: 1, alpha: 0.10)
        static let meridian = NSColor(white: 1, alpha: 0.22)
        static let prayerMeridian = NSColor(white: 1, alpha: 0.15)
        static let nextPrayerMeridian = NSColor(white: 1, alpha: 0.8)
        static let nextPrayerGlow = NSColor(white: 1, alpha: 0.1)
        static let marker = NSColor(white: 0.93, alpha: 1)
        static let markerRim = NSColor(white: 0, alpha: 0.65)
        static let sun = NSColor(white: 0.93, alpha: 1)
        static let sunRim = NSColor(white: 0, alpha: 0.65)
    }

    private let captionFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
    private let readoutFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)
    private let prayerNameFont = NSFont.systemFont(ofSize: 7, weight: .semibold)
    private let prayerTimeFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)

    /// Where the Mac is. The prayer meridians and the marker need it; the map
    /// itself does not.
    var place: Coordinate? {
        didSet {
            guard place != oldValue else { return }
            renderedMinute = nil
            refresh()
        }
    }

    private var solar = SolarPositionCalculator.position(at: Date())
    private var terrain: NSImage?
    private var renderedMinute: Date?
    private var clock = ""
    private var prayers: PrayerDay?
    private var nextPrayer: Prayer?

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

        if let place {
            prayers = PrayerCalculator.day(containing: date, at: place)
            nextPrayer = PrayerCalculator.next(after: date, at: place)?.prayer
        } else {
            prayers = nil
            nextPrayer = nil
        }
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
        drawPrayerMeridians(in: mapRect)
        drawNoonMeridian(in: mapRect)
        drawSun(in: mapRect)
        drawPlace(in: mapRect)

        NSGraphicsContext.restoreGraphicsState()

        Ink.border.setStroke()
        plate.lineWidth = 1
        plate.stroke()

        drawHourScale(below: mapRect)
        drawPrayerRow(below: mapRect)
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

    /// One meridian per prayer, marking where in the world that prayer is
    /// being called right now. They sweep west, so a line east of the marker
    /// is a prayer still to come.
    private func drawPrayerMeridians(in mapRect: NSRect) {
        guard let prayers else { return }

        let meridians = NSBezierPath()
        var approaching: CGFloat?

        for event in prayers.events {
            let x = point(
                latitude: 0,
                longitude: solar.longitude(forHourAngle: event.hourAngle),
                in: mapRect
            ).x.rounded() + 0.5

            if event.prayer == nextPrayer {
                approaching = x
                continue
            }

            // Dhuhr rides the noon meridian, which is drawn already.
            guard event.prayer != .dhuhr else { continue }

            meridians.move(to: NSPoint(x: x, y: mapRect.minY))
            meridians.line(to: NSPoint(x: x, y: mapRect.maxY))
        }

        meridians.lineWidth = 1
        meridians.setLineDash([1, 3], count: 2, phase: 0)
        Ink.prayerMeridian.setStroke()
        meridians.stroke()

        guard let approaching else { return }
        drawApproachingMeridian(at: approaching, in: mapRect)
    }

    /// The prayer coming next gets a solid lit meridian and a marker on the
    /// rail above it, so the eye finds it before reading any of the numbers.
    private func drawApproachingMeridian(at x: CGFloat, in mapRect: NSRect) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: mapRect.minY))
        line.line(to: NSPoint(x: x, y: mapRect.maxY))

        Ink.nextPrayerGlow.setStroke()
        line.lineWidth = 3
        line.stroke()

        Ink.nextPrayerMeridian.setStroke()
        line.lineWidth = 1
        line.stroke()

        let head = NSBezierPath()
        head.move(to: NSPoint(x: x - 3.5, y: mapRect.maxY))
        head.line(to: NSPoint(x: x + 3.5, y: mapRect.maxY))
        head.line(to: NSPoint(x: x, y: mapRect.maxY - 4.5))
        head.close()

        Ink.nextPrayerMeridian.setFill()
        head.fill()
    }

    private func drawPlace(in mapRect: NSRect) {
        guard let place else { return }

        let center = point(latitude: place.latitude, longitude: place.longitude, in: mapRect)
        let ring = NSBezierPath(ovalIn: circle(around: center, radius: 3))

        Ink.markerRim.setStroke()
        ring.lineWidth = 2.5
        ring.stroke()

        Ink.marker.setStroke()
        ring.lineWidth = 1
        ring.stroke()

        Ink.marker.setFill()
        NSBezierPath(ovalIn: circle(around: center, radius: 0.75)).fill()
    }

    /// The five prayers for today at this place, with the next one lit.
    private func drawPrayerRow(below mapRect: NSRect) {
        let top = mapRect.minY - Layout.scaleHeight
        let columnWidth = mapRect.width / CGFloat(Prayer.allCases.count)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        for (index, prayer) in Prayer.allCases.enumerated() {
            let isNext = prayer == nextPrayer
            let center = mapRect.minX + columnWidth * (CGFloat(index) + 0.5)

            let name = NSAttributedString(
                string: prayer.displayName.uppercased(),
                attributes: [
                    .font: prayerNameFont,
                    .kern: 0.6,
                    .foregroundColor: isNext ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
                ]
            )

            let event = prayers?[prayer]
            let time = NSAttributedString(
                string: event.map { formatter.string(from: rounded($0.date)) } ?? "--:--",
                attributes: [
                    .font: prayerTimeFont,
                    .foregroundColor: isNext ? NSColor.labelColor : NSColor.secondaryLabelColor
                ]
            )

            let nameSize = name.size()
            let timeSize = time.size()
            name.draw(at: NSPoint(
                x: (center - nameSize.width / 2).rounded(),
                y: (top - nameSize.height - 1).rounded()
            ))
            time.draw(at: NSPoint(
                x: (center - timeSize.width / 2).rounded(),
                y: (top - nameSize.height - timeSize.height - 1).rounded()
            ))
        }
    }

    /// Prayer times are published to the minute, so round rather than let the
    /// formatter drop the seconds and read a minute early.
    private func rounded(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
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
