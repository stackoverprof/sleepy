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
    private var mapView: DayNightMapView!
    private let location = LocationProvider()
    private let hotKey = GlobalHotKey()
    private var shortcutItems: [MenuShortcut: NSMenuItem] = [:]
    private var isMenuOpen = false
    private var mapItem: NSMenuItem!
    private var menu: NSMenu!
    private var lastToggle = 0.0

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

        location.onChange = { [weak self] in
            self?.mapView?.place = self?.location.coordinate
        }
        location.start()
        applyShortcut(MenuShortcut.current)
    }

    func menuWillOpen(_ menu: NSMenu) {
        DebugLog.write("menuWillOpen")
        isMenuOpen = true
        mapView?.refresh()
        refreshSettings(showErrors: false)
        updatePermissionState()
        updateLaunchAtLoginState()
    }

    func menuDidClose(_ menu: NSMenu) {
        DebugLog.write("menuDidClose")
        isMenuOpen = false
        statusItem?.button?.highlight(false)
    }

    @objc private func statusItemClicked() {
        DebugLog.write("statusItemClicked, isMenuOpen=\(isMenuOpen)")
        toggleMenu(pressedWhileOpen: isMenuOpen)
    }

    /// Opens the menu from the shortcut, or closes it if it is already down.
    ///
    /// Whether the menu was down is read now, while the key is still under the
    /// finger, and acted on next time round the loop: showing a menu means
    /// entering a modal tracking loop, which is no place to leave a Carbon
    /// event half dispatched. A press that arrived over an open menu can then
    /// only ever close it, however late the loop gets to it.
    ///
    /// A press can also reach here twice, from the hot key and from the menu's
    /// own key equivalent, so anything landing on the heels of the last one is
    /// taken to be the same press arriving by the other road.
    private func handleShortcut() {
        let wasOpen = isMenuOpen
        DebugLog.write("hotKey fired, isMenuOpen=\(wasOpen)")
        toggleMenu(pressedWhileOpen: wasOpen)
    }

    private func toggleMenu(pressedWhileOpen: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.claimToggle() else {
                DebugLog.write("  ignored, too soon after the last one")
                return
            }

            if pressedWhileOpen || self.isMenuOpen {
                DebugLog.write("  closing")
                self.menu.cancelTracking()
            } else {
                DebugLog.write("  opening")
                self.showMenu()
            }
        }
    }

    /// Shows the menu under the status item. Sleepy pops it up itself rather
    /// than handing it to the status item, so opening from the keyboard and
    /// opening from a click land in the same place.
    private func showMenu() {
        guard let button = statusItem?.button else { return }

        // A menu the status item shows for us picks up the menu bar's
        // appearance. One we pop up ourselves does not, and comes out in light
        // dress on a dark Mac, so tell it what to wear.
        menu.appearance = NSApp.effectiveAppearance

        button.highlight(true)
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.maxY + 5),
            in: button
        )
        DebugLog.write("  popUp returned")
    }

    @objc private func closeMenu() {
        DebugLog.write("map item key equivalent fired")
        guard claimToggle() else {
            DebugLog.write("  ignored, too soon after the last one")
            return
        }
        menu.cancelTracking()
    }

    private func claimToggle() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastToggle > 0.25 else { return false }
        lastToggle = now
        return true
    }

    private func applyShortcut(_ shortcut: MenuShortcut) {
        MenuShortcut.current = shortcut
        hotKey.unregister()

        mapItem?.keyEquivalent = shortcut.keyEquivalent
        mapItem?.keyEquivalentModifierMask = shortcut.modifierFlags

        if shortcut != .off {
            let registered = hotKey.register(shortcut) { [weak self] in
                self?.handleShortcut()
            }
            DebugLog.write("shortcut \(shortcut.displayName) registered=\(registered)")
            if !registered {
                shortcutItems[shortcut]?.toolTip = "Another app is already using \(shortcut.displayName)"
            }
        }

        for (candidate, item) in shortcutItems {
            item.state = candidate == shortcut ? .on : .off
        }
    }

    @objc private func selectShortcut(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let shortcut = MenuShortcut(rawValue: raw)
        else {
            return
        }
        applyShortcut(shortcut)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "moon.zzz.fill",
                accessibilityDescription: "Sleepy"
            )
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.title = "?"
            button.toolTip = "Sleepy: Mac sleep timer"
        }

        let menu = NSMenu()
        menu.delegate = self

        mapView = DayNightMapView(
            frame: NSRect(origin: .zero, size: DayNightMapView.preferredSize)
        )
        mapView.place = location.coordinate
        // The map item carries the shortcut as a key equivalent as well. It
        // draws its own view, so nothing of the shortcut shows, and it gives
        // the menu a way to close itself on the same keys that opened it.
        mapItem = NSMenuItem()
        mapItem.view = mapView
        mapItem.target = self
        mapItem.action = #selector(closeMenu)
        menu.addItem(mapItem)

        menu.addItem(.separator())

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

        let shortcutMenu = NSMenu()
        for shortcut in MenuShortcut.allCases {
            let item = NSMenuItem(
                title: shortcut.displayName,
                action: #selector(selectShortcut(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = shortcut.rawValue
            shortcutItems[shortcut] = item
            shortcutMenu.addItem(item)
        }

        let shortcutRoot = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        shortcutRoot.submenu = shortcutMenu
        menu.addItem(shortcutRoot)

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

        self.menu = menu
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        updateMenuState()
        updatePermissionState()
        updateLaunchAtLoginState()
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
