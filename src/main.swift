import Cocoa
import SwiftUI
import IOKit.ps

let pmset = "/usr/bin/pmset"
let batKey = "lowBatteryPercent"
let agentPath = NSHomeDirectory() + "/Library/LaunchAgents/local.lidawake.plist"
let appExe = NSHomeDirectory() + "/Applications/LidAwake.app/Contents/MacOS/LidAwake"

func batteryInfo() -> (percent: Int, onBattery: Bool)? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for ps in list {
        if let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
           let cap = d[kIOPSCurrentCapacityKey] as? Int {
            return (cap, (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue)
        }
    }
    return nil
}
let endKey = "timerEnd", startKey = "timerStart", selKey = "selectedMinutes"

// MARK: - Model (all logic)
final class Model: ObservableObject {
    @Published var active = false { didSet { onChange?() } }
    @Published var endDate: Date? = UserDefaults.standard.object(forKey: endKey) as? Date
    @Published var startDate: Date? = UserDefaults.standard.object(forKey: startKey) as? Date
    @Published var selected: Int = UserDefaults.standard.object(forKey: selKey) as? Int ?? 120 // 0 = indefinite
    @Published var now = Date()
    @Published var error = false
    @Published var lowBattery: Int = UserDefaults.standard.object(forKey: batKey) as? Int ?? 20 // 0 = off
    @Published var launchAtLogin = FileManager.default.fileExists(atPath: agentPath)

    func setLowBattery(_ v: Int) { lowBattery = v; UserDefaults.standard.set(v, forKey: batKey); checkBattery() }
    func checkBattery() {
        guard active, lowBattery > 0, let b = batteryInfo(), b.onBattery, b.percent <= lowBattery else { return }
        stop()
    }
    func setLaunchAtLogin(_ on: Bool) {
        if on {
            let pl = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>Label</key><string>local.lidawake</string><key>ProgramArguments</key><array><string>\(appExe)</string><string>--background</string></array><key>RunAtLoad</key><true/></dict></plist>"
            try? FileManager.default.createDirectory(atPath: (agentPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? pl.write(toFile: agentPath, atomically: true, encoding: .utf8)
        } else { try? FileManager.default.removeItem(atPath: agentPath) }
        launchAtLogin = FileManager.default.fileExists(atPath: agentPath)
    }
    var onChange: (() -> Void)?
    var oneShot: Timer?
    let q = DispatchQueue(label: "lidawake.pmset")

    func readState() -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: pmset); p.arguments = ["-g"]
        let pipe = Pipe(); p.standardOutput = pipe
        do { try p.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").contains { l in
            let t = l.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return t.count >= 2 && t[0] == "SleepDisabled" && t[1] == "1"
        }
    }

    func refresh() {
        q.async { [weak self] in
            guard let self = self else { return }
            let st = self.readState()
            DispatchQueue.main.async {
                self.active = st
                if !st, self.endDate != nil { self.clearTimer() }
                self.now = Date(); self.onChange?()
            }
        }
    }

    func tick() {
        if let e = endDate, e <= Date() {
            if active { setSleepDisabled(false) } else { clearTimer(); refresh() }
        } else { refresh() }
    }

    func setSleepDisabled(_ on: Bool) {
        q.async { [weak self] in
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            p.arguments = ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"]
            p.standardError = Pipe(); p.standardOutput = Pipe()
            var ok = false
            do { try p.run(); p.waitUntilExit(); ok = p.terminationStatus == 0 } catch {}
            DispatchQueue.main.async {
                self?.error = !ok
                if !on || !ok { self?.clearTimer() }
                self?.refresh()
            }
        }
    }

    func schedule(_ d: Date) {
        oneShot?.invalidate()
        oneShot = Timer.scheduledTimer(withTimeInterval: max(0, d.timeIntervalSinceNow), repeats: false) { [weak self] _ in self?.tick() }
    }
    func clearTimer() {
        endDate = nil; startDate = nil; oneShot?.invalidate(); oneShot = nil
        UserDefaults.standard.removeObject(forKey: endKey); UserDefaults.standard.removeObject(forKey: startKey)
    }
    func start() {
        clearTimer()
        if selected > 0 {
            let s = Date(), d = s.addingTimeInterval(Double(selected) * 60)
            startDate = s; endDate = d
            UserDefaults.standard.set(d, forKey: endKey); UserDefaults.standard.set(s, forKey: startKey)
            schedule(d)
        }
        active = true; setSleepDisabled(true)
    }
    func stop() { clearTimer(); active = false; setSleepDisabled(false) }
    func select(_ m: Int) {
        selected = m; UserDefaults.standard.set(m, forKey: selKey)
        if active { start() } // re-arm timer with new duration
    }
    func resumeOnLaunch() {
        if let e = endDate { if e > Date() { schedule(e) } }
    }
}

// MARK: - UI (fixed size so the popover never jumps)
struct PopoverView: View {
    @ObservedObject var m: Model
    func remaining() -> String {
        guard let e = m.endDate else { return "No time limit" }
        let s = max(0, Int(e.timeIntervalSince(m.now)))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
    var progress: Double {
        guard let s = m.startDate, let e = m.endDate else { return 1 }
        return max(0, min(1, e.timeIntervalSince(m.now) / e.timeIntervalSince(s)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(m.active ? Color.orange.opacity(0.2) : Color.primary.opacity(0.08))
                    Image(systemName: m.active ? "cup.and.saucer.fill" : "laptopcomputer")
                        .font(.system(size: 16)).foregroundStyle(m.active ? Color.orange : Color.secondary)
                }.frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.active ? "Staying awake" : "Normal sleep").font(.system(size: 13, weight: .semibold))
                    Text(m.active ? "Runs with the lid closed" : "Lid closed puts Mac to sleep")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { m.active }, set: { $0 ? m.start() : m.stop() }))
                    .toggleStyle(.switch).labelsHidden()
            }

            // Fixed-height status slot: content changes, size doesn't.
            VStack(alignment: .leading, spacing: 6) {
                if m.active {
                    HStack(alignment: .firstTextBaseline) {
                        Text(m.endDate == nil ? "No time limit" : remaining())
                            .font(.system(size: 20, weight: .medium)).monospacedDigit()
                        Spacer()
                        if let e = m.endDate {
                            Text("until \(e.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: m.endDate == nil ? 1 : progress).tint(.orange).opacity(m.endDate == nil ? 0.35 : 1)
                } else {
                    Text("Off").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                    Text("Turn on to keep the Mac running with the lid closed")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

            VStack(alignment: .leading, spacing: 6) {
                Text(m.active ? "Reset timer" : "Turn off automatically after")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { m.selected }, set: { m.select($0) })) {
                    Text("2 h").tag(120); Text("4 h").tag(240); Text("8 h").tag(480); Text("∞").tag(0)
                }.pickerStyle(.segmented).labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch at login", isOn: Binding(get: { m.launchAtLogin }, set: { m.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                HStack {
                    Text("Turn off on battery below")
                    Spacer()
                    Picker("", selection: Binding(get: { m.lowBattery }, set: { m.setLowBattery($0) })) {
                        Text("Never").tag(0); Text("10%").tag(10); Text("20%").tag(20); Text("30%").tag(30)
                    }.labelsHidden().fixedSize()
                }
            }.font(.system(size: 13))

            if m.error {
                Text("Setup missing — run install.sh once.").font(.system(size: 11)).foregroundStyle(.red)
            }
            Divider()
            HStack {
                Text("Avoid heavy loads in a bag (heat).").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.link).font(.system(size: 12))
            }
        }
        .padding(14).frame(width: 300)
        .animation(.easeInOut(duration: 0.18), value: m.active)
    }
}

// MARK: - App
final class App: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let m = Model()
    let pop = NSPopover()
    var secTimer: Timer?, poll: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        pop.behavior = .transient
        pop.delegate = self
        let host = NSHostingController(rootView: PopoverView(m: m))
        host.sizingOptions = [.preferredContentSize]
        pop.animates = true
        pop.contentViewController = host
        item.button?.target = self; item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageLeading
        m.onChange = { [weak self] in self?.render() }
        m.refresh(); m.resumeOnLaunch()
        // Manual launch (Launchpad/Finder) shows the panel; login launch passes --background.
        if !CommandLine.arguments.contains("--background") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showPopover() }
        }
        // Event-driven battery watch: no polling, fires only when power state changes.
        let ctx = Unmanaged.passUnretained(m).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ c in
            Unmanaged<Model>.fromOpaque(c!).takeUnretainedValue().checkBattery()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        poll = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.m.tick() }
        poll?.tolerance = 10
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.m.tick() }
    }

    @objc func toggle() { pop.isShown ? pop.performClose(nil) : showPopover() }
    func showPopover() {
        guard let b = item.button, !pop.isShown else { return }
        m.refresh()
        NSApp.activate(ignoringOtherApps: true)
        pop.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKey()
    }
    // Opening the app again (Launchpad/Spotlight) while it's running shows the panel.
    func applicationShouldHandleReopen(_ a: NSApplication, hasVisibleWindows f: Bool) -> Bool { showPopover(); return true }
    func popoverDidShow(_ n: Notification) {
        secTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.m.now = Date() }
    }
    func popoverDidClose(_ n: Notification) { secTimer?.invalidate(); secTimer = nil }

    func render() {
        let img = NSImage(systemSymbolName: m.active ? "cup.and.saucer.fill" : "laptopcomputer",
                          accessibilityDescription: m.active ? "Lid-closed awake ON" : "Normal sleep")
        img?.isTemplate = true
        item.button?.image = img
        if m.active, let e = m.endDate, e > Date() {
            let mins = Int(ceil(e.timeIntervalSinceNow / 60))
            item.button?.title = " " + (mins >= 60 ? "\(mins / 60)h\(String(format: "%02d", mins % 60))" : "\(mins)m")
        } else { item.button?.title = m.active ? " ∞" : "" }
    }

    func applicationWillTerminate(_ n: Notification) {
        if m.active { // don't leave the Mac stuck awake after quitting
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            p.arguments = ["-n", pmset, "-a", "disablesleep", "0"]; try? p.run(); p.waitUntilExit()
        }
        m.clearTimer()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let d = App(); app.delegate = d
app.run()
