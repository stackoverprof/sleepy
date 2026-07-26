import Foundation
import SleepyCore

enum PowerSettingsError: LocalizedError {
    case commandFailed(String)
    case helperFilesMissing
    case helperUnavailable
    case helperRejected(String)
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            "Could not read the Mac sleep settings. \(message)"
        case .helperFilesMissing:
            "The privileged helper is missing from this copy of Sleepy. Rebuild the app and try again."
        case .helperUnavailable:
            "The one-time permission helper did not become available."
        case .helperRejected(let message):
            "Could not change the Mac sleep setting. \(message)"
        case .setupFailed(let message):
            "Could not enable one-time permission. \(message)"
        }
    }
}

final class PowerSettingsService {
    func read() throws -> PowerSettingsSnapshot {
        let custom = try run("/usr/bin/pmset", arguments: ["-g", "custom"])
        let battery = try run("/usr/bin/pmset", arguments: ["-g", "batt"])
        return PowerSettingsParser.parse(customSettings: custom, batteryStatus: battery)
    }

    func isHelperAvailable(timeout: TimeInterval = 0.6) -> Bool {
        let connection = makeConnection()
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var didReply = false
        var available = false

        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            lock.lock()
            let shouldSignal = !didReply
            didReply = true
            lock.unlock()
            if shouldSignal {
                semaphore.signal()
            }
        } as? SleepyHelperProtocol

        connection.resume()
        proxy?.version { version in
            lock.lock()
            let shouldSignal = !didReply
            available = version == SleepyHelperConstants.protocolVersion
            didReply = true
            lock.unlock()
            if shouldSignal {
                semaphore.signal()
            }
        }

        let receivedReply = semaphore.wait(timeout: .now() + timeout) == .success
        connection.invalidate()
        return receivedReply && available
    }

    func installHelper() throws {
        let bundleURL = Bundle.main.bundleURL
        let sourceHelper = bundleURL
            .appendingPathComponent("Contents/Library/PrivilegedHelperTools")
            .appendingPathComponent(SleepyHelperConstants.executableName)
        let sourcePlist = bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons")
            .appendingPathComponent(SleepyHelperConstants.plistName)

        guard
            FileManager.default.isExecutableFile(atPath: sourceHelper.path),
            FileManager.default.fileExists(atPath: sourcePlist.path)
        else {
            throw PowerSettingsError.helperFilesMissing
        }

        let destinationHelper = "/Library/PrivilegedHelperTools/\(SleepyHelperConstants.executableName)"
        let destinationPlist = "/Library/LaunchDaemons/\(SleepyHelperConstants.plistName)"

        let commands = [
            "(/bin/launchctl bootout system/\(SleepyHelperConstants.label) >/dev/null 2>&1 || true)",
            "/usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools",
            "/usr/bin/install -o root -g wheel -m 755 \(shellQuote(sourceHelper.path)) \(shellQuote(destinationHelper))",
            "/usr/bin/install -o root -g wheel -m 644 \(shellQuote(sourcePlist.path)) \(shellQuote(destinationPlist))",
            "/bin/launchctl bootstrap system \(shellQuote(destinationPlist))"
        ]
        let command = commands.joined(separator: " && ")
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escapedCommand)\" with administrator privileges"

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: appleScript) else {
            throw PowerSettingsError.setupFailed("The authorization request could not be created.")
        }

        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "macOS rejected the request."
            throw PowerSettingsError.setupFailed(message)
        }

        for _ in 0..<8 {
            if isHelperAvailable(timeout: 0.5) {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        throw PowerSettingsError.helperUnavailable
    }

    func setSleep(minutes: Int, scope: PowerScope) throws {
        if !isHelperAvailable() {
            try installHelper()
        }

        let connection = makeConnection()
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<Void, Error>?

        let finish: (Result<Void, Error>) -> Void = { newResult in
            lock.lock()
            guard result == nil else {
                lock.unlock()
                return
            }
            result = newResult
            lock.unlock()
            semaphore.signal()
        }

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            finish(.failure(PowerSettingsError.helperRejected(error.localizedDescription)))
        } as? SleepyHelperProtocol

        connection.resume()
        proxy?.setSleep(
            minutes: NSNumber(value: minutes),
            scope: scope.rawValue as NSString
        ) { success, message in
            if success {
                finish(.success(()))
            } else {
                finish(.failure(PowerSettingsError.helperRejected(
                    message as String? ?? "The helper rejected the request."
                )))
            }
        }

        guard proxy != nil else {
            connection.invalidate()
            throw PowerSettingsError.helperUnavailable
        }

        guard semaphore.wait(timeout: .now() + 5) == .success else {
            connection.invalidate()
            throw PowerSettingsError.helperUnavailable
        }

        connection.invalidate()
        try result?.get()
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: SleepyHelperConstants.label,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: SleepyHelperProtocol.self)
        return connection
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PowerSettingsError.commandFailed(error.localizedDescription)
        }

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PowerSettingsError.commandFailed(message ?? "pmset exited with an error.")
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}
