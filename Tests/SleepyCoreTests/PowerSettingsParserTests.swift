import Testing
@testable import SleepyCore

@Test
func parsesBatteryAndAdapterSleepValues() {
    let settings = """
    Battery Power:
     lidwake              1
     displaysleep         15
     sleep                1
    AC Power:
     displaysleep         60
     sleep                1
    """

    let result = PowerSettingsParser.parse(
        customSettings: settings,
        batteryStatus: "Now drawing from 'AC Power'"
    )

    #expect(result.batterySleepMinutes == 15)
    #expect(result.adapterSleepMinutes == 60)
    #expect(result.activeSource == .adapter)
    #expect(result.activeSleepMinutes == 60)
}

@Test
func allScopeRequiresMatchingValues() {
    let matching = PowerSettingsSnapshot(
        batterySleepMinutes: 30,
        adapterSleepMinutes: 30,
        activeSource: .battery
    )
    let different = PowerSettingsSnapshot(
        batterySleepMinutes: 15,
        adapterSleepMinutes: 30,
        activeSource: .battery
    )

    #expect(matching.value(for: .all) == 30)
    #expect(different.value(for: .all) == nil)

    let adapterOnly = PowerSettingsSnapshot(
        batterySleepMinutes: nil,
        adapterSleepMinutes: 15,
        activeSource: .adapter
    )
    #expect(adapterOnly.value(for: .all) == 15)
}

@Test
func formatsLabels() {
    #expect(PowerSettingsParser.shortLabel(minutes: 0) == "Never")
    #expect(PowerSettingsParser.shortLabel(minutes: 15) == "15m")
    #expect(PowerSettingsParser.shortLabel(minutes: 120) == "2h")
    #expect(PowerSettingsParser.menuLabel(minutes: 60) == "1 Hour")
}

@Test
func validatesOnlySupportedHelperRequests() {
    #expect(
        SleepRequestValidator.arguments(minutes: 30, scope: PowerScope.all.rawValue)
            == ["-a", "displaysleep", "30", "sleep", "30"]
    )
    #expect(
        SleepRequestValidator.arguments(minutes: 120, scope: PowerScope.battery.rawValue)
            == ["-b", "displaysleep", "120", "sleep", "120"]
    )
    #expect(SleepRequestValidator.arguments(minutes: 31, scope: PowerScope.all.rawValue) == nil)
    #expect(SleepRequestValidator.arguments(minutes: 30, scope: "something-else") == nil)
}
