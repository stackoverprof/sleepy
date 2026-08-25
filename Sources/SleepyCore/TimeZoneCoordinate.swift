import Foundation

/// The reference coordinate the system time zone database keeps for every
/// zone. It is a city, not a fix, but it puts prayer times within a couple of
/// minutes without asking anyone for permission.
public enum TimeZoneCoordinate {
    public static let databasePath = "/usr/share/zoneinfo/zone.tab"

    public static func coordinate(
        for timeZone: TimeZone = .current,
        path: String = databasePath
    ) -> Coordinate? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        for line in contents.split(separator: "\n") {
            guard !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, fields[2] == timeZone.identifier else { continue }
            return parse(String(fields[1]))
        }

        return nil
    }

    /// Reads an ISO 6709 coordinate as zone.tab writes it, either
    /// `+DDMM+DDDMM` or `+DDMMSS+DDDMMSS`.
    public static func parse(_ text: String) -> Coordinate? {
        let characters = Array(text)
        guard characters.count >= 9 else { return nil }
        guard let split = characters.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else {
            return nil
        }

        guard
            let latitude = degrees(String(characters[..<split]), degreeDigits: 2),
            let longitude = degrees(String(characters[split...]), degreeDigits: 3)
        else {
            return nil
        }

        return Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func degrees(_ text: String, degreeDigits: Int) -> Double? {
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let digits = Array(text.dropFirst())
        guard digits.count >= degreeDigits + 2, digits.allSatisfy(\.isNumber) else { return nil }

        func number(_ range: Range<Int>) -> Double {
            Double(String(digits[range])) ?? 0
        }

        let whole = number(0..<degreeDigits)
        let minutes = number(degreeDigits..<(degreeDigits + 2))
        let seconds = digits.count >= degreeDigits + 4
            ? number((degreeDigits + 2)..<(degreeDigits + 4))
            : 0

        return (sign == "-" ? -1 : 1) * (whole + minutes / 60 + seconds / 3_600)
    }
}
