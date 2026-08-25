import Foundation
import Testing
@testable import SleepyCore

private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: components)!
}

@Test
func subsolarPointFollowsUTCTime() {
    // Solar noon crosses Greenwich at 12:00 UTC and the antimeridian at
    // midnight, give or take the equation of time.
    let noon = SolarPositionCalculator.position(at: utc(2026, 8, 24, 12))
    #expect(abs(noon.subsolarLongitude) < 5)

    let midnight = SolarPositionCalculator.position(at: utc(2026, 8, 24, 0))
    #expect(abs(midnight.subsolarLongitude) > 175)

    let evening = SolarPositionCalculator.position(at: utc(2026, 8, 24, 18))
    #expect(abs(evening.subsolarLongitude + 90) < 5)
}

@Test
func subsolarLatitudeTracksTheSeasons() {
    let juneSolstice = SolarPositionCalculator.position(at: utc(2026, 6, 21, 12))
    #expect(abs(juneSolstice.subsolarLatitude - 23.43) < 0.2)

    let decemberSolstice = SolarPositionCalculator.position(at: utc(2026, 12, 21, 12))
    #expect(abs(decemberSolstice.subsolarLatitude + 23.43) < 0.2)

    let marchEquinox = SolarPositionCalculator.position(at: utc(2026, 3, 20, 14, 46))
    #expect(abs(marchEquinox.subsolarLatitude) < 0.2)
}

@Test
func elevationPeaksAtTheSubsolarPointAndBottomsOutOpposite() {
    let solar = SolarPositionCalculator.position(at: utc(2026, 8, 24, 9, 30))

    let overhead = solar.elevation(
        latitude: solar.subsolarLatitude,
        longitude: solar.subsolarLongitude
    )
    #expect(abs(overhead - 90) < 0.001)

    let antipode = solar.elevation(
        latitude: -solar.subsolarLatitude,
        longitude: solar.subsolarLongitude + 180
    )
    #expect(abs(antipode + 90) < 0.001)
}

@Test
func daylightFallsOnTheHalfFacingTheSun() {
    let solar = SolarPosition(subsolarLatitude: 0, subsolarLongitude: 0)

    #expect(solar.elevation(latitude: 0, longitude: 45) > 0)
    #expect(solar.elevation(latitude: 0, longitude: -45) > 0)
    #expect(solar.elevation(latitude: 0, longitude: 135) < 0)
    #expect(abs(solar.elevation(latitude: 0, longitude: 90)) < 0.001)
    #expect(abs(solar.elevation(latitude: 90, longitude: 0)) < 0.001)
}

@Test
func solarHoursMapOntoLongitudes() {
    let solar = SolarPosition(subsolarLatitude: 0, subsolarLongitude: 35)

    #expect(solar.longitude(forSolarHour: 12) == 35)
    #expect(solar.longitude(forSolarHour: 18) == 125)
    #expect(solar.longitude(forSolarHour: 6) == -55)
    #expect(solar.longitude(forSolarHour: 0) == -145)
    #expect(solar.longitude(forSolarHour: 23) == -180 + 20)

    // Noon is wherever the sun stands, at every time of year.
    let now = SolarPositionCalculator.position(at: utc(2026, 8, 25, 9, 40))
    #expect(now.longitude(forSolarHour: 12) == now.subsolarLongitude)
    let midnight = now.elevation(
        latitude: -now.subsolarLatitude,
        longitude: now.longitude(forSolarHour: 0)
    )
    #expect(abs(midnight + 90) < 0.001)
}

@Test
func longitudesWrapIntoASingleRange() {
    #expect(SolarMath.wrapped180(190) == -170)
    #expect(SolarMath.wrapped180(-190) == 170)
    #expect(SolarMath.wrapped180(180) == -180)
    #expect(SolarMath.wrapped360(-10) == 350)
}
