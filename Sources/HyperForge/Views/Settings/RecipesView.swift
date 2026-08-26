// RecipesView.swift
// AX UI automation playbooks (UIA spiritual successor).

import SwiftUI

struct RecipesView: View {
    @ObservedObject private var store = AXRecipeStore.shared
    @ObservedObject private var recorder = AXRecipeRecorder.shared
    @State private var name = ""
    @State private var clickTarget = "OK"
    @State private var pendingRecording: AXRecipe?
    @State private var recordingName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AX Recipes")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(HFTheme.textPrimary)
                        Text("Multi-step Accessibility automation — click named UI, keys, paste. Clicks wait up to 2s for a sheet.")
                            .font(.system(size: 13))
                            .foregroundStyle(HFTheme.textSecondary)
                    }
                    Spacer()
                    if recorder.isRecording {
                        Button("Stop & Save") {
                            pendingRecording = recorder.stop()
                            recordingName = pendingRecording?.name ?? ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HFTheme.danger)
                    } else {
                        Button("Record…") { recorder.start() }
                            .buttonStyle(.bordered)
                    }
                    Button("Run menu…") { store.showMenu() }
                        .buttonStyle(.borderedProminent)
                        .tint(HFTheme.accent)
                }

                if recorder.isRecording {
                    GlassCard {
                        HStack(spacing: 8) {
                            Image(systemName: "record.circle")
                                .foregroundStyle(HFTheme.danger)
                            Text("Recording — click and type in any app, then Stop & Save.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(HFTheme.textSecondary)
                        }
                    }
                }

                if let pending = pendingRecording {
                    saveRecordingCard(pending)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick add: click a named button")
                            .font(.system(size: 13, weight: .semibold))
                        TextField("Recipe name", text: $name)
                            .textFieldStyle(.roundedBorder)
                        TextField("Button / control name", text: $clickTarget)
                            .textFieldStyle(.roundedBorder)
                        Button("Add click recipe") {
                            guard !name.isEmpty, !clickTarget.isEmpty else { return }
                            store.add(
                                AXRecipe(
                                    name: name,
                                    steps: [AXRecipeStep(kind: .clickNamed, value: clickTarget)]
                                )
                            )
                            name = ""
                        }
                        .buttonStyle(.bordered)
                        .disabled(name.isEmpty || clickTarget.isEmpty)
                    }
                }

                ForEach(store.recipes) { recipe in
                    recipeRow(recipe)
                }
            }
            .padding(24)
        }
    }

    private func saveRecordingCard(_ pending: AXRecipe) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Save recorded recipe")
                    .font(.system(size: 13, weight: .semibold))
                TextField("Recipe name", text: $recordingName)
                    .textFieldStyle(.roundedBorder)
                // `pending.steps` was mapped 1:1 (same order, same count) from
                // `recorder.draftSteps` when the recording stopped.
                ForEach(Array(pending.steps.enumerated()), id: \.element.id) { index, step in
                    let isFragile = recorder.draftSteps.indices.contains(index)
                        && recorder.draftSteps[index].isFragile
                    HStack(spacing: 6) {
                        if isFragile {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(HFTheme.warning)
                                .help("No AX label found — recorded by role only, may not replay reliably.")
                        }
                        Text("\(step.kind.rawValue): \(step.value)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(HFTheme.textTertiary)
                    }
                }
                if !pending.bundleID.isEmpty {
                    Text("Scoped to \(pending.bundleID)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HFTheme.textTertiary)
                }
                HStack {
                    Button("Discard") { pendingRecording = nil }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Save Recipe") {
                        var r = pending
                        r.name = recordingName.isEmpty ? pending.name : recordingName
                        store.add(r)
                        pendingRecording = nil
                        Banner.show("Recipe saved", subtitle: r.name, style: .success)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HFTheme.accent)
                }
            }
        }
    }

    private func recipeRow(_ recipe: AXRecipe) -> some View {
        GlassCard(padding: 12) {
            HStack {
                Image(systemName: recipe.symbol)
                    .foregroundStyle(HFTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(
                        recipe.steps.map { "\($0.kind.rawValue):\($0.value)" }
                            .joined(separator: " → ")
                    )
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HFTheme.textTertiary)
                    .lineLimit(2)
                    if !recipe.bundleID.isEmpty {
                        Text(recipe.bundleID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(HFTheme.textTertiary)
                    }
                }
                Spacer()
                Button("Run") { store.run(recipe) }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(HFTheme.accent)
                Button(role: .destructive) {
                    store.delete(recipe)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(HFTheme.danger.opacity(0.8))
            }
        }
    }
}
