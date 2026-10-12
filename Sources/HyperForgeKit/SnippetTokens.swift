// SnippetTokens.swift
// Pure {{env:NAME}} substitution. Callers pass the environment in.

import Foundation

public enum SnippetTokens {
    /// Replace `{{env:NAME}}` from `environment`.
    ///
    /// NAME must match `[A-Za-z_][A-Za-z0-9_]*`. An unset or illegal name is
    /// left unchanged so a typo stays visible. The value is inserted literally
    /// and is not scanned for further tokens.
    public static func resolveEnv(_ template: String, environment: [String: String]) -> String {
        guard template.contains("{{env:") else { return template }
        guard let re = try? NSRegularExpression(
            pattern: #"\{\{env:([A-Za-z_][A-Za-z0-9_]*)\}\}"#,
            options: []
        ) else {
            return template
        }
        let ns = template as NSString
        let matches = re.matches(in: template, options: [], range: NSRange(location: 0, length: ns.length))
        var out = template
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range, in: out),
                  let nameRange = Range(match.range(at: 1), in: out)
            else { continue }
            let name = String(out[nameRange])
            guard let value = environment[name] else { continue }
            out.replaceSubrange(fullRange, with: value)
        }
        return out
    }
}
