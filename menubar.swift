// lidstay menu bar icon: pause lidstay so closing the lid sleeps the Mac again,
// for a few hours or until turned back on. Same options as Matt's Hammerspoon
// "Lid" submenu. It only writes or moves the pause file; the root daemon reads it.
// Built by install.sh with swiftc (comes with git's Command Line Tools).
import AppKit

let pauseFile = "/Users/Shared/lidstay/pause_until"

enum Pause { case none, manual, until(Date) }

func readPause() -> Pause {
    guard let raw = try? String(contentsOfFile: pauseFile, encoding: .utf8) else { return .none }
    let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if v == "manual" { return .manual }
    if let t = Double(v), t > Date().timeIntervalSince1970 { return .until(Date(timeIntervalSince1970: t)) }
    return .none
}

func writePause(_ value: String) {
    do { try (value + "\n").write(toFile: pauseFile, atomically: true, encoding: .utf8) }
    catch {
        let a = NSAlert()
        a.messageText = "lidstay isn't installed (can't write \(pauseFile))"
        a.runModal()
    }
}

func resume() { try? FileManager.default.moveItem(atPath: pauseFile, toPath: pauseFile + ".done") }

class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func applicationDidFinishLaunching(_ n: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refreshIcon()
        // A timed pause ends on its own; keep the icon honest
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in self.refreshIcon() }
    }

    func refreshIcon() {
        let paused: Bool
        if case .none = readPause() { paused = false } else { paused = true }
        let name = paused ? "moon.zzz" : "laptopcomputer"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "lidstay")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = paused ? "lidstay: lid sleep allowed" : "lidstay: stays awake with lid closed"
    }

    // Rebuilt each time it opens, so the status line is current
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let pause = readPause()
        let status: String
        switch pause {
        case .manual: status = "Lid sleep allowed (until you turn it back)"
        case .until(let d):
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            status = "Lid sleep allowed until " + f.string(from: d)
        case .none: status = "Lid closed: stays awake"
        }
        let s = NSMenuItem(title: status, action: nil, keyEquivalent: ""); s.isEnabled = false
        menu.addItem(s)
        menu.addItem(.separator())
        for h in [1, 2, 4, 8] {
            add(menu, "Allow lid sleep for \(h) hour\(h == 1 ? "" : "s")", tag: h)
        }
        let manual = add(menu, "Allow lid sleep until I turn it back", tag: -1)
        if case .manual = pause { manual.state = .on }
        let awake = add(menu, "Keep awake with lid closed", tag: 0)
        if case .none = pause { awake.state = .on }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit lidstay icon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    @discardableResult
    func add(_ menu: NSMenu, _ title: String, tag: Int) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
        i.target = self; i.tag = tag
        menu.addItem(i)
        return i
    }

    @objc func pick(_ sender: NSMenuItem) {
        switch sender.tag {
        case 0: resume()
        case -1: writePause("manual")
        default: writePause(String(Int(Date().timeIntervalSince1970) + sender.tag * 3600))
        }
        refreshIcon()
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
