// Completions for the HF script bridge (mirrors HFScriptBridgeExporting in ScriptStore.swift).

const HF_METHODS = [
  {
    name: "snap",
    apply: 'snap("left")',
    detail: "(position)",
    info: 'Snap the front window. Position: left, right, top, bottom, max, center, centerNice, thirdLeft, thirdCenter, thirdRight, twoThirdsLeft, twoThirdsRight, almostMax.',
  },
  {
    name: "notify",
    apply: "notify(",
    detail: "(message)",
    info: "Show a HyperForge banner.",
  },
  {
    name: "log",
    apply: "log(",
    detail: "(message)",
    info: "Append a line to script output (Settings → Scripts).",
  },
  {
    name: "clipboardGet",
    apply: "clipboardGet()",
    detail: "()",
    info: "Return the current clipboard text, or null.",
  },
  {
    name: "clipboardSet",
    apply: "clipboardSet(",
    detail: "(text)",
    info: "Replace the clipboard with text.",
  },
  {
    name: "pasteText",
    apply: "pasteText(",
    detail: "(text)",
    info: "Type text into the front app.",
  },
  {
    name: "pressKey",
    apply: "pressKey(",
    detail: "(chord)",
    info: 'Send a key chord, e.g. "cmd+s" or "cmd+shift+4".',
  },
  {
    name: "runShortcut",
    apply: "runShortcut(",
    detail: "(name)",
    info: "Run a macOS Shortcut by name.",
  },
  {
    name: "launchApp",
    apply: "launchApp(",
    detail: "(bundleID)",
    info: 'Launch, focus, or minimize an app, e.g. "com.apple.Notes".',
  },
  {
    name: "sleep",
    apply: "sleep(",
    detail: "(ms)",
    info: "Pause this script (milliseconds). Does not block the UI.",
  },
];

function methodOptions() {
  return HF_METHODS.map((m) => ({
    label: m.name,
    type: "function",
    apply: m.apply,
    detail: m.detail,
    info: m.info,
    boost: 99,
  }));
}

/** CodeMirror completion source: typing `HF.` lists every bridge method. */
export function hfCompletions(context) {
  const afterDot = context.matchBefore(/HF\.\w*/);
  if (afterDot) {
    return {
      from: afterDot.from + 3,
      options: methodOptions(),
      validFor: /^\w*$/,
    };
  }
  // Ctrl-Space on `HF` still lists methods (inserts `HF.snap(...)` etc.).
  const bare = context.matchBefore(/HF\w*/);
  if (!bare || (bare.from === bare.to && !context.explicit)) return null;
  if (bare.text !== "HF" && !bare.text.startsWith("HF")) return null;
  if (!context.explicit && bare.text !== "HF") return null;
  return {
    from: bare.from,
    options: HF_METHODS.map((m) => ({
      label: "HF." + m.name,
      type: "function",
      apply: "HF." + m.apply,
      detail: m.detail,
      info: m.info,
      boost: 99,
    })),
    validFor: /^HF\.?\w*$/,
  };
}
