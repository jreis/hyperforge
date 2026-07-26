// OnboardingView.swift
// Permissions + Hyper setup + live 3-chord first-run challenge.

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var challenge = FirstRunChallengeStore.shared
    @State private var step = 0

    private let infoSteps: [(String, String, String)] = [
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
    ]

    /// info steps + interactive prove-it step
    private var lastInfoIndex: Int { infoSteps.count - 1 }
    private var proveStep: Int { infoSteps.count }
    private var totalSteps: Int { infoSteps.count + 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            GlassCard(padding: 28) {
                VStack(spacing: 22) {
                    if step <= lastInfoIndex {
                        infoStepBody
                    } else {
                        proveStepBody
                    }

                    // Dots + navigation
                    ZStack {
                        HStack(spacing: 8) {
                            ForEach(0..<totalSteps, id: \.self) { i in
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
                                Color.clear.frame(width: 1, height: 1)
                            }
                            Spacer()
                            if step < proveStep {
                                Button("Continue") {
                                    step += 1
                                    if step == proveStep {
                                        // Ensure engine is listening for the live checks.
                                        appState.engine.start()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(HFTheme.accent)
                            } else {
                                Button(challenge.allProved ? "Enter HyperForge" : "Skip & enter") {
                                    if !challenge.allProved {
                                        challenge.skip()
                                    }
                                    appState.completeOnboarding()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(HFTheme.accent)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 500)
                .multilineTextAlignment(.center)
            }
        }
        .onAppear {
            // Fresh installs should re-run the interactive checks.
            if !UserDefaults.standard.bool(forKey: "hf.hasCompletedOnboarding") {
                // leave challenge as-is if partially done
            }
        }
    }

    private var infoStepBody: some View {
        VStack(spacing: 22) {
            Image(systemName: infoSteps[step].0)
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [HFTheme.accent, HFTheme.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(infoSteps[step].1)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(HFTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(infoSteps[step].2)
                .font(.system(size: 13))
                .foregroundStyle(HFTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

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
        }
    }

    private var proveStepBody: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [HFTheme.accent, HFTheme.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("Three chords. Ten seconds.")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(HFTheme.textPrimary)

            Text("Do these live with the engine running. Each check turns green when HyperForge sees the real input.")
                .font(.system(size: 12))
                .foregroundStyle(HFTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            FirstRunChallengeView(compact: false)
                .multilineTextAlignment(.leading)
        }
    }
}
