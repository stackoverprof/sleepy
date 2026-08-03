import AppKit
import ServiceManagement
import SleepyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let service = PowerSettingsService()
    private let presets = SleepPresets.values
    private let scopeDefaultsKey = "powerScope"

    private var statusItem: NSStatusItem!
    private var snapshot: PowerSettingsSnapshot?
    private var presetItems: [Int: NSMenuItem] = [:]
    private var scopeItems: [PowerScope: NSMenuItem] = [:]
    private var permissionItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!

    private var selectedScope: PowerScope {
        get {
            guard
                let rawValue = UserDefaults.standard.string(forKey: scopeDefaultsKey),
                let scope = PowerScope(rawValue: rawValue)
            else {
                return .all
            }
            return scope
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: scopeDefaultsKey)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refreshSettings(showErrors: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshSettings(showErrors: false)
        updatePermissionState()
        updateLaunchAtLoginState()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = coffeeBeanImage()
            button.imagePosition = .imageLeading
            button.title = "?"
            button.toolTip = "Sleepy: Mac sleep timer"
        }

        let menu = NSMenu()
        menu.delegate = self

        let heading = NSMenuItem(title: "Sleep after", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        for minutes in presets {
            let item = NSMenuItem(
                title: PowerSettingsParser.menuLabel(minutes: minutes),
                action: #selector(selectPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: minutes)
            presetItems[minutes] = item
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let scopeMenu = NSMenu()
        for scope in PowerScope.allCases {
            let item = NSMenuItem(
                title: scope.displayName,
                action: #selector(selectScope(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = scope.rawValue
            scopeItems[scope] = item
            scopeMenu.addItem(item)
        }

        let scopeRoot = NSMenuItem(title: "Apply to", action: nil, keyEquivalent: "")
        scopeRoot.submenu = scopeMenu
        menu.addItem(scopeRoot)

        menu.addItem(.separator())

        permissionItem = NSMenuItem(
            title: "Enable One-Time Permission…",
            action: #selector(enableOneTimePermission),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        let refreshItem = NSMenuItem(
            title: "Refresh",
            action: #selector(refreshMenu),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        let quitItem = NSMenuItem(
            title: "Quit Sleepy",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuState()
        updatePermissionState()
        updateLaunchAtLoginState()
    }

    private func coffeeBeanImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()

            let bean = NSBezierPath()
            bean.move(to: NSPoint(x: 9.5, y: 1.5))
            bean.curve(
                to: NSPoint(x: 15.4, y: 8.4),
                controlPoint1: NSPoint(x: 13.3, y: 1.5),
                controlPoint2: NSPoint(x: 15.8, y: 4.7)
            )
            bean.curve(
                to: NSPoint(x: 8.6, y: 16.5),
                controlPoint1: NSPoint(x: 15.0, y: 12.5),
                controlPoint2: NSPoint(x: 12.3, y: 16.3)
            )
            bean.curve(
                to: NSPoint(x: 2.6, y: 9.7),
                controlPoint1: NSPoint(x: 5.1, y: 16.6),
                controlPoint2: NSPoint(x: 2.4, y: 13.6)
            )
            bean.curve(
                to: NSPoint(x: 9.5, y: 1.5),
                controlPoint1: NSPoint(x: 2.8, y: 6.0),
                controlPoint2: NSPoint(x: 5.6, y: 1.6)
            )
            bean.close()
            bean.fill()

            NSGraphicsContext.current?.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear

            let seam = NSBezierPath()
            seam.move(to: NSPoint(x: 11.9, y: 2.4))
            seam.curve(
                to: NSPoint(x: 6.0, y: 15.2),
                controlPoint1: NSPoint(x: 8.7, y: 5.2),
                controlPoint2: NSPoint(x: 10.8, y: 8.7)
            )
            seam.lineWidth = 1.5
            seam.lineCapStyle = .round
            seam.stroke()

            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = "Sleepy coffee bean"
        return image
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let minutes = (sender.representedObject as? NSNumber)?.intValue else {
            return
        }

        do {
            try service.setSleep(minutes: minutes, scope: selectedScope)
            refreshSettings(showErrors: true)
        } catch {
            show(error)
        }
    }

    @objc private func selectScope(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let scope = PowerScope(rawValue: rawValue)
        else {
            return
        }

        selectedScope = scope
        updateMenuState()
    }

    @objc private func refreshMenu() {
        refreshSettings(showErrors: true)
    }

    @objc private func enableOneTimePermission() {
        do {
            try service.installHelper()
            updatePermissionState()
        } catch {
            show(error)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            default:
                try SMAppService.mainApp.register()
            }
            updateLaunchAtLoginState()
        } catch {
            show(error)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func refreshSettings(showErrors: Bool) {
        do {
            snapshot = try service.read()
            updateMenuState()
        } catch {
            if showErrors {
                show(error)
            }
        }
    }

    private func updateMenuState() {
        let currentValue = snapshot?.value(for: selectedScope)

        for (minutes, item) in presetItems {
            item.state = currentValue == minutes ? .on : .off
        }

        for (scope, item) in scopeItems {
            item.state = selectedScope == scope ? .on : .off
        }

        if let button = statusItem?.button {
            button.title = PowerSettingsParser.shortLabel(minutes: snapshot?.activeSleepMinutes)
            if let activeSleepMinutes = snapshot?.activeSleepMinutes {
                button.toolTip = "Sleepy: Mac sleeps after \(PowerSettingsParser.menuLabel(minutes: activeSleepMinutes).lowercased())"
            } else {
                button.toolTip = "Sleepy: Mac sleep timer unavailable"
            }
        }
    }

    private func updatePermissionState() {
        let enabled = service.isHelperAvailable()
        permissionItem?.title = enabled
            ? "One-Time Permission Enabled"
            : "Enable One-Time Permission…"
        permissionItem?.state = enabled ? .on : .off
        permissionItem?.isEnabled = !enabled
    }

    private func updateLaunchAtLoginState() {
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func show(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Sleepy"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
