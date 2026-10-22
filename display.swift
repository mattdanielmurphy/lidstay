// Display re-sync: a TV behind a USB-C hub that comes back on showing
// "no signal" picks the Mac up again once the display is slept and woken
// (the same thing opening the lid does). The hub hides the TV's power
// state from macOS, so re-syncs are aimed at the moments it's likely stuck.
//
// Automatic triggers (all only with the lid shut):
//   disconnect   the display vanished (adapters that report it): retry every
//                retrySeconds until it's back, the lid opens, or 30 minutes pass
//   first touch  first keyboard/trackpad input after idleMinutes of none; reads
//                the system idle timer, so it works at the lock screen too
//   after wake   once, a few seconds after the Mac wakes from sleep
// Backups: the hotkey (not at the lock screen) and scheduled times.
//
// Shared by tvresync and lidstay's menu bar icon. Settings live in
// <configDir>/display.json and can be edited from the menu or by hand:
//   hotkey        "ctrl+opt+r" (ctrl/opt/cmd/shift + a letter, digit or f1-f12)
//   approved      displays re-syncs may touch (vendor + model); none = any external display
//   schedule      [{"time": "19:00", "days": "daily" | "weekdays" | "weekends"}]
//   onDisconnect, onFirstTouch, onWake   switch each trigger (default true)
//   idleMinutes   idle time before a touch counts as "first touch" (10)
//   retrySeconds  gap between re-syncs while the display is missing (10)
//   sleepSeconds  how long the display stays off during a re-sync (4)
import AppKit
import Carbon.HIToolbox
import IOKit
import IOKit.pwr_mgt

struct DisplayID: Codable, Equatable {
    var name: String
    var vendor: UInt32
    var model: UInt32
    func same(_ o: DisplayID) -> Bool { vendor == o.vendor && model == o.model }
}

struct ScheduledResync: Codable, Equatable {
    var time: String
    var days: String
    var label: String { "\(time) \(days)" }
}

struct DisplayConfig: Codable {
    var hotkey = "ctrl+opt+r"
    var approved: [DisplayID] = []
    var schedule: [ScheduledResync] = []
    var onDisconnect = true
    var onFirstTouch = true
    var onWake = true
    var idleMinutes = 10.0
    var retrySeconds = 10.0
    var sleepSeconds = 4.0

    init() {}
    init(from d: Decoder) throws {  // missing keys keep their defaults
        let c = try d.container(keyedBy: CodingKeys.self)
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? hotkey
        approved = try c.decodeIfPresent([DisplayID].self, forKey: .approved) ?? []
        schedule = try c.decodeIfPresent([ScheduledResync].self, forKey: .schedule) ?? []
        onDisconnect = try c.decodeIfPresent(Bool.self, forKey: .onDisconnect) ?? onDisconnect
        onFirstTouch = try c.decodeIfPresent(Bool.self, forKey: .onFirstTouch) ?? onFirstTouch
        onWake = try c.decodeIfPresent(Bool.self, forKey: .onWake) ?? onWake
        idleMinutes = try c.decodeIfPresent(Double.self, forKey: .idleMinutes) ?? idleMinutes
        retrySeconds = try c.decodeIfPresent(Double.self, forKey: .retrySeconds) ?? retrySeconds
        sleepSeconds = try c.decodeIfPresent(Double.self, forKey: .sleepSeconds) ?? sleepSeconds
    }
}

func displayLog(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("\(f.string(from: Date())) \(s)"); fflush(stdout)
}

// External displays macOS has online (with the lid shut that's all of them)
func externalDisplays() -> [DisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
    CGGetOnlineDisplayList(16, &ids, &n)
    return ids.prefix(Int(n)).filter { CGDisplayIsBuiltin($0) == 0 }.map { id in
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return DisplayID(name: screen?.localizedName ?? "Display \(id)",
                         vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id))
    }
}

func lidClosed() -> Bool {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    defer { IOObjectRelease(root) }
    let v = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
    return (v?.takeRetainedValue() as? Bool) ?? false
}

// Seconds since the last keyboard/trackpad input, system-wide (keeps counting at the lock screen)
func idleSeconds() -> Double {
    let hid = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    defer { IOObjectRelease(hid) }
    let v = IORegistryEntryCreateCFProperty(hid, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)
    return ((v?.takeRetainedValue() as? NSNumber)?.doubleValue ?? 0) / 1_000_000_000
}

// Sleep the display, then wake it with a user-activity assertion.
// Blocking version for the command line.
func resyncDisplayNow(sleepSeconds: Double) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["displaysleepnow"]
    try? p.run(); p.waitUntilExit()
    Thread.sleep(forTimeInterval: sleepSeconds)
    var a: IOPMAssertionID = 0
    IOPMAssertionDeclareUserActivity("display re-sync" as CFString, kIOPMUserActiveLocal, &a)
    Thread.sleep(forTimeInterval: 1)
    IOPMAssertionRelease(a)
}

private let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
    "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
    "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
    "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
    "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
    "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
    "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
    "9": kVK_ANSI_9, "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
    "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11,
    "f12": kVK_F12,
]

// "ctrl+opt+r" -> (key code, Carbon modifiers, "⌃⌥R")
func parseHotkey(_ s: String) -> (key: UInt32, mods: UInt32, symbol: String)? {
    var mods = 0, key: Int?, keyName = ""
    var symbol = ""
    for part in s.lowercased().split(separator: "+").map(String.init) {
        switch part {
        case "ctrl", "control": mods |= controlKey
        case "opt", "option", "alt": mods |= optionKey
        case "cmd", "command": mods |= cmdKey
        case "shift": mods |= shiftKey
        default: key = keyCodes[part]; keyName = part.uppercased()
        }
    }
    guard let k = key, mods != 0 else { return nil }
    if mods & controlKey != 0 { symbol += "⌃" }
    if mods & optionKey != 0 { symbol += "⌥" }
    if mods & shiftKey != 0 { symbol += "⇧" }
    if mods & cmdKey != 0 { symbol += "⌘" }
    return (UInt32(k), UInt32(mods), symbol + keyName)
}

private weak var hotkeyTarget: DisplayResync?

class DisplayResync: NSObject {
    let configURL: URL
    private(set) var config = DisplayConfig()
    private var hotkeyRef: EventHotKeyRef?
    private var registeredHotkey = ""
    private var busy = false
    private var firedSlots = Set<String>()
    private var lastResync = Date.distantPast
    private var prevIdle = 0.0
    private var lastSeen: DisplayID?      // display that was attached, for the disconnect trigger
    private var missingSince: Date?       // set while re-syncing for a missing display
    private var armed = false             // lid shut + idle long enough: next touch re-syncs
    private var lastShownName: String? = "?"
    private var activity: NSObjectProtocol?

    init(configDir: String) {
        let dir = URL(fileURLWithPath: (configDir as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("display.json")
        super.init()
        load()
        if !FileManager.default.fileExists(atPath: configURL.path) { save() }
    }

    func start() {
        hotkeyTarget = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            hotkeyTarget?.resync(reason: "hotkey"); return noErr
        }, 1, &spec, nil, nil)
        registerHotkey()
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.load(); self?.registerHotkey()  // pick up hand edits to the settings file
            self?.checkSchedule()
        }
        // Keep the 2s checks on time: App Nap would otherwise slow a windowless app to a crawl,
        // most of all at the lock screen. This doesn't stop the Mac sleeping.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                          reason: "watching for display re-sync triggers")
        prevIdle = idleSeconds()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.afterWake() }
        }
    }

    // MARK: settings

    func load() {
        guard let data = try? Data(contentsOf: configURL) else { return }
        do { config = try JSONDecoder().decode(DisplayConfig.self, from: data) }
        catch { displayLog("can't read \(configURL.path): \(error.localizedDescription)") }
    }

    func save() {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(config).write(to: configURL, options: .atomic)
    }

    private func registerHotkey() {
        guard config.hotkey != registeredHotkey else { return }
        if let r = hotkeyRef { UnregisterEventHotKey(r); hotkeyRef = nil }
        registeredHotkey = config.hotkey
        guard let hk = parseHotkey(config.hotkey) else {
            displayLog("hotkey \"\(config.hotkey)\" not understood; none set"); return
        }
        let id = EventHotKeyID(signature: OSType(0x7476_7273), id: 1)  // 'tvrs'
        let err = RegisterEventHotKey(hk.key, hk.mods, id, GetApplicationEventTarget(), 0, &hotkeyRef)
        displayLog(err == noErr ? "hotkey \(hk.symbol)" : "hotkey \(hk.symbol) is taken by another app (error \(err))")
    }

    // MARK: re-sync

    func resync(reason: String) {
        guard !busy else { return }
        busy = true
        lastResync = Date()
        displayLog("re-sync (\(reason))")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + config.sleepSeconds) {
            var a: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("display re-sync" as CFString, kIOPMUserActiveLocal, &a)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { IOPMAssertionRelease(a); self.busy = false }
        }
    }

    // The attached display re-syncs are for: an approved one, or any external one if none are approved
    func approvedConnected() -> DisplayID? {
        let ext = externalDisplays()
        return config.approved.isEmpty ? ext.first : ext.first { d in config.approved.contains { $0.same(d) } }
    }

    var retrying: Bool { missingSince != nil }

    // Every 2s: cheap checks (lid, display list, idle timer); a re-sync only when a trigger fires
    private func poll() {
        let lid = lidClosed(), shown = approvedConnected(), idle = idleSeconds()
        defer { prevIdle = idle; if let d = shown { lastSeen = d } }
        if shown?.name != lastShownName {
            lastShownName = shown?.name
            displayLog("display: \(shown?.name ?? "none")")
        }
        let nowArmed = config.onFirstTouch && lid && shown != nil && idle >= config.idleMinutes * 60
        if nowArmed && !armed { displayLog("armed: \(Int(idle / 60)) min idle with the lid shut, next touch re-syncs") }
        armed = nowArmed

        // Disconnect: keep re-syncing until it's back, the lid opens, or 30 minutes pass
        if let since = missingSince {
            if let d = shown { missingSince = nil; displayLog("\(d.name) is back: stop re-syncing") }
            else if !lid { missingSince = nil; displayLog("lid opened and still no display: stop re-syncing") }
            else if Date().timeIntervalSince(since) > 1800 { missingSince = nil; displayLog("no display for 30 minutes: stop re-syncing") }
            else if Date().timeIntervalSince(lastResync) >= config.sleepSeconds + config.retrySeconds {
                resync(reason: "display missing, retrying every \(Int(config.retrySeconds))s")
            }
            return
        }
        if config.onDisconnect, lid, shown == nil, let gone = lastSeen {
            lastSeen = nil; missingSince = Date()
            displayLog("\(gone.name) disappeared with the lid shut")
            resync(reason: "display missing")
            return
        }

        // First touch after a long idle: likely someone back at a TV that just came on.
        // Skipped right after a re-sync, whose wake-up can itself reset the idle timer.
        if config.onFirstTouch, lid, shown != nil, prevIdle >= config.idleMinutes * 60, idle < 10,
           Date().timeIntervalSince(lastResync) > 60 {
            resync(reason: "first touch after \(Int(prevIdle / 60)) min idle")
        }
    }

    private func afterWake() {
        guard config.onWake, lidClosed(), let d = approvedConnected(),
              Date().timeIntervalSince(lastResync) > 30 else { return }
        resync(reason: "after wake, \(d.name)")
    }

    // Scheduled re-syncs only run with the lid shut and a display attached,
    // so they never blank a screen you're looking at on the laptop itself.
    private func checkSchedule() {
        let now = Date(), cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let hm = f.string(from: now)
        let weekend = cal.isDateInWeekend(now)
        for s in config.schedule where s.time == hm {
            let today = s.days == "daily" || (s.days == "weekdays" && !weekend) || (s.days == "weekends" && weekend)
            let slot = "\(cal.ordinality(of: .day, in: .era, for: now) ?? 0) \(s.label)"
            guard today, !firedSlots.contains(slot) else { continue }
            firedSlots.insert(slot)
            if !lidClosed() { displayLog("scheduled \(s.label) skipped: lid open"); continue }
            guard let d = approvedConnected() else { displayLog("scheduled \(s.label) skipped: no display"); continue }
            resync(reason: "scheduled \(s.label), \(d.name)")
        }
    }

    // MARK: menu

    // Adds the display section to a menu that's rebuilt each time it opens
    func addItems(to menu: NSMenu) {
        load(); registerHotkey()  // pick up hand edits to the settings file
        let hk = parseHotkey(config.hotkey)?.symbol
        if retrying { menu.addItem(info("Display missing: re-syncing every \(Int(config.retrySeconds))s")) }
        menu.addItem(item("Re-sync display now" + (hk.map { "  \($0)" } ?? ""), #selector(resyncNow)))

        let autoMenu = NSMenu()
        let triggers = [("When the display disappears (retry every \(Int(config.retrySeconds))s)", config.onDisconnect),
                        ("First touch after \(Int(config.idleMinutes)) min idle", config.onFirstTouch),
                        ("After waking from sleep", config.onWake)]
        for (n, t) in triggers.enumerated() {
            let i = item(t.0, #selector(toggleTrigger(_:))); i.tag = n; i.state = t.1 ? .on : .off
            autoMenu.addItem(i)
        }
        autoMenu.addItem(.separator())
        autoMenu.addItem(info("Only with the lid shut; first touch works at the lock screen"))
        let auto = NSMenuItem(title: "Automatic re-sync", action: nil, keyEquivalent: "")
        auto.submenu = autoMenu
        menu.addItem(auto)

        let approvedMenu = NSMenu()
        let connected = externalDisplays()
        if connected.isEmpty { approvedMenu.addItem(info("No external display connected")) }
        for d in connected {
            let i = item(d.name, #selector(toggleApproved(_:)))
            i.representedObject = try? JSONEncoder().encode(d)
            i.state = config.approved.contains { $0.same(d) } ? .on : .off
            approvedMenu.addItem(i)
        }
        let away = config.approved.filter { a in !connected.contains { $0.same(a) } }
        if !away.isEmpty {
            approvedMenu.addItem(.separator())
            for d in away {
                let i = item("\(d.name) (not connected)", #selector(toggleApproved(_:)))
                i.representedObject = try? JSONEncoder().encode(d); i.state = .on
                approvedMenu.addItem(i)
            }
        }
        approvedMenu.addItem(.separator())
        approvedMenu.addItem(info("Re-syncs only touch ticked displays (none ticked = any)"))
        let a = NSMenuItem(title: "Approved displays", action: nil, keyEquivalent: "")
        a.submenu = approvedMenu
        menu.addItem(a)

        let schedMenu = NSMenu()
        if config.schedule.isEmpty { schedMenu.addItem(info("No scheduled re-syncs")) }
        for (n, s) in config.schedule.enumerated() {
            let i = item("Remove \(s.label)", #selector(removeSchedule(_:))); i.tag = n
            schedMenu.addItem(i)
        }
        schedMenu.addItem(.separator())
        schedMenu.addItem(item("Add a time…", #selector(addSchedule)))
        schedMenu.addItem(info("Runs only with the lid shut and a display attached"))
        let s = NSMenuItem(title: "Scheduled re-sync", action: nil, keyEquivalent: "")
        s.submenu = schedMenu
        menu.addItem(s)

        menu.addItem(item("Edit display settings…", #selector(editSettings)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = self; return i
    }

    private func info(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""); i.isEnabled = false; return i
    }

    @objc func resyncNow() { resync(reason: "menu") }

    @objc func toggleTrigger(_ sender: NSMenuItem) {
        switch sender.tag {
        case 0: config.onDisconnect.toggle(); if !config.onDisconnect { missingSince = nil }
        case 1: config.onFirstTouch.toggle()
        default: config.onWake.toggle()
        }
        save()
    }

    @objc func toggleApproved(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? Data,
              let d = try? JSONDecoder().decode(DisplayID.self, from: data) else { return }
        if config.approved.contains(where: { $0.same(d) }) { config.approved.removeAll { $0.same(d) } }
        else { config.approved.append(d) }
        save()
    }

    @objc func removeSchedule(_ sender: NSMenuItem) {
        guard config.schedule.indices.contains(sender.tag) else { return }
        config.schedule.remove(at: sender.tag); save()
    }

    @objc func addSchedule() {
        let alert = NSAlert()
        alert.messageText = "Scheduled display re-sync"
        alert.informativeText = "Time (24-hour) and days, e.g. \"19:00 weekdays\". Days: daily, weekdays or weekends."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = "19:00 daily"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let parts = field.stringValue.lowercased().split(separator: " ").map(String.init)
        let hm = parts.first.flatMap { t -> String? in
            let p = t.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
            return String(format: "%02d:%02d", p[0], p[1])
        }
        let days = parts.count > 1 ? parts[1] : "daily"
        guard let time = hm, ["daily", "weekdays", "weekends"].contains(days) else {
            let e = NSAlert(); e.messageText = "Couldn't read \"\(field.stringValue)\""; e.runModal(); return
        }
        config.schedule.append(ScheduledResync(time: time, days: days))
        config.schedule.sort { $0.time < $1.time }
        save()
    }

    @objc func editSettings() {  // in the default text editor, not whatever owns .json
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", configURL.path]
        try? p.run()
    }
}
