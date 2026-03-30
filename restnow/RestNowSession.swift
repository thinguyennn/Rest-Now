import Foundation
import AppKit
import Combine

final class RestNowSession: ObservableObject {
    enum Phase {
        case work
        case rest
    }

    let workDuration: TimeInterval
    let breakDuration: TimeInterval

    @Published private(set) var phase: Phase
    @Published private(set) var remainingSeconds: TimeInterval
    @Published private(set) var isPaused: Bool = false

    /// True when the cycle is suspended due to system lock/sleep.
    @Published private(set) var isSystemSuspended: Bool = false

    /// Lightweight signal incremented each rest-tick to trigger SwiftUI updates
    /// without mutating `remainingSeconds` or `phaseStartDate` every second.
    @Published private(set) var restTickSignal: UInt = 0

    /// Fires only when the work phase ends (one-shot) or every second during rest (for overlay countdown).
    private var timer: Timer?

    /// Timestamp when we last started/resumed the timer, used to compute remaining time accurately.
    private var phaseStartDate: Date?

    /// Pre-loaded sound to avoid filesystem I/O on every bell.
    private let bellSound = NSSound(named: NSSound.Name("Submarine"))

    init(
        workDuration: TimeInterval = 20 * 60,
        breakDuration: TimeInterval = 10 * 60
    ) {
        self.workDuration = workDuration
        self.breakDuration = breakDuration
        self.phase = .work
        self.remainingSeconds = workDuration
        scheduleTimer()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Public Actions

    func resetCycle() {
        phase = .work
        remainingSeconds = workDuration
        scheduleTimer()
    }

    func startBreakNow() {
        phase = .rest
        remainingSeconds = breakDuration
        pauseMediaPlayback()
        playBell()
        scheduleTimer()
    }

    func skipBreak() {
        phase = .work
        remainingSeconds = workDuration
        playBell()
        scheduleTimer()
    }

    func togglePause() {
        if isPaused {
            resumeCycle()
        } else {
            pauseCycle()
        }
    }

    func pauseCycle() {
        guard !isPaused else { return }
        isPaused = true
        // Snapshot remaining time before stopping
        if let start = phaseStartDate {
            let elapsed = Date().timeIntervalSince(start)
            remainingSeconds = max(remainingSeconds - elapsed, 0)
        }
        timer?.invalidate()
        timer = nil
        phaseStartDate = nil
    }

    func resumeCycle() {
        guard isPaused else { return }
        isPaused = false
        guard !isSystemSuspended else { return }
        scheduleTimer()
    }

    func suspendForSystemState() {
        guard !isSystemSuspended else { return }
        isSystemSuspended = true

        if !isPaused, let start = phaseStartDate {
            let elapsed = Date().timeIntervalSince(start)
            remainingSeconds = max(remainingSeconds - elapsed, 0)
        }

        timer?.invalidate()
        timer = nil
        phaseStartDate = nil
    }

    func resumeFromSystemState() {
        guard isSystemSuspended else { return }
        isSystemSuspended = false
        guard !isPaused else { return }
        scheduleTimer()
    }

    // MARK: - Menu Info (computed on demand, no per-second cost)

    /// Static text for the menu item — computed only when the menu is opened.
    var menuTimeDescription: String {
        let remaining = currentRemainingSeconds
        let formatted = Self.formattedTime(remaining)

        switch phase {
        case .work:
            if isPaused { return "Paused – \(formatted) until break" }
            return "\(formatted) until break"
        case .rest:
            if isPaused { return "Paused – Break \(formatted)" }
            return "Break – \(formatted) remaining"
        }
    }

    /// Accurate remaining seconds computed from the start-date, no timer needed.
    var currentRemainingSeconds: TimeInterval {
        if isPaused || isSystemSuspended { return max(remainingSeconds, 0) }
        guard let start = phaseStartDate else { return max(remainingSeconds, 0) }
        let elapsed = Date().timeIntervalSince(start)
        return max(remainingSeconds - elapsed, 0)
    }

    // MARK: - Shared Formatter

    static func formattedTime(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - Timer Scheduling

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil

        guard !isSystemSuspended else {
            phaseStartDate = nil
            return
        }

        phaseStartDate = Date()

        switch phase {
        case .work:
            // ONE-SHOT timer — fires only when rest should begin.
            // Zero CPU cost in between. Allows macOS App Nap.
            let t = Timer(
                timeInterval: remainingSeconds,
                repeats: false
            ) { [weak self] _ in
                self?.switchPhase()
            }
            t.tolerance = 2.0 // Allow macOS to coalesce with other timers
            RunLoop.main.add(t, forMode: .common)
            timer = t

        case .rest:
            // 1-second repeating timer for overlay countdown display.
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.restTick()
            }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func restTick() {
        guard !isPaused, !isSystemSuspended else { return }

        // Use currentRemainingSeconds (computed from the original phaseStartDate)
        // instead of mutating remainingSeconds + phaseStartDate every tick.
        if currentRemainingSeconds <= 0 {
            switchPhase()
        } else {
            // Increment a lightweight signal to trigger SwiftUI re-render.
            // No @Published TimeInterval mutation, no Date() allocation.
            restTickSignal &+= 1
        }
    }

    private func switchPhase() {
        switch phase {
        case .work:
            startBreakNow()
        case .rest:
            skipBreak()
        }
    }

    // MARK: - Sound

    private func playBell() {
        bellSound?.play()
    }
    // MARK: - Media Pause

    /// Sends a dedicated "pause" command to the system's now-playing media session.
    /// - If something is playing → pauses it.
    /// - If nothing is playing → does nothing (no risk of starting playback).
    /// Cost: one indirect function call, zero allocation.
    private func pauseMediaPlayback() {
        _ = MediaRemoteBridge.sendPause?(1, nil)  // 1 = kMRPause
    }
}

// MARK: - MediaRemote Private Framework Bridge

private typealias MRSendCommand = @convention(c) (Int, CFDictionary?) -> Bool

private enum MediaRemoteBridge {
    /// Loaded once (lazy, thread-safe). Looks up MRMediaRemoteSendCommand from the
    /// private MediaRemote framework used by macOS Control Center.
    static let sendPause: MRSendCommand? = {
        guard let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL
        ) else { return nil }

        guard let ptr = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteSendCommand" as CFString
        ) else { return nil }

        return unsafeBitCast(ptr, to: MRSendCommand.self)
    }()
}
