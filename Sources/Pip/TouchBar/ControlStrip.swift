import AppKit

/// Private Touch Bar API, used only when the user turns on "Keep Pip in the
/// Control Strip". Public NSTouchBar content is shown only while its app is
/// frontmost; these DFRFoundation / NSTouchBar SPIs are what lets an item live
/// in the system Control Strip and expand over any app, as the design intends.
///
/// Every symbol is looked up at runtime and checked, so a macOS update that
/// removes one disables the feature instead of crashing.
@MainActor
enum ControlStrip {
    nonisolated(unsafe) private static let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    private typealias SetPresence = @convention(c) (NSString, Bool) -> Void
    private typealias ShowCloseBox = @convention(c) (Bool) -> Void
    private typealias PresentModal = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString) -> Void

    private static let addTray = NSSelectorFromString("addSystemTrayItem:")
    private static let removeTray = NSSelectorFromString("removeSystemTrayItem:")
    private static let present = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
    private static let dismiss = NSSelectorFromString("dismissSystemModalTouchBar:")

    static var isAvailable: Bool {
        dfr != nil && symbol("DFRElementSetControlStripPresenceForIdentifier") != nil
            && (NSTouchBarItem.self as AnyObject).responds(to: addTray)
            && class_getClassMethod(NSTouchBar.self, present) != nil
    }

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dfr.flatMap { dlsym($0, name) }
    }

    /// Puts `item` in the Control Strip (or takes it out).
    static func setTrayItem(_ item: NSTouchBarItem, visible: Bool) {
        guard isAvailable, let sym = symbol("DFRElementSetControlStripPresenceForIdentifier") else { return }
        if visible {
            _ = (NSTouchBarItem.self as AnyObject).perform(addTray, with: item)
        }
        unsafeBitCast(sym, to: SetPresence.self)(item.identifier.rawValue as NSString, visible)
        if !visible, (NSTouchBarItem.self as AnyObject).responds(to: removeTray) {
            _ = (NSTouchBarItem.self as AnyObject).perform(removeTray, with: item)
        }
    }

    /// Expands `bar` over whatever app is frontmost.
    static func presentModal(_ bar: NSTouchBar, trayIdentifier: NSTouchBarItem.Identifier) {
        guard isAvailable, let method = class_getClassMethod(NSTouchBar.self, present) else { return }
        if let sym = symbol("DFRSystemModalShowsCloseBoxWhenFrontMost") {
            unsafeBitCast(sym, to: ShowCloseBox.self)(true)
        }
        let imp = unsafeBitCast(method_getImplementation(method), to: PresentModal.self)
        imp(NSTouchBar.self, present, bar, 1, trayIdentifier.rawValue as NSString)
    }

    static func dismissModal(_ bar: NSTouchBar) {
        guard (NSTouchBar.self as AnyObject).responds(to: dismiss) else { return }
        _ = (NSTouchBar.self as AnyObject).perform(dismiss, with: bar)
    }
}
