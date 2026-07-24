import Foundation
import SleepyCore

private final class SleepyHelper: NSObject, SleepyHelperProtocol {
    func ping(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func setSleep(
        minutes: NSNumber,
        scope: NSString,
        withReply reply: @escaping (Bool, NSString?) -> Void
    ) {
        guard let arguments = SleepRequestValidator.arguments(
            minutes: minutes.intValue,
            scope: scope as String
        ) else {
            reply(false, "Sleepy rejected an invalid sleep request.")
            return
        }

        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            reply(false, error.localizedDescription as NSString)
            return
        }

        guard process.terminationStatus == 0 else {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            reply(false, (message ?? "pmset exited with an error.") as NSString)
            return
        }

        reply(true, nil)
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let helper = SleepyHelper()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.setCodeSigningRequirement(#"identifier "com.erbin.sleepy""#)
        newConnection.exportedInterface = NSXPCInterface(with: SleepyHelperProtocol.self)
        newConnection.exportedObject = helper
        newConnection.resume()
        return true
    }
}

private let delegate = ListenerDelegate()
private let listener = NSXPCListener(machServiceName: SleepyHelperConstants.label)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
