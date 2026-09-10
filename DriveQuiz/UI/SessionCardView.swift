import SwiftUI

/// The only thing on screen during a drive. Session name, score, stop.
/// No progress bar, no question text, no animation. Nothing that rewards
/// looking at it.
struct SessionCardView: View {

    let card: CardState
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(card.sessionName)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(card.scoreLine)
                .font(.system(size: 84, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("\(card.score) correct out of \(card.asked)")

            if card.dailyStreak >= 2 {
                Text("Day \(card.dailyStreak)")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if card.watchdogEnded {
                Text("Stopped: audio was not responding")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if card.isPaused {
                Text("Paused. Say resume.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: onStop) {
                Text("Stop")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 88)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .accessibilityHint("Ends the game")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        // The driver should never need this screen, but if they glance,
        // it must be readable at arm's length in daylight.
        .dynamicTypeSize(.large ... .accessibility2)
    }
}
