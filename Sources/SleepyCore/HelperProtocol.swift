import Foundation

public enum SleepyHelperConstants {
    public static let label = "com.erbin.sleepy.helper"
    public static let executableName = "com.erbin.sleepy.helper"
    public static let plistName = "com.erbin.sleepy.helper.plist"
}

public enum SleepPresets {
    public static let values = [1, 5, 10, 15, 30, 60, 120, 0]
}

public enum SleepRequestValidator {
    public static func arguments(minutes: Int, scope: String) -> [String]? {
        guard SleepPresets.values.contains(minutes), let powerScope = PowerScope(rawValue: scope) else {
            return nil
        }
        return [powerScope.pmsetFlag, "sleep", String(minutes)]
    }
}

@objc public protocol SleepyHelperProtocol: AnyObject {
    func ping(withReply reply: @escaping (Bool) -> Void)
    func setSleep(
        minutes: NSNumber,
        scope: NSString,
        withReply reply: @escaping (Bool, NSString?) -> Void
    )
}
