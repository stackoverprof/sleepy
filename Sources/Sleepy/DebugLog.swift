import Foundation

/// Appends a line to ~/Library/Logs/Sleepy.log, but only while
/// `defaults write com.erbin.sleepy debugLog -bool true` is set.
///
/// A menu bar app has nowhere to print, and menu tracking is exactly the kind
/// of thing that has to be watched from outside to be understood.
enum DebugLog {
    private static let isOn = UserDefaults.standard.bool(forKey: "debugLog")

    private static let path: String = {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Sleepy.log")
        return logs.path
    }()

    static func write(_ message: String) {
        guard isOn else { return }

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "HH:mm:ss.SSS"
        let line = "\(stamp.string(from: Date()))  \(message)\n"

        guard let data = line.data(using: .utf8) else { return }

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
