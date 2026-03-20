import AppKit
import SwiftUI
import CoreGraphics

final class BreakOverlayWindowManager {
    private let session: RestNowSession
    private var windows: [NSWindow] = []

    private let fadeDuration: TimeInterval = 0.45

    /// Track screen config to detect when we need to rebuild windows.
    private var lastScreenCount: Int = 0

    init(session: RestNowSession) {
        self.session = session
    }

    func show() {
        let currentScreenCount = NSScreen.screens.count

        // Reuse existing windows if screen configuration hasn't changed.
        if !windows.isEmpty && currentScreenCount == lastScreenCount {
            windows.forEach { window in
                window.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = fadeDuration
                    window.animator().alphaValue = 1
                }
            }
            NSApp.activate(ignoringOtherApps: true)
            windows.first?.makeKeyAndOrderFront(nil)
            return
        }

        // Tear down old windows if screen config changed.
        tearDownWindows()

        let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

        for screen in NSScreen.screens {
            let frame = screen.frame
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.setFrame(frame, display: true)

            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = level
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.alphaValue = 0

            let hostingView = NSHostingView(rootView: BreakOverlayView(session: session))
            hostingView.frame = NSRect(origin: .zero, size: frame.size)
            hostingView.autoresizingMask = [.width, .height]
            window.contentView = hostingView

            windows.append(window)
        }

        lastScreenCount = currentScreenCount

        NSApp.activate(ignoringOtherApps: true)

        for (idx, window) in windows.enumerated() {
            if idx == 0 {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeDuration
                window.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        // Fade out but keep windows alive for reuse.
        windows.forEach { window in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeDuration
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
            }
        }
    }

    /// Releases all windows (called when screen configuration changes or on teardown).
    private func tearDownWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        lastScreenCount = 0
    }
}
