// PowerView: an always-on-top wattage display for the Concept2 BikeErg (PM5).

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var source: PowerSource!
    var panel: NSPanel!

    func applicationDidFinishLaunching(_ n: Notification) {
        source = CommandLine.arguments.contains("--demo") ? Demo(model: model) : Bike(model: model)
        let host = NSHostingController(rootView: PowerDisplay(model: model, source: source))
        host.sizingOptions = .preferredContentSize  // window follows the Size setting

        panel = NSPanel(contentRect: NSRect(origin: .zero, size: PowerDisplay.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentViewController = host
        panel.level = .statusBar
        // Accessory app (LSUIElement) + these behaviors let the window float over other apps' full-screen spaces.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        if !panel.setFrameUsingName("PowerWindow"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - PowerDisplay.size.width - 20, y: screen.maxY - 20))
        }
        panel.setFrameAutosaveName("PowerWindow")
        panel.orderFrontRegardless()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
