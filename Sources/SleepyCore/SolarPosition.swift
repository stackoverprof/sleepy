import Foundation

/// Where the sun stands over the Earth at one instant.
///
/// The sun is directly overhead at the subsolar point, so the daylit half of
/// the world is the half facing it.
public struct SolarPosition: Equatable, Sendable {
    /// Latitude of the subsolar point, in degrees north.
    public let subsolarLatitude: Double

    /// Longitude of the subsolar point, in degrees east, wrapped to -180...180.
    public let subsolarLongitude: Double

    public init(subsolarLatitude: Double, subsolarLongitude: Double) {
        self.subsolarLatitude = subsolarLatitude
        self.subsolarLongitude = subsolarLongitude
    }

    /// Height of the sun above the horizon, in degrees, seen from a location.
    ///
    /// Positive means daylight, negative means night, and the values in
    /// between trace the twilight band.
    public func elevation(latitude: Double, longitude: Double) -> Double {
        SolarMath.degrees(asin(sineOfElevation(latitude: latitude, longitude: longitude)))
    }

    /// Longitude, in degrees east, where the clock currently reads `hour` in
    /// apparent solar time. Hour 12 is the noon meridian the sun stands over.
    public func longitude(forSolarHour hour: Double) -> Double {
        SolarMath.wrapped180(subsolarLongitude + (hour - 12) * 15)
    }

    /// Sine of ``elevation(latitude:longitude:)``, which is what shading the
    /// map actually needs.
    public func sineOfElevation(latitude: Double, longitude: Double) -> Double {
        let declination = SolarMath.radians(subsolarLatitude)
        let localLatitude = SolarMath.radians(latitude)
        let hourAngle = SolarMath.radians(longitude - subsolarLongitude)
        let value = sin(localLatitude) * sin(declination)
            + cos(localLatitude) * cos(declination) * cos(hourAngle)
        return min(max(value, -1), 1)
    }
}

/// Solar position from the low-precision NOAA solar equations, which stay
/// within a fraction of a degree for any date this app will ever show.
public enum SolarPositionCalculator {
    public static func position(at date: Date) -> SolarPosition {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let century = (julianDay - 2_451_545.0) / 36_525.0

        let meanLongitude = SolarMath.wrapped360(
            280.46646 + century * (36_000.76983 + century * 0.0003032)
        )
        let meanAnomaly = 357.52911 + century * (35_999.05029 - century * 0.0001537)
        let eccentricity = 0.016708634 - century * (0.000042037 + century * 0.0000001267)

        let equationOfCenter =
            sin(SolarMath.radians(meanAnomaly))
                * (1.914602 - century * (0.004817 + century * 0.000014))
            + sin(SolarMath.radians(2 * meanAnomaly)) * (0.019993 - century * 0.000101)
            + sin(SolarMath.radians(3 * meanAnomaly)) * 0.000289

        let moonAscendingNode = 125.04 - century * 1_934.136
        let apparentLongitude = meanLongitude + equationOfCenter
            - 0.00569
            - 0.00478 * sin(SolarMath.radians(moonAscendingNode))

        let meanObliquity = 23
            + (26 + (21.448 - century * (46.815 + century * (0.00059 - century * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(SolarMath.radians(moonAscendingNode))

        let declination = SolarMath.degrees(
            asin(sin(SolarMath.radians(obliquity)) * sin(SolarMath.radians(apparentLongitude)))
        )

        // Equation of time, in minutes: how far true solar noon drifts from
        // mean noon on this date.
        let varianceY = pow(tan(SolarMath.radians(obliquity / 2)), 2)
        let equationOfTime = 4 * SolarMath.degrees(
            varianceY * sin(SolarMath.radians(2 * meanLongitude))
                - 2 * eccentricity * sin(SolarMath.radians(meanAnomaly))
                + 4 * eccentricity * varianceY
                    * sin(SolarMath.radians(meanAnomaly))
                    * cos(SolarMath.radians(2 * meanLongitude))
                - 0.5 * varianceY * varianceY * sin(SolarMath.radians(4 * meanLongitude))
                - 1.25 * eccentricity * eccentricity * sin(SolarMath.radians(2 * meanAnomaly))
        )

        let minutesIntoUTCDay = SolarMath.minutesIntoUTCDay(of: date)
        let subsolarLongitude = SolarMath.wrapped180(
            180 - (minutesIntoUTCDay + equationOfTime) / 4
        )

        return SolarPosition(
            subsolarLatitude: declination,
            subsolarLongitude: subsolarLongitude
        )
    }
}

enum SolarMath {
    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    static func wrapped360(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    static func wrapped180(_ degrees: Double) -> Double {
        let value = wrapped360(degrees + 180) - 180
        return value == 180 ? -180 : value
    }

    static func minutesIntoUTCDay(of date: Date) -> Double {
        let seconds = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400)
        return (seconds < 0 ? seconds + 86_400 : seconds) / 60
    }
}
