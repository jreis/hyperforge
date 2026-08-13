// URLTriggerService.swift
// Handles `hyperforge://` URLs so Shortcuts, scripts, cron, or other apps can
// trigger any catalog action, script, recipe, or saved layout from outside the app —
// delivered to the already-running instance, no relaunch.
//
//   hyperforge://run?kind=action&id=sys-scripts
//   hyperforge://run?kind=script&id=<script name>
//   hyperforge://run?kind=recipe&id=<recipe name>
//   hyperforge://run?kind=layout&id=<layout name>

import Foundation

@MainActor
enum URLTriggerService {
    static func handle(_ url: URL) {
        guard url.scheme == "hyperforge", url.host == "run" else {
            HyperLog.event("hyperforge:// ignored (not a run URL): \(url.absoluteString)")
            return
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first(where: { $0.name == name })?.value
        }
        guard let kind = value("kind"), let id = value("id"), !id.isEmpty else {
            HyperLog.event("hyperforge:// trigger missing kind/id: \(url.absoluteString)")
            return
        }

        switch kind {
        case "action":
            HyperKeyActions.perform(actionID: id)
        case "script":
            ScriptStore.shared.runByName(id)
        case "recipe":
            AXRecipeStore.shared.runByName(id)
        case "layout":
            ProfileStore.shared.restoreLayoutByName(id)
        default:
            HyperLog.event("hyperforge:// unknown kind=\(kind)")
            Banner.show("Unknown trigger kind", subtitle: kind, style: .warning)
        }
    }
}
