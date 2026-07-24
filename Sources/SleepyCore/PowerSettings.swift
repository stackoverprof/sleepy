import Foundation

public enum PowerScope: String, CaseIterable, Sendable {
    case all
    case battery
    case adapter

    public var pmsetFlag: String {
        switch self {
        case .all: "-a"
        case .battery: "-b"
        case .adapter: "-c"
        }
    }

    public var displayName: String {
        switch self {
        case .all: "Battery and Power Adapter"
        case .battery: "Battery Only"
        case .adapter: "Power Adapter Only"
        }
    }
}

public enum ActivePowerSource: Sendable {
    case battery
    case adapter
}

public struct PowerSettingsSnapshot: Equatable, Sendable {
    public var batterySleepMinutes: Int?
    public var adapterSleepMinutes: Int?
    public var activeSource: ActivePowerSource

    public init(
        batterySleepMinutes: Int?,
        adapterSleepMinutes: Int?,
        activeSource: ActivePowerSource
    ) {
        self.batterySleepMinutes = batterySleepMinutes
        self.adapterSleepMinutes = adapterSleepMinutes
        self.activeSource = activeSource
    }

    public var activeSleepMinutes: Int? {
        switch activeSource {
        case .battery: batterySleepMinutes
        case .adapter: adapterSleepMinutes
        }
    }

    public func value(for scope: PowerScope) -> Int? {
        switch scope {
        case .battery:
            batterySleepMinutes
        case .adapter:
            adapterSleepMinutes
        case .all:
            switch (batterySleepMinutes, adapterSleepMinutes) {
            case let (battery?, adapter?):
                battery == adapter ? battery : nil
            case let (battery?, nil):
                battery
            case let (nil, adapter?):
                adapter
            case (nil, nil):
                nil
            }
        }
    }
}

public enum PowerSettingsParser {
    public static func parse(
        customSettings: String,
        batteryStatus: String
    ) -> PowerSettingsSnapshot {
        enum Section {
            case none
            case battery
            case adapter
        }

        var section = Section.none
        var batterySleep: Int?
        var adapterSleep: Int?

        for rawLine in customSettings.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("Battery Power:") {
                section = .battery
                continue
            }

            if line.hasPrefix("AC Power:") {
                section = .adapter
                continue
            }

            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0] == "sleep", let value = Int(fields[1]) else {
                continue
            }

            switch section {
            case .battery:
                batterySleep = value
            case .adapter:
                adapterSleep = value
            case .none:
                break
            }
        }

        let activeSource: ActivePowerSource =
            batteryStatus.localizedCaseInsensitiveContains("AC Power") ? .adapter : .battery

        return PowerSettingsSnapshot(
            batterySleepMinutes: batterySleep,
            adapterSleepMinutes: adapterSleep,
            activeSource: activeSource
        )
    }

    public static func shortLabel(minutes: Int?) -> String {
        guard let minutes else { return "?" }
        if minutes == 0 { return "Never" }
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }

    public static func menuLabel(minutes: Int) -> String {
        if minutes == 0 { return "Never" }
        if minutes == 60 { return "1 Hour" }
        if minutes > 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60) Hours"
        }
        return "\(minutes) Minutes"
    }
}
