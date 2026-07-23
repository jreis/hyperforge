# Private work modules

Put **employer-specific** automation here. This folder’s `work.ahk` is gitignored.

## Setup

```text
copy work.example.ahk work.ahk
; edit work.ahk — Splunk, AD, SNOW, internal URLs, etc.
```

`HyperForge.ahk` loads `work\work.ahk` automatically if it exists (`#Include *i`).

## Rules

- No secrets in source — use Windows Credential Manager (`CredRead`) like your original script.
- Do not commit `work.ahk` or real hostnames/emails to a public repo.
- Prefer reading paths from `config.ini` or a private `work.ini`.
