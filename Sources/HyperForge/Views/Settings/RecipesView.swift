// RecipesView.swift
// AX UI automation playbooks (UIA spiritual successor).

import SwiftUI

struct RecipesView: View {
    @ObservedObject private var store = AXRecipeStore.shared
    @State private var name = ""
    @State private var clickTarget = "OK"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AX Recipes")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(HFTheme.textPrimary)
                        Text("Multi-step Accessibility automation — click named UI, keys, paste.")
                            .font(.system(size: 13))
                            .foregroundStyle(HFTheme.textSecondary)
                    }
                    Spacer()
                    Button("Run menu…") { store.showMenu() }
                        .buttonStyle(.borderedProminent)
                        .tint(HFTheme.accent)
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
            .padding(24)
        }
    }
}
