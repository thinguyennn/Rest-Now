import AppKit
import SwiftUI
import CoreGraphics

final class BreakOverlayWindowManager {
    private let session: RestNowSession
    private var windows: [NSWindow] = []
    private var previousApplication: NSRunningApplication?
    private var isVisible = false
    private var visibilityGeneration: UInt = 0

    private let fadeDuration: TimeInterval = 0.45

    /// Track screen config to detect when we need to rebuild windows.
    private var lastScreenCount: Int = 0

    init(session: RestNowSession) {
        self.session = session
    }

    func show() {
        let currentScreenCount = NSScreen.screens.count
        guard !isVisible || currentScreenCount != lastScreenCount else { return }

        if !isVisible,
           let application = NSWorkspace.shared.frontmostApplication,
           application.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApplication = application
        }
        isVisible = true
        visibilityGeneration &+= 1

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

    func hide(restoreFocus: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        visibilityGeneration &+= 1
        let generation = visibilityGeneration
        let application = previousApplication
        if restoreFocus {
            previousApplication = nil
        }

        // Wait for every screen to fade before returning focus.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            windows.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            // A new break must not be hidden by an earlier fade completion.
            guard self.visibilityGeneration == generation else { return }
            self.windows.forEach { $0.orderOut(nil) }

            guard restoreFocus,
                  NSApp.isActive,
                  let application,
                  !application.isTerminated else { return }

            // Leave focus on settings or another Rest Now window, if opened.
            if let keyWindow = NSApp.keyWindow,
               !self.windows.contains(where: { $0 === keyWindow }) {
                return
            }

            NSApp.yieldActivation(to: application)
            application.activate(options: [])
        }
    }

    /// Releases all windows (called when screen configuration changes or on teardown).
    private func tearDownWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        lastScreenCount = 0
    }
}
