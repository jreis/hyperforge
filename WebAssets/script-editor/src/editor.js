// editor.js — bundled (via esbuild, see ../package.json) into
// Sources/HyperForge/Resources/ScriptEditor/editor.bundle.js and loaded by
// index.html inside a WKWebView. Bridges to Swift through:
//   - window.webkit.messageHandlers.hfEditor.postMessage(text)       (JS -> Swift, on every edit)
//   - window.webkit.messageHandlers.hfEditorFocus.postMessage(bool)  (JS -> Swift, on focus/blur —
//     lets EscapeCoordinator step aside so vim's insert-mode Esc isn't stolen by window-hide)
//   - window.hfEditor.init/setContent/setVimEnabled/getContent       (Swift -> JS)
import { EditorState } from "@codemirror/state";
import {
  EditorView,
  keymap,
  lineNumbers,
  highlightActiveLine,
  highlightActiveLineGutter,
} from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { javascript } from "@codemirror/lang-javascript";
import { bracketMatching, indentOnInput, syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language";
import { vim } from "@replit/codemirror-vim";

const darkTheme = EditorView.theme(
  {
    "&": {
      backgroundColor: "#10141c",
      color: "#e7e9ee",
      height: "100%",
      fontSize: "12px",
    },
    ".cm-scroller": { overflow: "auto" },
    ".cm-content": {
      caretColor: "#7dd3fc",
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
      padding: "8px 0",
    },
    ".cm-gutters": {
      backgroundColor: "#0b0d12",
      color: "#5a6272",
      border: "none",
    },
    ".cm-activeLine": { backgroundColor: "rgba(255,255,255,0.04)" },
    ".cm-activeLineGutter": { backgroundColor: "rgba(255,255,255,0.06)" },
    "&.cm-focused .cm-cursor": { borderLeftColor: "#7dd3fc" },
    "&.cm-focused .cm-selectionBackground, ::selection": {
      backgroundColor: "rgba(125,211,252,0.25)",
    },
    ".cm-panels": { backgroundColor: "#161b26", color: "#e7e9ee" },
    ".cm-panels input": { color: "#e7e9ee" },
  },
  { dark: true }
);

let notifyTimer = null;
function scheduleNotify(view) {
  clearTimeout(notifyTimer);
  // Debounce so a fast typist doesn't flood the native message handler.
  notifyTimer = setTimeout(() => {
    const text = view.state.doc.toString();
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.hfEditor) {
      window.webkit.messageHandlers.hfEditor.postMessage(text);
    }
  }, 150);
}

const changeNotifier = EditorView.updateListener.of((update) => {
  if (update.docChanged) scheduleNotify(update.view);
});

function notifyFocus(hasFocus) {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.hfEditorFocus) {
    window.webkit.messageHandlers.hfEditorFocus.postMessage(hasFocus);
  }
}

const focusNotifier = EditorView.domEventHandlers({
  focus: () => notifyFocus(true),
  blur: () => notifyFocus(false),
});

function buildExtensions(vimEnabled) {
  const ext = [
    lineNumbers(),
    highlightActiveLineGutter(),
    highlightActiveLine(),
    history(),
    bracketMatching(),
    indentOnInput(),
    syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
    javascript(),
    EditorView.lineWrapping,
    darkTheme,
    changeNotifier,
    focusNotifier,
    keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
  ];
  // vim() must come first so it gets first crack at keydown events.
  if (vimEnabled) ext.unshift(vim());
  return ext;
}

let view = null;

function createEditor(initialText, vimEnabled) {
  const parent = document.getElementById("editor");
  const state = EditorState.create({
    doc: initialText || "",
    extensions: buildExtensions(vimEnabled),
  });
  view = new EditorView({ state, parent });
}

window.hfEditor = {
  init(initialText, vimEnabled) {
    createEditor(initialText, !!vimEnabled);
  },
  setContent(text) {
    if (!view) return;
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: text || "" },
    });
  },
  getContent() {
    return view ? view.state.doc.toString() : "";
  },
  setVimEnabled(enabled) {
    if (!view) return;
    const text = view.state.doc.toString();
    const selection = view.state.selection;
    view.destroy();
    createEditor(text, enabled);
    // Best-effort restore of cursor position across the mode switch.
    try {
      view.dispatch({ selection });
    } catch {
      // Selection may be out of range if content changed; ignore.
    }
  },
  focus() {
    if (view) view.focus();
  },
};
