import Foundation

/// A point on the Earth, in degrees north and east.
public struct Coordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum Prayer: String, CaseIterable, Sendable {
    case fajr
    case dhuhr
    case asr
    case maghrib
    case isha

    public var displayName: String {
        switch self {
        case .fajr: "Fajr"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }
}

/// The parameters a prayer timetable is calculated from: how far the sun sits
/// below the horizon at Fajr and Isha, how long a shadow has to grow before
/// Asr, and the ihtiyati minutes added as a margin.
public struct PrayerConvention: Equatable, Sendable {
    public let fajrAngle: Double
    public let ishaAngle: Double
    public let asrShadowFactor: Double
    public let safetyMinutes: Double

    public init(
        fajrAngle: Double,
        ishaAngle: Double,
        asrShadowFactor: Double,
        safetyMinutes: Double
    ) {
        self.fajrAngle = fajrAngle
        self.ishaAngle = ishaAngle
        self.asrShadowFactor = asrShadowFactor
        self.safetyMinutes = safetyMinutes
    }

    /// Kementerian Agama Republik Indonesia: 20 degrees for Fajr, 18 for Isha,
    /// the Shafi'i shadow for Asr, and two minutes of ihtiyati.
    public static let kemenag = PrayerConvention(
        fajrAngle: -20,
        ishaAngle: -18,
        asrShadowFactor: 1,
        safetyMinutes: 2
    )

    /// The same maths without the margin, which is what most published
    /// calculators show.
    public static let muslimWorldLeague = PrayerConvention(
        fajrAngle: -18,
        ishaAngle: -17,
        asrShadowFactor: 1,
        safetyMinutes: 0
    )
}

public struct PrayerEvent: Equatable, Sendable {
    public let prayer: Prayer
    public let date: Date

    /// Where the sun stands relative to the local meridian at this prayer, in
    /// degrees: negative before noon, positive after. The map turns this into
    /// the meridian the prayer is sweeping along right now.
    public let hourAngle: Double

    public init(prayer: Prayer, date: Date, hourAngle: Double) {
        self.prayer = prayer
        self.date = date
        self.hourAngle = hourAngle
    }
}

/// One day of prayers at one place. A prayer is missing only where the sun
/// never reaches its angle, which happens through the polar summer.
public struct PrayerDay: Equatable, Sendable {
    public let events: [PrayerEvent]

    public init(events: [PrayerEvent]) {
        self.events = events
    }

    public subscript(prayer: Prayer) -> PrayerEvent? {
        events.first { $0.prayer == prayer }
    }

    public func next(after date: Date) -> PrayerEvent? {
        events.first { $0.date > date }
    }
}

public enum PrayerCalculator {
    /// The prayers of the calendar day that `date` falls in.
    public static func day(
        containing date: Date,
        at coordinate: Coordinate,
        timeZone: TimeZone = .current,
        convention: PrayerConvention = .kemenag
    ) -> PrayerDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let noonEstimate = calendar.startOfDay(for: date).addingTimeInterval(12 * 3_600)
        let transit = solarNoon(near: noonEstimate, longitude: coordinate.longitude)
        let margin = convention.safetyMinutes * 60

        var events: [PrayerEvent] = []

        if let fajr = event(
            altitude: { _ in convention.fajrAngle },
            afternoon: false,
            transit: transit,
            coordinate: coordinate
        ) {
            events.append(
                PrayerEvent(
                    prayer: .fajr,
                    date: fajr.date.addingTimeInterval(margin),
                    hourAngle: fajr.hourAngle + convention.safetyMinutes / 4
                )
            )
        }

        events.append(
            PrayerEvent(
                prayer: .dhuhr,
                date: transit.addingTimeInterval(margin),
                hourAngle: convention.safetyMinutes / 4
            )
        )

        // Asr arrives when a shadow has grown by the convention's factor on top
        // of the shadow the sun already casts at noon.
        if let asr = event(
            altitude: { declination in
                altitude(
                    for: .asr,
                    latitude: coordinate.latitude,
                    declination: declination,
                    convention: convention
                ) ?? 0
            },
            afternoon: true,
            transit: transit,
            coordinate: coordinate
        ) {
            events.append(
                PrayerEvent(
                    prayer: .asr,
                    date: asr.date.addingTimeInterval(margin),
                    hourAngle: asr.hourAngle + convention.safetyMinutes / 4
                )
            )
        }

        if let maghrib = event(
            altitude: { _ in sunsetAltitude },
            afternoon: true,
            transit: transit,
            coordinate: coordinate
        ) {
            events.append(
                PrayerEvent(
                    prayer: .maghrib,
                    date: maghrib.date.addingTimeInterval(margin),
                    hourAngle: maghrib.hourAngle + convention.safetyMinutes / 4
                )
            )
        }

        if let isha = event(
            altitude: { _ in convention.ishaAngle },
            afternoon: true,
            transit: transit,
            coordinate: coordinate
        ) {
            events.append(
                PrayerEvent(
                    prayer: .isha,
                    date: isha.date.addingTimeInterval(margin),
                    hourAngle: isha.hourAngle + convention.safetyMinutes / 4
                )
            )
        }

        return PrayerDay(events: events.sorted { $0.date < $1.date })
    }

    /// The next prayer due, rolling into tomorrow once Isha has passed.
    public static func next(
        after date: Date,
        at coordinate: Coordinate,
        timeZone: TimeZone = .current,
        convention: PrayerConvention = .kemenag
    ) -> PrayerEvent? {
        let today = day(containing: date, at: coordinate, timeZone: timeZone, convention: convention)
        if let event = today.next(after: date) {
            return event
        }

        let tomorrow = day(
            containing: date.addingTimeInterval(24 * 3_600),
            at: coordinate,
            timeZone: timeZone,
            convention: convention
        )
        return tomorrow.events.first
    }

    /// Sunset for the upper limb of the sun, allowing for refraction.
    public static let sunsetAltitude = -0.8333

    /// The sun's altitude that defines a prayer. Asr moves with latitude and
    /// season, because it is a shadow length rather than a fixed angle, and
    /// Dhuhr has no defining altitude at all: it is the meridian itself.
    public static func altitude(
        for prayer: Prayer,
        latitude: Double,
        declination: Double,
        convention: PrayerConvention = .kemenag
    ) -> Double? {
        switch prayer {
        case .fajr:
            convention.fajrAngle
        case .dhuhr:
            nil
        case .asr:
            SolarMath.degrees(
                atan(
                    1 / (
                        convention.asrShadowFactor
                            + tan(abs(SolarMath.radians(latitude) - SolarMath.radians(declination)))
                    )
                )
            )
        case .maghrib:
            sunsetAltitude
        case .isha:
            convention.ishaAngle
        }
    }

    /// How far off the meridian the sun stands when it reaches an altitude at a
    /// latitude, in degrees. Nil where it never reaches it: through the polar
    /// summer there is no Fajr to find.
    public static func hourAngle(
        altitude: Double,
        latitude: Double,
        declination: Double
    ) -> Double? {
        let latitude = SolarMath.radians(latitude)
        let declination = SolarMath.radians(declination)
        let cosine = (sin(SolarMath.radians(altitude)) - sin(latitude) * sin(declination))
            / (cos(latitude) * cos(declination))
        guard abs(cosine) <= 1 else { return nil }
        return SolarMath.degrees(acos(cosine))
    }

    /// Longitude, in degrees east, where `prayer` is being called right now at
    /// this latitude.
    ///
    /// This is what the map draws. Only Dhuhr is a meridian: the rest trace
    /// curves, since the sun has to climb further at higher latitudes to reach
    /// the same angle, and at some point it never gets there at all.
    public static func longitude(
        of prayer: Prayer,
        atLatitude latitude: Double,
        solar: SolarPosition,
        convention: PrayerConvention = .kemenag
    ) -> Double? {
        let margin = convention.safetyMinutes / 4

        guard prayer != .dhuhr else {
            return solar.longitude(forHourAngle: margin)
        }

        guard
            let altitude = altitude(
                for: prayer,
                latitude: latitude,
                declination: solar.subsolarLatitude,
                convention: convention
            ),
            let hourAngle = hourAngle(
                altitude: altitude,
                latitude: latitude,
                declination: solar.subsolarLatitude
            )
        else {
            return nil
        }

        return solar.longitude(forHourAngle: (prayer == .fajr ? -hourAngle : hourAngle) + margin)
    }

    /// Local solar noon: the moment the sun stands over this meridian.
    private static func solarNoon(near estimate: Date, longitude: Double) -> Date {
        var transit = estimate
        for _ in 0..<3 {
            let solar = SolarPositionCalculator.position(at: transit)
            // How far past the local meridian the sun already is, which is
            // how far back solar noon sits.
            let hourAngle = SolarMath.wrapped180(longitude - solar.subsolarLongitude)
            transit = transit.addingTimeInterval(-hourAngle / 15 * 3_600)
        }
        return transit
    }

    /// Solves for the moment the sun reaches an altitude, which the caller
    /// gives as a function of the declination so Asr can move with the season.
    private static func event(
        altitude: (Double) -> Double,
        afternoon: Bool,
        transit: Date,
        coordinate: Coordinate
    ) -> (date: Date, hourAngle: Double)? {
        var hourAngle = 0.0
        var moment = transit

        for _ in 0..<3 {
            let solar = SolarPositionCalculator.position(at: moment)
            let declination = SolarMath.radians(solar.subsolarLatitude)
            let latitude = SolarMath.radians(coordinate.latitude)
            let target = SolarMath.radians(altitude(solar.subsolarLatitude))

            let cosine = (sin(target) - sin(latitude) * sin(declination))
                / (cos(latitude) * cos(declination))
            guard abs(cosine) <= 1 else { return nil }

            hourAngle = SolarMath.degrees(acos(cosine)) * (afternoon ? 1 : -1)
            moment = transit.addingTimeInterval(hourAngle / 15 * 3_600)
        }

        return (moment, hourAngle)
    }
}
