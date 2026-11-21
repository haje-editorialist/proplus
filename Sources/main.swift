// ProPlus — keeps the Mac awake with the lid closed while on power.
// Modes: On (awake whenever on power), Auto (on power + Claude open), Off (normal sleep).
// On battery, normal lid-close sleep is always restored.

import Cocoa
import IOKit
import IOKit.ps
import ServiceManagement

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let claudeBundleID = "com.anthropic.claudefordesktop"
let pmsetPath = "/usr/bin/pmset"

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
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private var lastApplied: Bool?
    private var setupError: String?

    private var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mode"); evaluate() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // React immediately to power changes and Claude launching/quitting.
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue().evaluate()
        }, ctx)?.takeRetainedValue() {
            powerSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.evaluate() }
        }
        // Fallback poll.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.evaluate() }

        lastApplied = currentSleepDisabled()
        evaluate()
    }

    func applicationWillTerminate(_ note: Notification) {
        // Never leave the Mac unable to sleep after ProPlus quits.
        _ = applyPmset(disable: false)
    }

    // MARK: - State

    private func onACPower() -> Bool {
        guard let type = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String? else { return false }
        return type == kIOPMACPowerKey
    }

    private func claudeOpen() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).isEmpty
    }

    private func shouldStayAwake() -> Bool {
        guard onACPower() else { return false }
        switch mode {
        case .on: return true
        case .auto: return claudeOpen()
        case .off: return false
        }
    }

    @objc func evaluate() {
        let want = shouldStayAwake()
        if want != lastApplied {
            if applyPmset(disable: want) {
                let wasAwake = lastApplied == true
                lastApplied = want
                setupError = nil
                if wasAwake && !want { sleepIfLidClosed() }
            } else {
                setupError = "Setup needed: run setup.sh once"
                lastApplied = currentSleepDisabled()
            }
        }
        updateIcon()
    }

    // MARK: - Lid

    private func lidClosed() -> Bool {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard svc != 0 else { return false }
        defer { IOObjectRelease(svc) }
        let v = IORegistryEntryCreateCFProperty(svc, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
        return v ?? false
    }

    private func externalDisplayAttached() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    /// Sleep was just re-enabled. If the lid is already shut (and there's no external
    /// display keeping the Mac in clamshell mode), make sure it actually goes to sleep
    /// instead of staying awake in a bag.
    private func sleepIfLidClosed() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.lastApplied == false, self.lidClosed(), !self.externalDisplayAttached() else { return }
            _ = self.run(pmsetPath, ["sleepnow"])
        }
    }

    // MARK: - pmset

    private func run(_ path: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
    }

    private func applyPmset(disable: Bool) -> Bool {
        // Allowed without a password by /etc/sudoers.d/proplus (installed by setup.sh).
        run("/usr/bin/sudo", ["-n", pmsetPath, "-a", "disablesleep", disable ? "1" : "0"]).0 == 0
    }

    private func currentSleepDisabled() -> Bool {
        let out = run(pmsetPath, ["-g"]).1
        for line in out.split(separator: "\n") where line.contains("SleepDisabled") {
            return line.split(separator: " ").last == "1"
        }
        return false
    }

    // MARK: - UI

    private func updateIcon() {
        let awake = lastApplied == true
        let symbol = setupError != nil ? "exclamationmark.triangle" : (awake ? "cup.and.saucer.fill" : "moon.zzz")
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "ProPlus")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.toolTip = "ProPlus — \(mode.rawValue)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let awake = lastApplied == true
        let power = onACPower() ? "Plugged in" : "On battery"
        let claude = claudeOpen() ? "Claude open" : "Claude closed"
        menu.addItem(disabled(awake ? "Awake with lid closed" : "Normal sleep"))
        menu.addItem(disabled("\(power) · \(claude)"))
        if let setupError { menu.addItem(disabled(setupError)) }
        menu.addItem(.separator())
        for m in Mode.allCases {
            let item = NSMenuItem(title: m.detail, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.rawValue
            item.state = m == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(disabled("ProPlus \(appVersion)"))
        let quit = NSMenuItem(title: "Quit ProPlus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    @objc private func pick(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = Mode(rawValue: raw) { mode = m }
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
