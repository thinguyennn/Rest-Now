import AppKit
import Combine
import Foundation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let workDurationSeconds = "restnow.workDurationSeconds"
        static let restDurationSeconds = "restnow.restDurationSeconds"
    }

    private enum SystemState {
        static let screenLocked = Notification.Name("com.apple.screenIsLocked")
        static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")
    }

    private enum SystemEvent {
        case screenLocked
        case screenUnlocked
        case systemWillSleep
        case systemDidWake
        case displaysDidSleep
        case displaysDidWake
    }

    private var session: RestNowSession?
    private var overlayManager: BreakOverlayWindowManager?

    private var statusItem: NSStatusItem?

    private var timeInfoItem: NSMenuItem?
    private var startBreakItem: NSMenuItem?
    private var skipBreakItem: NSMenuItem?
    private var pauseCycleItem: NSMenuItem?
    private var resetItem: NSMenuItem?

    /// We only subscribe to phase/pause changes (infrequent), not per-second ticks.
    private var cancellables = Set<AnyCancellable>()

    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var isScreenLocked = false
    private var isSystemAsleep = false
    private var areDisplaysAsleep = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureSystemStateObservers()

        if let work = UserDefaults.standard.object(forKey: DefaultsKey.workDurationSeconds) as? Double,
           let rest = UserDefaults.standard.object(forKey: DefaultsKey.restDurationSeconds) as? Double {
            startSession(workDuration: work, restDuration: rest)
        } else {
            showOnboarding()
        }
    }

    @objc private func startBreakNow() {
        session?.startBreakNow()
    }

    @objc private func skipBreak() {
        session?.skipBreak()
    }

    @objc private func resetCycle() {
        session?.resetCycle()
    }

    @objc private func togglePauseCycle() {
        session?.togglePause()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.forEach { distributedCenter.removeObserver($0) }
    }

    private func configureSystemStateObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleSystemEvent(.systemWillSleep)
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleSystemEvent(.systemDidWake)
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleSystemEvent(.displaysDidSleep)
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleSystemEvent(.displaysDidWake)
            }
        ]

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers = [
            distributedCenter.addObserver(
                forName: SystemState.screenLocked,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleSystemEvent(.screenLocked)
            },
            distributedCenter.addObserver(
                forName: SystemState.screenUnlocked,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleSystemEvent(.screenUnlocked)
            }
        ]
    }

    private var isSystemInteractive: Bool {
        !isScreenLocked && !isSystemAsleep && !areDisplaysAsleep
    }

    private func handleSystemEvent(_ event: SystemEvent) {
        let wasInteractive = isSystemInteractive

        switch event {
        case .screenLocked:
            isScreenLocked = true
        case .screenUnlocked:
            isScreenLocked = false
        case .systemWillSleep:
            isSystemAsleep = true
        case .systemDidWake:
            isSystemAsleep = false
        case .displaysDidSleep:
            areDisplaysAsleep = true
        case .displaysDidWake:
            areDisplaysAsleep = false
        }

        let isInteractive = isSystemInteractive

        if wasInteractive && !isInteractive {
            overlayManager?.hide()
            session?.suspendForSystemState()
        } else if !wasInteractive && isInteractive {
            session?.resumeFromSystemState()
            updateOverlayVisibility()
        } else if !isInteractive {
            overlayManager?.hide()
        }
    }

    private func updateOverlayVisibility() {
        guard let session else { return }

        switch session.phase {
        case .work:
            overlayManager?.hide()
        case .rest:
            if isSystemInteractive {
                overlayManager?.show()
            } else {
                overlayManager?.hide()
            }
        }
    }

    private func startSession(workDuration: TimeInterval, restDuration: TimeInterval) {
        cancellables.removeAll()

        overlayManager?.hide()
        overlayManager = nil

        let session = RestNowSession(workDuration: workDuration, breakDuration: restDuration)
        self.session = session

        let overlayManager = BreakOverlayWindowManager(session: session)
        self.overlayManager = overlayManager

        // --- Status bar: icon only, no title text ---
        let item: NSStatusItem
        if let existing = statusItem {
            item = existing
        } else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem = item
        }

        if let button = item.button {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            let image = (
                NSImage(systemSymbolName: "eye.half.closed.fill", accessibilityDescription: "Rest Now") ??
                NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "Rest Now") ??
                NSImage(systemSymbolName: "eye", accessibilityDescription: "Rest Now")
            )?
                .withSymbolConfiguration(symbolConfig)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.title = "" // No text in menu bar — zero per-second updates
        }

        // --- Build menu ---
        let menu = NSMenu()
        menu.delegate = self  // Update time info only when menu is opened

        // Dynamic time info shown inside the menu (computed on demand)
        let timeInfo = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        timeInfo.isEnabled = false
        menu.addItem(timeInfo)
        self.timeInfoItem = timeInfo

        menu.addItem(.separator())

        let pauseCycle = NSMenuItem(title: "Pause Cycle", action: #selector(togglePauseCycle), keyEquivalent: "p")
        pauseCycle.target = self
        menu.addItem(pauseCycle)
        self.pauseCycleItem = pauseCycle

        let reset = NSMenuItem(title: "Reset Cycle", action: #selector(resetCycle), keyEquivalent: "r")
        reset.target = self
        menu.addItem(reset)
        self.resetItem = reset

        menu.addItem(.separator())

        let startBreak = NSMenuItem(title: "Start Break Now", action: #selector(startBreakNow), keyEquivalent: "b")
        startBreak.target = self
        menu.addItem(startBreak)
        self.startBreakItem = startBreak

        let skipBreak = NSMenuItem(title: "Skip Break", action: #selector(self.skipBreak), keyEquivalent: "s")
        skipBreak.target = self
        menu.addItem(skipBreak)
        self.skipBreakItem = skipBreak

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Rest Now", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu

        // --- Subscribe ONLY to phase and pause changes (very infrequent) ---
        Publishers.CombineLatest(session.$phase, session.$isPaused)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase, isPaused in
                guard let self else { return }
                self.pauseCycleItem?.title = isPaused ? "Resume Cycle" : "Pause Cycle"

                switch phase {
                case .work:
                    self.skipBreakItem?.isEnabled = false
                    self.startBreakItem?.isEnabled = true
                case .rest:
                    self.skipBreakItem?.isEnabled = true
                    self.startBreakItem?.isEnabled = false
                }

                self.updateOverlayVisibility()
            }
            .store(in: &cancellables)

        skipBreakItem?.isEnabled = false
        updateOverlayVisibility()
    }

    private func showOnboarding() {
        let hostingView = NSHostingView(
            rootView: OnboardingView(
                title: "RestNow",
                subtitle: "Choose your work and rest durations.",
                primaryButtonTitle: "Start",
                initialWorkMinutes: 30,
                initialRestMinutes: 10
            ) { [weak self] workDuration, restDuration in
                guard let self else { return }

                UserDefaults.standard.set(workDuration, forKey: DefaultsKey.workDurationSeconds)
                UserDefaults.standard.set(restDuration, forKey: DefaultsKey.restDurationSeconds)

                self.onboardingWindow?.close()
                self.onboardingWindow = nil

                self.startSession(workDuration: workDuration, restDuration: restDuration)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Rest Now"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        onboardingWindow = window
    }

    private func showSettings() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let workSecondsRaw = UserDefaults.standard.double(forKey: DefaultsKey.workDurationSeconds)
        let restSecondsRaw = UserDefaults.standard.double(forKey: DefaultsKey.restDurationSeconds)

        let allowed: Set<Int> = [1, 3, 5, 10, 20, 30, 60]

        let initialWork = allowed.contains(Int(workSecondsRaw)) ? Int(workSecondsRaw) : 30
        let initialRest = allowed.contains(Int(restSecondsRaw)) ? Int(restSecondsRaw) : 10

        let hostingView = NSHostingView(
            rootView: OnboardingView(
                title: "Rest Now",
                subtitle: "Update your work and rest durations.",
                primaryButtonTitle: "Save",
                initialWorkMinutes: initialWork,
                initialRestMinutes: initialRest,
                showsProjectLink: true
            ) { [weak self] workDuration, restDuration in
                guard let self else { return }

                UserDefaults.standard.set(workDuration, forKey: DefaultsKey.workDurationSeconds)
                UserDefaults.standard.set(restDuration, forKey: DefaultsKey.restDurationSeconds)

                self.settingsWindow?.close()
                self.settingsWindow = nil

                self.startSession(workDuration: workDuration, restDuration: restDuration)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        settingsWindow = window
    }
}

// MARK: - NSMenuDelegate (compute time only when user opens the menu)

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        timeInfoItem?.title = session?.menuTimeDescription ?? "Not running"
    }
}
