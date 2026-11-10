import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let tabs = TabState()
    private let controller = GameController()
    private lazy var training = GameController(mode: .train, history: controller.history)
    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.isMouseCoalescingEnabled = false
        // Build Walking Distance tables off the main thread.
        Task.detached(priority: .utility) { _ = WalkingDistance.shared }

        buildMenu()
        let host = NSHostingView(rootView: ContentView(controller: controller, training: training, tabs: tabs))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 630),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "fifteen"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Palette.background
        window.contentView = host
        window.contentMinSize = NSSize(width: 320, height: 420)
        window.acceptsMouseMovedEvents = true
        window.center()
        window.setFrameAutosaveName("FifteenPuzzleMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            return self.handleKey(e)   // nil = handled/swallowed (no beep)
        }
    }

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        guard NSApp.keyWindow != nil else { return e }
        let mods = e.modifierFlags.intersection([.command, .control, .option, .shift])
        // Arrows/Home/End with a modifier held do nothing but are still swallowed (no beep).
        if !mods.isEmpty { return [123, 124, 125, 126, 115, 119].contains(e.keyCode) ? nil : e }
        if e.keyCode == 17 { // T
            if !e.isARepeat {
                Palette.rotation = (Palette.rotation + 1) % 4
                self.controller.onHintsChanged?()
                training.onHintsChanged?()
            }
            return nil
        }
        if tabs.tab == .history { return nil }
        let controller = tabs.tab == .train ? training : self.controller
        switch e.keyCode {
        case 1: // S
            if tabs.tab == .train { controller.toggleSolve() }
            return nil
        case 5: // G
            if tabs.tab == .train { controller.toggleGhost() }
            return nil
        case 49: // Space
            if tabs.tab == .train { controller.playOptimalMove() }
            return nil
        case 15: controller.restart(); return nil                 // R
        case 123: controller.navigate(.back); return nil          // left
        case 124: controller.navigate(.forward); return nil       // right
        case 126: controller.navigate(controller.phase == .reviewing ? .start : .prevSibling); return nil // up
        case 125: controller.navigate(controller.phase == .reviewing ? .end : .nextSibling); return nil   // down
        case 115: controller.navigate(.start); return nil         // home
        case 119: controller.navigate(.end); return nil           // end
        default: return e
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit fifteen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }
}
