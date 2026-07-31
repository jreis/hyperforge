#!/usr/bin/env python3
"""Enable / update HyperForge Karabiner complex_modifications rules.

Copies are not enough: assets only show under “Add predefined rule”.
This script upserts rules onto the selected profile in karabiner.json:

  • Removes existing HyperForge pack rules (by description alias or content)
  • Inserts the current pack at the front
  • Idempotent — re-running updates instead of duplicating

Usage:
  karabiner-enable-pack.py <karabiner.json> <assets_dir>
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

# Order matters for the final rule list (front = higher priority in practice).
PACK_FILES = (
    "hyperforge_caps_to_f18.json",
    "hyperforge_help_f19.json",
    "hyperforge_dashboard_f20.json",
)

# Every description HyperForge has ever used (install, Doctor, manual enables).
# Matching any of these marks a rule as ours and eligible for replace/remove.
LEGACY_DESCRIPTIONS = {
    "Caps Lock to F18 (Hyper trigger)",
    "Caps Lock to F18 (Hyper trigger, alone = Escape)",
    "HyperForge: Caps Lock to F18 (Hyper trigger, alone = Escape)",
    "Hyper (⌘⌃⌥⇧) + / → F19 (HyperForge cheat sheet)",
    "Hyper (⌘⌃⌥⇧) + / or ` → F19 (cheat sheet)",
    "HyperForge: Hyper + / or ` → F19 (cheat sheet)",
    "Hyper (⌘⌃⌥⇧) + , → F20 (HyperForge dashboard)",
    "Hyper (⌘⌃⌥⇧) + , → F20 (show dashboard)",
    "HyperForge: Hyper + , → F20 (dashboard)",
}


def _manip_blob(rule: dict) -> str:
    return json.dumps(rule.get("manipulators") or [], sort_keys=True).lower()


def rule_family(rule: dict) -> str | None:
    """Classify a rule as a HyperForge pack family, or None if unrelated."""
    desc = (rule.get("description") or "").strip()
    lower = desc.lower()
    blob = _manip_blob(rule)

    if desc in LEGACY_DESCRIPTIONS or lower.startswith("hyperforge"):
        # Prefer content when possible; fall through to heuristics.
        pass

    # Description heuristics (covers renames)
    if "f18" in lower and "caps" in lower:
        return "caps_f18"
    if "f19" in lower and any(
        x in lower for x in ("/", "slash", "help", "cheat", "grave", "`", "keybinding")
    ):
        return "help_f19"
    if "f20" in lower and any(
        x in lower for x in (",", "comma", "dashboard", "show dashboard")
    ):
        return "dashboard_f20"

    # Content fingerprints (duplicates with renamed descriptions)
    compact = blob.replace(" ", "")
    if "caps_lock" in compact and '"key_code":"f18"' in compact:
        return "caps_f18"
    if '"key_code":"f19"' in compact and ("slash" in compact or "grave" in compact):
        return "help_f19"
    if '"key_code":"f20"' in compact and "comma" in compact:
        return "dashboard_f20"

    if desc in LEGACY_DESCRIPTIONS or lower.startswith("hyperforge"):
        return "hyperforge_other"

    return None


def load_pack_rules(asset_dir: Path) -> list[dict]:
    rules: list[dict] = []
    for name in PACK_FILES:
        path = asset_dir / name
        if not path.is_file():
            continue
        with open(path, encoding="utf-8") as f:
            asset = json.load(f)
        for rule in asset.get("rules") or []:
            if isinstance(rule, dict) and rule.get("manipulators"):
                rules.append(rule)
    return rules


def upsert(config_path: Path, asset_dir: Path) -> tuple[int, int, str]:
    if not config_path.is_file():
        raise SystemExit(f"missing config: {config_path}")

    pack = load_pack_rules(asset_dir)
    if not pack:
        raise SystemExit(f"no pack rules found in {asset_dir}")

    backup = config_path.with_suffix(config_path.suffix + ".hyperforge-backup")
    if not backup.exists():
        shutil.copy2(config_path, backup)

    with open(config_path, encoding="utf-8") as f:
        root = json.load(f)

    profiles = root.get("profiles") or []
    if not profiles:
        raise SystemExit("karabiner.json has no profiles")

    idx = next((i for i, p in enumerate(profiles) if p.get("selected")), 0)
    profile = profiles[idx]
    cm = profile.setdefault("complex_modifications", {})
    existing = list(cm.get("rules") or [])

    pack_families = {rule_family(r) for r in pack}
    pack_families.discard(None)

    kept: list[dict] = []
    removed = 0
    for rule in existing:
        fam = rule_family(rule)
        if fam is not None and (fam in pack_families or fam == "hyperforge_other"):
            removed += 1
            continue
        kept.append(rule)

    # Pack rules first (stable order), then everything else.
    cm["rules"] = pack + kept
    profiles[idx] = profile
    root["profiles"] = profiles

    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(root, f, indent=4)
        f.write("\n")

    name = profile.get("name") or "Default"
    return len(pack), removed, str(name)


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        raise SystemExit(2)
    written, removed, profile = upsert(Path(sys.argv[1]), Path(sys.argv[2]))
    if removed:
        print(
            f"updated {written} HyperForge rule(s) on profile {profile!r} "
            f"(replaced {removed} old/duplicate)"
        )
    else:
        print(f"enabled {written} HyperForge rule(s) on profile {profile!r}")


if __name__ == "__main__":
    main()
