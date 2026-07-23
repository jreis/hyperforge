// OnboardingView.swift
// Clear permissions + Hyper/Karabiner setup.

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step = 0

    private let steps: [(String, String, String)] = [
        (
            "flame.fill",
            "Welcome to HyperForge",
            "Power-user automation for Hyper Key + Karabiner. Fully local, private by default, and built for environments where Hammerspoon is blocked."
        ),
        (
            "keyboard.fill",
            "Caps Lock becomes Hyper",
            "Karabiner maps Caps → Hyper (F18 or ⌘⌃⌥⇧). Tap Caps alone for Escape. For 4-mod Hyper, also enable F19 (help) and F20 (dashboard) bridges — Doctor walks you through it."
        ),
        (
            "hand.raised.fill",
            "Accessibility permission",
            "macOS needs Accessibility so HyperForge can observe Hyper keys and synthesize keystrokes, scrolls, and window moves. Nothing is uploaded."
        ),
        (
            "sparkles",
            "You're ready",
            "Use Doctor to verify setup. Hold Caps + key for Hyper actions, hold Space + H/J/K/L for arrows, menu bar flame for Keybindings anytime."
        ),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            GlassCard(padding: 28) {
                VStack(spacing: 22) {
                    Image(systemName: steps[step].0)
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [HFTheme.accent, HFTheme.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(steps[step].1)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(HFTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(steps[step].2)
                        .font(.system(size: 13))
                        .foregroundStyle(HFTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    if step == 2 {
                        HStack {
                            Button("Request Accessibility") {
                                PermissionsService.requestTrust()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(HFTheme.warning)
                            Button("Open System Settings") {
                                PermissionsService.openSystemSettings()
                            }
                        }
                    }

                    // ZStack keeps page dots geometrically centered regardless of
                    // Back / Continue button widths (or Back being hidden on step 0).
                    ZStack {
                        HStack(spacing: 8) {
                            ForEach(0..<steps.count, id: \.self) { i in
                                Circle()
                                    .fill(i == step ? HFTheme.accent : Color.white.opacity(0.2))
                                    .frame(width: 7, height: 7)
                                    .animation(.easeInOut(duration: 0.2), value: step)
                            }
                        }

                        HStack {
                            if step > 0 {
                                Button("Back") { step -= 1 }
                            } else {
                                // Invisible placeholder so layout stays balanced if needed
                                Color.clear.frame(width: 1, height: 1)
                            }
                            Spacer()
                            if step < steps.count - 1 {
                                Button("Continue") { step += 1 }
                                    .buttonStyle(.borderedProminent)
                                    .tint(HFTheme.accent)
                            } else {
                                Button("Enter HyperForge") {
                                    appState.completeOnboarding()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(HFTheme.accent)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 460)
                .multilineTextAlignment(.center)
            }
        }
    }
}
