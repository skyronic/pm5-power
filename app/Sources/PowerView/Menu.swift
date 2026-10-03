import AppKit

/// The right-click menu, built in AppKit each time it opens.
///
/// A SwiftUI `.contextMenu` is rebuilt on every redraw — a couple of times a second while riding —
/// which makes open submenus flicker and close. This one doesn't change while it's open.
/// Settings are written to UserDefaults, which the view reads through `@AppStorage`.
func makeMenu(model: Model, source: PowerSource) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false

    menu.addItem(.label(model.link.message))
    if let error = model.lastError { menu.addItem(.label(error)) }
    switch model.link {
    case .paused: menu.addItem(.action("Connect") { source.resume() })
    case .scanning, .connecting: menu.addItem(.action("Stop Scanning") { source.pause("Off") })
    case .connected: menu.addItem(.action("Disconnect") { source.pause("Off") })
    default: break
    }
    menu.addItem(.separator())

    let mainIsAverage = UserDefaults.standard.bool(forKey: "mainIsAverage")
    let toggle = NSMenuItem.action("Show 3s Average as Main Number") {
        UserDefaults.standard.set(!mainIsAverage, forKey: "mainIsAverage")
    }
    toggle.state = mainIsAverage ? .on : .off
    menu.addItem(toggle)
    menu.addItem(.choice("Size", key: "scale", default: 1.0,
                         [("Small", 0.75), ("Medium", 1.0), ("Large", 1.5)]))
    menu.addItem(.choice("Background", key: "opacity", default: 0.7,
                         [("Light", 0.4), ("Medium", 0.7), ("Solid", 0.95)]))
    menu.addItem(.choice("Opacity", key: "windowOpacity", default: 1.0,
                         [("100%", 1.0), ("75%", 0.75), ("50%", 0.5), ("30%", 0.3)]))
    menu.addItem(.choice("Refresh", key: Model.refreshKey, default: 0.0,
                         [("Live", 0.0), ("Every 2 s", 2.0), ("Every 5 s", 5.0), ("Every 10 s", 10.0)]))
    menu.addItem(.separator())
    menu.addItem(.action("Quit") { NSApp.terminate(nil) })
    return menu
}

private final class ClosureItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

private extension NSMenuItem {
    static func action(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        ClosureItem(title, handler)
    }

    static func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A submenu of options for one Double setting, with the current one checked.
    static func choice(_ title: String, key: String, default fallback: Double,
                       _ options: [(String, Double)]) -> NSMenuItem {
        let current = UserDefaults.standard.object(forKey: key) as? Double ?? fallback
        let sub = NSMenu()
        for (name, value) in options {
            let item = action(name) { UserDefaults.standard.set(value, forKey: key) }
            item.state = value == current ? .on : .off
            sub.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }
}
