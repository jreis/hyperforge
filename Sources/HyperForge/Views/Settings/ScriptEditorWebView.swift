// ScriptEditorWebView.swift
// WKWebView wrapper around the CodeMirror + vim-mode editor bundled under
// Resources/ScriptEditor (built from WebAssets/script-editor — see build-script-editor.sh).
// Edits flow JS -> Swift live via a WKScriptMessageHandler; Swift only pushes content
// back into the page when `reloadToken` changes (i.e. the user switched which script
// is loaded), so it never fights the live typing session or cursor position.

import SwiftUI
import WebKit

struct ScriptEditorWebView: NSViewRepresentable {
    @Binding var source: String
    var vimEnabled: Bool
    var reloadToken: Int
    /// Bumped to take first responder and focus CodeMirror (pencil / double-click).
    var focusToken: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(source: $source)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "hfEditor")
        controller.add(context.coordinator, name: "hfEditorFocus")
        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = NSColor(calibratedRed: 0x10 / 255, green: 0x14 / 255, blue: 0x1C / 255, alpha: 1)

        context.coordinator.pendingInitialText = source
        context.coordinator.pendingVimEnabled = vimEnabled
        context.coordinator.lastReloadToken = reloadToken

        if let url = Bundle.module.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "ScriptEditor"
        ) {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
            if context.coordinator.isReady {
                context.coordinator.focusEditor(in: webView)
            } else {
                context.coordinator.pendingFocus = true
            }
        }
        guard context.coordinator.isReady else { return }
        if reloadToken != context.coordinator.lastReloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.setContent(source, in: webView)
        }
        if vimEnabled != context.coordinator.lastVimEnabled {
            context.coordinator.lastVimEnabled = vimEnabled
            webView.evaluateJavaScript("window.hfEditor.setVimEnabled(\(vimEnabled));")
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // Belt-and-suspenders: if this view goes away without a JS blur event
        // (e.g. the user navigates off the Scripts sidebar item mid-edit), don't
        // leave Escape permanently swallowed app-wide.
        EscapeCoordinator.shared.webEditorHasFocus = false
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let source: Binding<String>
        var pendingInitialText = ""
        var pendingVimEnabled = true
        var lastReloadToken = -1
        var lastVimEnabled = true
        var lastFocusToken = 0
        var pendingFocus = false
        var isReady = false

        init(source: Binding<String>) {
            self.source = source
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "hfEditor":
                guard let text = message.body as? String, source.wrappedValue != text else { return }
                source.wrappedValue = text
            case "hfEditorFocus":
                EscapeCoordinator.shared.webEditorHasFocus = (message.body as? Bool) ?? false
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            lastVimEnabled = pendingVimEnabled
            let literal = Self.jsStringLiteral(pendingInitialText)
            webView.evaluateJavaScript("window.hfEditor.init(\(literal), \(pendingVimEnabled));")
            if pendingFocus {
                pendingFocus = false
                focusEditor(in: webView)
            }
        }

        func setContent(_ text: String, in webView: WKWebView) {
            let literal = Self.jsStringLiteral(text)
            webView.evaluateJavaScript("window.hfEditor.setContent(\(literal));")
        }

        func focusEditor(in webView: WKWebView) {
            // After scroll + setContent, the WebView must be first responder
            // before CodeMirror can show a caret.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                webView.window?.makeFirstResponder(webView)
                webView.evaluateJavaScript(
                    "window.hfEditor && window.hfEditor.focus && window.hfEditor.focus();"
                )
            }
        }

        /// JSON-encodes so the text is a safe, valid JS string literal regardless of quotes/newlines.
        static func jsStringLiteral(_ s: String) -> String {
            guard let data = try? JSONEncoder().encode(s),
                  let literal = String(data: data, encoding: .utf8)
            else { return "\"\"" }
            return literal
        }
    }
}
