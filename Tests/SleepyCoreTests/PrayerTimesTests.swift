import Foundation
import Testing
@testable import SleepyCore

private let jakarta = Coordinate(latitude: -6.2088, longitude: 106.8456)
private let jakartaZone = TimeZone(identifier: "Asia/Jakarta")!

/// Kemenag angles without the ihtiyati margin, which is what published
/// calculators show and what the fixtures below were taken from.
private let kemenagAngles = PrayerConvention(
    fajrAngle: -20,
    ishaAngle: -18,
    asrShadowFactor: 1,
    safetyMinutes: 0
)

private func noon(_ day: String, _ zone: TimeZone) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd-MM-yyyy HH:mm"
    formatter.timeZone = zone
    return formatter.date(from: "\(day) 12:00")!
}

private func clock(_ date: Date, _ zone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = zone
    return formatter.string(from: date)
}

/// Compares against published timetables to the minute. The fixtures come from
/// the Kemenag and Muslim World League tables for these dates.
@Test(arguments: [
    ("25-08-2026", ["04:38", "11:55", "15:14", "17:53", "19:04"]),
    ("15-01-2026", ["04:25", "12:02", "15:26", "18:15", "19:30"]),
    ("21-06-2026", ["04:38", "11:54", "15:16", "17:47", "19:02"]),
    ("21-12-2026", ["04:11", "11:51", "15:18", "18:05", "19:21"])
])
func jakartaMatchesPublishedTimes(day: String, expected: [String]) {
    let times = PrayerCalculator.day(
        containing: noon(day, jakartaZone),
        at: jakarta,
        timeZone: jakartaZone,
        convention: kemenagAngles
    )

    #expect(times.events.count == 5)
    for (event, published) in zip(times.events, expected) {
        let minutes = abs(event.date.timeIntervalSince(
            reference(published, on: day, in: jakartaZone)
        )) / 60
        #expect(minutes < 1, "\(event.prayer.displayName) \(clock(event.date, jakartaZone)) vs \(published)")
    }
}

private func reference(_ time: String, on day: String, in zone: TimeZone) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd-MM-yyyy HH:mm"
    formatter.timeZone = zone
    return formatter.date(from: "\(day) \(time)")!
}

@Test
func istanbulMatchesMuslimWorldLeague() {
    let zone = TimeZone(identifier: "Europe/Istanbul")!
    let times = PrayerCalculator.day(
        containing: noon("21-06-2026", zone),
        at: Coordinate(latitude: 41.0082, longitude: 28.9784),
        timeZone: zone,
        convention: .muslimWorldLeague
    )

    #expect(clock(times[.fajr]!.date, zone) == "03:24")
    #expect(clock(times[.dhuhr]!.date, zone) == "13:05")
    #expect(clock(times[.asr]!.date, zone) == "17:06")
    #expect(clock(times[.maghrib]!.date, zone) == "20:39")
    #expect(clock(times[.isha]!.date, zone) == "22:38")
}

@Test
func kemenagAddsItsSafetyMargin() {
    let plain = PrayerCalculator.day(
        containing: noon("25-08-2026", jakartaZone),
        at: jakarta,
        timeZone: jakartaZone,
        convention: kemenagAngles
    )
    let kemenag = PrayerCalculator.day(
        containing: noon("25-08-2026", jakartaZone),
        at: jakarta,
        timeZone: jakartaZone,
        convention: .kemenag
    )

    for (margined, plain) in zip(kemenag.events, plain.events) {
        #expect(abs(margined.date.timeIntervalSince(plain.date) - 120) < 0.001)
        #expect(abs(margined.hourAngle - plain.hourAngle - 0.5) < 0.001)
    }
}

@Test
func hourAnglesRunFromNightToNight() {
    let times = PrayerCalculator.day(
        containing: noon("25-08-2026", jakartaZone),
        at: jakarta,
        timeZone: jakartaZone,
        convention: .kemenag
    )

    #expect(times[.fajr]!.hourAngle < -90)
    #expect(abs(times[.dhuhr]!.hourAngle) < 1)
    #expect(times[.isha]!.hourAngle > 90)
    #expect(times.events.map(\.hourAngle) == times.events.map(\.hourAngle).sorted())
}

@Test
func polarSummerDropsThePrayersTheSunNeverReaches() {
    let zone = TimeZone(identifier: "Europe/Oslo")!
    let times = PrayerCalculator.day(
        containing: noon("21-06-2026", zone),
        at: Coordinate(latitude: 69.65, longitude: 18.96),
        timeZone: zone,
        convention: .muslimWorldLeague
    )

    #expect(times[.fajr] == nil)
    #expect(times[.maghrib] == nil)
    #expect(times[.isha] == nil)
    #expect(times[.dhuhr] != nil)
    #expect(times[.asr] != nil)
}

@Test
func nextPrayerRollsIntoTomorrow() {
    let afterIsha = reference("23:30", on: "25-08-2026", in: jakartaZone)
    let event = PrayerCalculator.next(after: afterIsha, at: jakarta, timeZone: jakartaZone)

    #expect(event?.prayer == .fajr)
    #expect(clock(event!.date, jakartaZone) == "04:39")

    let morning = reference("05:00", on: "25-08-2026", in: jakartaZone)
    #expect(PrayerCalculator.next(after: morning, at: jakarta, timeZone: jakartaZone)?.prayer == .dhuhr)
}

@Test
func timeZoneCoordinatesParseTheDatabaseFormat() {
    let jakarta = TimeZoneCoordinate.parse("-0610+10648")
    #expect(abs(jakarta!.latitude + 6.1667) < 0.001)
    #expect(abs(jakarta!.longitude - 106.8) < 0.001)

    let newYork = TimeZoneCoordinate.parse("+404251-0740023")
    #expect(abs(newYork!.latitude - 40.7142) < 0.001)
    #expect(abs(newYork!.longitude + 74.0064) < 0.001)

    #expect(TimeZoneCoordinate.parse("nonsense") == nil)

    // The database ships with macOS, so the lookup should find a real zone.
    let lookup = TimeZoneCoordinate.coordinate(for: TimeZone(identifier: "Asia/Jakarta")!)
    #expect(abs(lookup!.latitude + 6.1667) < 0.001)
}
