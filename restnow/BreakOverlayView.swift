import SwiftUI

/// Static gradient background — extracted so SwiftUI never re-diffs it
/// during per-second countdown updates.
private struct BreakBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.85),
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.95),
                    Color.black.opacity(1.0)
                ]),
                center: .center,
                startRadius: 0,
                endRadius: 900
            )
        }
        .ignoresSafeArea()
    }
}

struct BreakOverlayView: View {
    @ObservedObject var session: RestNowSession

    var body: some View {
        // Subscribe to the lightweight tick signal so SwiftUI re-evaluates
        // the body each second, then read the computed remaining time.
        let _ = session.restTickSignal
        let remaining = session.currentRemainingSeconds

        ZStack {
            BreakBackgroundView()

            VStack(spacing: 20) {
                Text("Rest Now")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.white)

                Text("Take a break. Stand up. Stretch.")
                    .font(.largeTitle.weight(.regular))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.9))

                Text(RestNowSession.formattedTime(remaining))
                    .font(.system(size: 44, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)

                if session.breakDuration - remaining >= 60 {
                    Button {
                        session.skipBreak()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.right.2")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Skip Break")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.35))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}
