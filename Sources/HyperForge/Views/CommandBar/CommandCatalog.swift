// CommandCatalog.swift
// Aggregates apps, snippets, recipes, Shortcuts, and Hyper actions into the
// command-bar's fuzzy-searchable corpus.

import AppKit
import Foundation

@MainActor
enum CommandCatalog {
    static func allEntries() -> [CommandResult] {
        var items: [CommandResult] = []

        for slot in HyperAppSlotStore.snapshotSlots() {
            items.append(
                CommandResult(
                    title: slot.displayName,
                    subtitle: "Hyper + \(slot.digit)",
                    icon: slot.symbol,
                    kind: .app
                ) {
                    Task { @MainActor in
                        HyperAppSlotStore.shared.launch(actionID: slot.actionID)
                    }
                }
            )
        }

        for snippet in SnippetStore.shared.snippets where snippet.isEnabled {
            let preview = snippet.expansion
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(40)
            items.append(
                CommandResult(
                    title: snippet.trigger,
                    subtitle: preview.isEmpty ? "(empty)" : String(preview),
                    icon: "text.badge.plus",
                    kind: .snippet
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet.expansion, forType: .string)
                    Banner.show(
                        "Copied snippet",
                        subtitle: snippet.trigger,
                        style: .success,
                        symbol: "doc.on.clipboard"
                    )
                }
            )
        }

        for recipe in AXRecipeStore.shared.recipes where recipe.isEnabled {
            let scope = recipe.bundleID.isEmpty ? "Any app" : recipe.bundleID
            items.append(
                CommandResult(
                    title: recipe.name,
                    subtitle: "\(scope) · \(recipe.steps.count) step\(recipe.steps.count == 1 ? "" : "s")",
                    icon: recipe.symbol,
                    kind: .recipe
                ) {
                    Task { @MainActor in
                        AXRecipeStore.shared.run(recipe)
                    }
                }
            )
        }

        for layout in ProfileStore.shared.activeProfile.layouts {
            items.append(
                CommandResult(
                    title: layout.name,
                    subtitle: "\(layout.windows.count) window\(layout.windows.count == 1 ? "" : "s")",
                    icon: "rectangle.3.group",
                    kind: .workspace
                ) {
                    Task { @MainActor in
                        ProfileStore.shared.restoreLayout(layout)
                    }
                }
            )
        }

        for script in ScriptStore.shared.scripts where script.isEnabled {
            let scope = script.bundleID.isEmpty ? "Any app" : script.bundleID
            items.append(
                CommandResult(
                    title: script.name,
                    subtitle: scope,
                    icon: script.symbol,
                    kind: .script
                ) {
                    Task { @MainActor in
                        ScriptStore.shared.run(script)
                    }
                }
            )
        }

        for name in ShortcutsService.cachedOrRefreshingNames() {
            items.append(
                CommandResult(
                    title: name,
                    subtitle: "macOS Shortcut",
                    icon: "bolt.fill",
                    kind: .shortcut
                ) {
                    ShortcutsService.run(name: name)
                }
            )
        }

        for action in ActionCatalog.resolvedDefaults() {
            items.append(
                CommandResult(
                    title: action.title,
                    subtitle: action.shortcutDisplay,
                    icon: action.symbol,
                    kind: .action
                ) {
                    Task { @MainActor in
                        HyperKeyActions.perform(actionID: action.id)
                    }
                }
            )
        }

        return items
    }
}
