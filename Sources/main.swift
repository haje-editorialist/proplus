// ProPlus — keeps the Mac awake with the lid closed while on power.
// Modes: On (awake whenever on power), Auto (on power + Claude open), Off (normal sleep).
// On battery, normal lid-close sleep is always restored.

import Cocoa
import IOKit
import IOKit.ps
import ServiceManagement

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let claudeBundleID = "com.anthropic.claudefordesktop"
let repoURL = URL(string: "https://github.com/haje-editorialist/proplus")!
let pmset = "/usr/bin/pmset"

enum Mode: String, CaseIterable {
    case on = "On", auto = "Auto", off = "Off"
    var detail: String {
        switch self {
        case .on: return "On — stay awake whenever plugged in"
        case .auto: return "Auto — stay awake when plugged in and Claude is open"
        case .off: return "Off — sleep when the lid closes"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let termSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    private var needsSetup = false
    /// Set when the Mac gets hot with the lid shut; cleared when the lid opens.
    private var overheated = false

    private var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mode"); evaluate() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Re-evaluate on power changes, Claude launching/quitting, wake, and heat changes.
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue().evaluate()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        let refresh: (Notification) -> Void = { [weak self] _ in self?.evaluate() }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main, using: refresh)
        }
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                               object: nil, queue: .main, using: refresh)
        // Fallback poll (also catches the lid closing, which has no notification).
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.evaluate() }

        // Treat `kill` like Quit, so sleep is restored on the way out.
        signal(SIGTERM, SIG_IGN)
        termSignal.setEventHandler { NSApp.terminate(nil) }
        termSignal.resume()

        evaluate()
    }

    func applicationWillTerminate(_ note: Notification) {
        // Never leave the Mac unable to sleep after ProPlus quits.
        setSleepDisabled(false)
    }

    // MARK: - Decision

    private func shouldStayAwake() -> Bool {
        guard onACPower(), !overheated else { return false }
        switch mode {
        case .on: return true
        case .auto: return claudeOpen()
        case .off: return false
        }
    }

    private func evaluate() {
        if !lidClosed() {
            overheated = false
        } else if isHot && !externalDisplayAttached() {
            overheated = true
        }

        let want = shouldStayAwake()
        if want != sleepDisabled() {
            needsSetup = !setSleepDisabled(want)
            // Sleep was just re-enabled: if the lid is already shut, make sure the Mac
            // actually goes to sleep instead of staying awake in a bag.
            if !needsSetup && !want { sleepIfLidClosed() }
        }
        updateIcon()
    }

    private func sleepIfLidClosed() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.sleepDisabled(), self.lidClosed(), !self.externalDisplayAttached() else { return }
            self.run(pmset, "sleepnow")
        }
    }

    // MARK: - System state

    private func onACPower() -> Bool {
        IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String? == kIOPMACPowerKey
    }

    private func claudeOpen() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).isEmpty
    }

    private var isHot: Bool {
        ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    private var temperatureLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Very hot"
        @unknown default: return "Unknown"
        }
    }

    /// Reads a boolean from the power management root domain (the same values `ioreg` shows).
    private func powerFlag(_ key: String) -> Bool {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard svc != 0 else { return false }
        defer { IOObjectRelease(svc) }
        return IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool ?? false
    }

    private func lidClosed() -> Bool { powerFlag("AppleClamshellState") }
    private func sleepDisabled() -> Bool { powerFlag("SleepDisabled") }

    private func externalDisplayAttached() -> Bool {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    // MARK: - pmset

    @discardableResult
    private func run(_ path: String, _ args: String...) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Allowed without a password by /etc/sudoers.d/proplus (installed by setup.sh).
    @discardableResult
    private func setSleepDisabled(_ disabled: Bool) -> Bool {
        run("/usr/bin/sudo", "-n", pmset, "-a", "disablesleep", disabled ? "1" : "0")
    }

    // MARK: - UI

    private func updateIcon() {
        let symbol = needsSetup ? "exclamationmark.triangle"
            : overheated ? "thermometer.high"
            : sleepDisabled() ? "cup.and.saucer.fill" : "moon.zzz"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "ProPlus")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.toolTip = "ProPlus — \(mode.rawValue)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        evaluate()
        menu.removeAllItems()

        let awake = sleepDisabled()
        let status = lidClosed()
            ? (awake ? "Lid closed, staying awake" : "Lid closed, sleep allowed")
            : (awake ? "Will stay awake when the lid closes" : "Will sleep when the lid closes")
        menu.addItem(info(status))
        menu.addItem(info("\(onACPower() ? "Plugged in" : "On battery") · \(claudeOpen() ? "Claude open" : "Claude closed")"))
        menu.addItem(info("Laptop Temperature: \(temperatureLabel)"))
        if overheated { menu.addItem(info("Too hot with lid closed, letting it sleep")) }
        if needsSetup { menu.addItem(info("Setup needed: run setup.sh once")) }

        menu.addItem(.separator())
        for m in Mode.allCases {
            let item = action(m.detail, #selector(pick(_:)))
            item.representedObject = m
            item.state = m == mode ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let login = action("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(action("About ProPlus (\(appVersion))", #selector(openAbout)))
        menu.addItem(NSMenuItem(title: "Quit ProPlus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pick(_ sender: NSMenuItem) {
        if let m = sender.representedObject as? Mode { mode = m }
    }

    @objc private func openAbout() {
        NSWorkspace.shared.open(repoURL)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
