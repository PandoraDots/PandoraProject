#!/usr/bin/env python3
"""Repair managed TOML keys, preserving unrelated settings and comments."""
import datetime
import json
import os
import pathlib
import re
import sys
import tomllib


def set_key(text, section, key, value):
    lines = text.splitlines(keepends=True)
    header = re.compile(r"^\s*\[" + re.escape(section) + r"\]\s*(?:#.*)?$")
    start = next((i for i, line in enumerate(lines) if header.match(line.rstrip())), None)
    assignment = f"{key} = {json.dumps(value)}\n"
    if start is None:
        return text.rstrip() + f"\n\n[{section}]\n" + assignment
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^\s*\[", lines[i])), len(lines))
    _replace_assignment(lines, start, end, key, assignment)
    return "".join(lines)


def _replace_assignment(lines, start, end, key, assignment):
    indices = [i for i in range(start + 1, end) if re.match(r"^\s*" + re.escape(key) + r"\s*=", lines[i])]
    if indices:
        i = indices[0]
        stop = i + 1
        if "[" in lines[i].split("=", 1)[1] and "]" not in lines[i].split("=", 1)[1]:
            while stop < end and "]" not in lines[stop]:
                stop += 1
            stop += 1
        lines[i:stop] = [assignment]
        return end + (1 - (stop - i))
    lines.insert(start + 1, assignment)
    return end + 1


def _array_table_ranges(lines, name):
    header = re.compile(r"^\s*\[\[" + re.escape(name) + r"\]\]\s*(?:#.*)?$")
    starts = [i for i, line in enumerate(lines) if header.match(line.rstrip())]
    ranges = []
    for start in starts:
        end = next((j for j in range(start + 1, len(lines)) if re.match(r"^\s*\[", lines[j])), len(lines))
        ranges.append((start, end))
    return ranges


def upsert_selectorless_window_rule(text, mapping):
    """Keep a first-match window_rule with no match.* so later rules can override."""
    lines = text.splitlines(keepends=True)
    ranges = _array_table_ranges(lines, "window_rule")
    target = next(
        (
            (start, end)
            for start, end in ranges
            if not any(re.match(r"^\s*match\.", lines[i]) for i in range(start + 1, end))
        ),
        None,
    )
    if target is None:
        block = ["\n", "# Pandora visual: Caelestia window chrome (blur + opacity).\n", "[[window_rule]]\n"]
        for key, value in mapping.items():
            block.append(f"{key} = {json.dumps(value)}\n")
        insert_at = ranges[0][0] if ranges else len(lines)
        lines[insert_at:insert_at] = block
        return "".join(lines)
    start, end = target
    for key, value in mapping.items():
        end = _replace_assignment(lines, start, end, key, f"{key} = {json.dumps(value)}\n")
    return "".join(lines)


# Caelestia hypr/variables.lua + decoration.lua + animations.lua + rules.lua.
# Colors (default red/terracotta scheme) are intentionally omitted.
#
# Hyprland animation speed is in deciseconds (1 ds = 100 ms).
#   windowsIn/workspaces speed 5 → 500 ms
#   windowsOut speed 3 → 300 ms
#   windowsMove/border/fade speed 6 → 600 ms
#   specialWorkspace speed 4 → 400 ms
# Bezier control points come from caelestia animations.lua (hl.curve).
# Layer animations stay OFF: Noctalia owns panel motion (docs recommend no_anim).
# Custom GLSL shaders stay OFF: Caelestia does not ship window shaders.
CAELESTIA_VISUAL = (
    ("appearance", "border_width", 1),
    ("appearance", "corner_radius", 15),
    ("appearance.blur", "enabled", True),
    ("appearance.blur", "optimized", True),
    ("appearance.blur", "passes", 2),
    ("appearance.blur", "radius", 8),
    # Hyprland decoration:blur defaults (Caelestia does not override these).
    ("appearance.blur", "noise", 0.0117),
    ("appearance.blur", "brightness", 1.0),
    ("appearance.blur", "contrast", 0.8916),
    ("appearance.blur", "saturation", 1.0),
    ("appearance.shadow", "enabled", True),
    # range=15 + render_power=4 → compact falloff; softness≈12 is closer than 15.
    ("appearance.shadow", "softness", 12),
    ("appearance.shadow", "offset_x", 0),
    ("appearance.shadow", "offset_y", 0),
    # Umbriel has a single gap; Caelestia gaps_in=5 / gaps_out=10 → use gaps_in.
    ("layout", "gap", 5),
    ("animation", "enabled", True),
    ("animation.beziers", "emphasizedDecel", [0.05, 0.7, 0.1, 1.0]),
    ("animation.beziers", "emphasizedAccel", [0.3, 0.0, 0.8, 0.15]),
    ("animation.beziers", "standard", [0.2, 0.0, 0.0, 1.0]),
    ("animation.beziers", "specialWorkSwitch", [0.05, 0.7, 0.1, 1.0]),
    ("animation.windows_in", "enabled", True),
    ("animation.windows_in", "duration_ms", 500),
    ("animation.windows_in", "curve", "emphasizedDecel"),
    # Caelestia leaves windowsIn style unset; Umbriel requires one — popin is closest.
    ("animation.windows_in", "style", "popin"),
    ("animation.windows_in", "scale", 0.85),
    ("animation.windows_out", "enabled", True),
    ("animation.windows_out", "duration_ms", 300),
    ("animation.windows_out", "curve", "emphasizedAccel"),
    ("animation.windows_out", "style", "fade"),
    ("animation.windows_move", "enabled", True),
    ("animation.windows_move", "duration_ms", 600),
    ("animation.windows_move", "curve", "standard"),
    ("animation.workspaces", "enabled", True),
    ("animation.workspaces", "duration_ms", 500),
    ("animation.workspaces", "curve", "standard"),
    ("animation.border", "enabled", True),
    ("animation.border", "duration_ms", 600),
    ("animation.border", "curve", "standard"),
    # specialWorkspace ≈ scratchpad (no slidefadevert in Umbriel).
    ("animation.scratchpad", "enabled", True),
    ("animation.scratchpad", "duration_ms", 400),
    ("animation.scratchpad", "curve", "specialWorkSwitch"),
    ("animation.layers", "enabled", False),
)

CAELESTIA_WINDOW_RULE = {
    "opacity": 0.95,
    "blur": True,
    "blur_popups": True,
    "blur_optimized": False,
}

# Named scratchpads replace the implicit "default"; general keeps Mod+Space.
# Firefox is a plain spawn (--new-window), not a scratchpad.
PANDORA_SCRATCHPADS = ("general", "concord", "sung", "whatsapp")

# (app_id regex, scratchpad name) — open maximized like Concord's full float.
PANDORA_SCRATCH_RULES = (
    ("^concord$", "concord"),
    ("^sung$", "sung"),
    # ZapZap's Wayland app_id is reverse-DNS; use [.] (TOML-safe) not \.
    ("^com[.]rtosta[.]zapzap$", "whatsapp"),
)

# Drop leftover browser/firefox scratchpad wiring from earlier installs.
PANDORA_REMOVE_SCRATCHPADS = ("browser",)
PANDORA_REMOVE_SCRATCH_PADS_FROM_RULES = ("browser",)


def _helper_bin(name):
    home = pathlib.Path.home()
    # Prefer the user copy so live fixes apply without root; installer still
    # deploys /usr/local/bin for fresh systems.
    for candidate in (
        home / ".local/bin" / name,
        pathlib.Path("/usr/local/bin") / name,
    ):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return str(home / ".local/bin" / name)


def _abs_cmd(name):
    home = pathlib.Path.home()
    for candidate in (
        pathlib.Path("/usr/bin") / name,
        pathlib.Path("/usr/local/bin") / name,
        home / ".local/bin" / name,
    ):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return name


def pandora_keybinds():
    scratch = _helper_bin("pandora-scratch-toggle")
    terminal = _helper_bin("pandora-terminal")
    sung = _abs_cmd("sung")
    zapzap = _abs_cmd("zapzap")
    concord = _abs_cmd("concord")
    kitty = _abs_cmd("kitty")
    firefox = _abs_cmd("firefox")
    cursor = _abs_cmd("cursor")
    binds = {
        "Mod+C": f'"spawn:{cursor}"',
        "Mod+D": f'"spawn:{scratch} concord concord -- {kitty} --app-id=concord -e {concord}"',
        "Mod+G": f'"spawn:{scratch} sung sung -- {sung}"',
        "Mod+W": f'"spawn:{firefox} --new-window"',
        "Mod+A": f'"spawn:{scratch} whatsapp com.rtosta.zapzap -- {zapzap}"',
        "Mod+T": f'"spawn:{terminal}"',
        "Mod+Return": f'"spawn:{terminal}"',
        "Mod+Alt+R": '"window-toggle-floating"',
        "Mod+Alt+F": '"window-toggle-maximize-to-edges"',
        "Mod+F": '"window-toggle-fullscreen"',
        "Mod+O": '{ action = "overview-toggle", repeat = false }',
        "Mod+MouseBack": '{ action = "overview-toggle", repeat = false }',
        "Mod+MouseForward": '{ action = "overview-toggle", repeat = false }',
        "Mod+WheelUp": '{ action = "workspace-previous", cooldown_ms = 150 }',
        "Mod+WheelDown": '{ action = "workspace-next", cooldown_ms = 150 }',
        "Mod+Space": '"scratchpad-toggle:general"',
        "Mod+Shift+Space": '"window-move-to-scratchpad:general"',
        "Mod+Ctrl+Space": '"window-restore-from-scratchpad:general"',
        "Mod+Tab": '"scratchpad-focus-next:general"',
        # Noctalia capture / clipboard / emoji
        "Print": '"spawn:noctalia msg screenshot-region"',
        "Mod+Print": '"spawn:noctalia msg screenshot-fullscreen"',
        "Mod+V": '"spawn:noctalia msg panel-toggle clipboard"',
        "Mod+Period": '"spawn:noctalia msg panel-toggle launcher /emo"',
        # Displaced example binds → free chords
        "Mod+Alt+H": '"window-cycle-height"',
        "Mod+Alt+Shift+H": '"window-cycle-height-back"',
        "Mod+Alt+C": '"column-center"',
        "Mod+Alt+Period": '"window-consume-right"',
        # Replaced by Mod+Alt+F / Mod+Alt+R / Wheel workspace binds.
        "Mod+M": None,
        "Mod+Ctrl+F": None,
    }
    for n in range(1, 10):
        binds[f"Mod+Alt+{n}"] = f'"window-move-to-workspace:{n}"'
    return binds


def set_keybind(text, chord, action_toml):
    """Set or remove a chord inside [keybinds]. action_toml=None deletes it."""
    lines = text.splitlines(keepends=True)
    header = re.compile(r"^\s*\[keybinds\]\s*(?:#.*)?$")
    start = next((i for i, line in enumerate(lines) if header.match(line.rstrip())), None)
    if start is None:
        if action_toml is None:
            return text
        return text.rstrip() + f'\n\n[keybinds]\n"{chord}" = {action_toml}\n'
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^\s*\[", lines[i])), len(lines))
    chord_re = re.compile(r'^\s*"' + re.escape(chord) + r'"\s*=')
    indices = [i for i in range(start + 1, end) if chord_re.match(lines[i])]
    if action_toml is None:
        for i in reversed(indices):
            del lines[i]
        return "".join(lines)
    assignment = f'"{chord}" = {action_toml}\n'
    if indices:
        lines[indices[0]] = assignment
        for i in reversed(indices[1:]):
            del lines[i]
    else:
        lines.insert(end, assignment)
    return "".join(lines)


def ensure_scratchpads(text, names):
    lines = text.splitlines(keepends=True)
    existing = set()
    for start, end in _array_table_ranges(lines, "scratchpad"):
        for i in range(start + 1, end):
            m = re.match(r'^\s*name\s*=\s*"([^"]+)"', lines[i])
            if m:
                existing.add(m.group(1))
    missing = [n for n in names if n not in existing]
    if not missing:
        return text
    block = ["\n"]
    for name in missing:
        block.append("[[scratchpad]]\n")
        block.append(f'name = "{name}"\n')
        block.append("\n")
    # Insert before [keybinds] when present so scratchpads stay discoverable.
    keybinds = next((i for i, line in enumerate(lines) if re.match(r"^\s*\[keybinds\]", line)), None)
    insert_at = keybinds if keybinds is not None else len(lines)
    lines[insert_at:insert_at] = block
    return "".join(lines)


def remove_scratchpads(text, names):
    drop = set(names)
    lines = text.splitlines(keepends=True)
    ranges = _array_table_ranges(lines, "scratchpad")
    for start, end in reversed(ranges):
        body = "".join(lines[start:end])
        if any(re.search(rf'(?m)^\s*name\s*=\s*"{re.escape(n)}"', body) for n in drop):
            del lines[start:end]
    return "".join(lines)


def ensure_scratch_window_rules(text, rules):
    """Replace Pandora scratchpad window rules with a clean, ordered block."""
    pads = [pad for _, pad in rules]
    text = remove_scratch_window_rules(text, pads)
    lines = text.splitlines(keepends=True)
    layer = next((i for i, line in enumerate(lines) if re.match(r"^\s*\[\[layer_rule\]\]", line)), None)
    insert_at = layer if layer is not None else len(lines)
    while insert_at > 0 and lines[insert_at - 1].strip() == "":
        insert_at -= 1
    block = ["\n"]
    for app_re, pad in rules:
        block.extend(
            [
                "\n",
                f"# Pandora scratchpad: {pad}\n",
                "[[window_rule]]\n",
                f'match.app_id = "{app_re}"\n',
                f'default_scratchpad = "{pad}"\n',
                "default_maximize = true\n",
            ]
        )
    lines[insert_at:insert_at] = block
    return "".join(lines)


def remove_scratch_window_rules(text, pads):
    drop = set(pads)
    lines = text.splitlines(keepends=True)
    ranges = _array_table_ranges(lines, "window_rule")
    for start, end in reversed(ranges):
        body = "".join(lines[start:end])
        if any(f'default_scratchpad = "{pad}"' in body for pad in drop):
            # Also drop the Pandora comment line immediately above, if present.
            cut = start
            if cut > 0 and "Pandora scratchpad" in lines[cut - 1]:
                cut -= 1
            del lines[cut:end]
    return "".join(lines)


def apply_pandora_keybinds(text):
    text = set_key(text, "input.focus", "follows_mouse", True)
    # Concord/Sung/ZapZap scratchpads: maximize to usable edges when shown.
    # (Per-window maximize is cleared on scratchpad entry; this re-applies it.)
    text = set_key(text, "animation.scratchpad", "maximize", True)
    text = remove_scratchpads(text, PANDORA_REMOVE_SCRATCHPADS)
    text = remove_scratch_window_rules(text, PANDORA_REMOVE_SCRATCH_PADS_FROM_RULES)
    text = ensure_scratchpads(text, PANDORA_SCRATCHPADS)
    text = ensure_scratch_window_rules(text, PANDORA_SCRATCH_RULES)
    for chord, action in pandora_keybinds().items():
        text = set_keybind(text, chord, action)
    return text




def repair(text, kind, value, *extra):
    if kind == "greeter":
        try:
            tomllib.loads(text)
        except tomllib.TOMLDecodeError:
            # Older installer split the upstream comment listing these sections.
            # Only repair that recognizable damage; unknown syntax errors fail safely.
            text = re.sub(r"(?m)^\[user\] default\s*$", "# [user] default", text)
            text = re.sub(r"(?m)^\[appearance\] (scheme,.*)$", r"# [appearance] \1", text)
            # These erroneous assignments were inserted into the introductory comment.
            prefix, sep, rest = text.partition("\n\n")
            if "# [session] default," in prefix:
                prefix = re.sub(r'(?m)^default = "[^"\n]*"\n?', '', prefix)
                text = prefix + sep + rest
            tomllib.loads(text)
        text = set_key(text, "user", "default", value)
        text = set_key(text, "session", "default", "Umbriel")
    elif kind == "drm":
        data = tomllib.loads(text)
        addresses = data.get("drm", {}).get("ignored_pci_addresses", [])
        if not isinstance(addresses, list):
            raise ValueError("drm.ignored_pci_addresses must be an array")
        text = set_key(text, "drm", "ignored_pci_addresses", list(dict.fromkeys([*addresses, value])))
    elif kind == "keyboard":
        # Umbriel [input.keyboard] — Brazilian ABNT2 by default.
        layout = value or "br"
        variant = extra[0] if extra else "abnt2"
        text = set_key(text, "input.keyboard", "layout", layout)
        text = set_key(text, "input.keyboard", "variant", variant)
    elif kind == "brightness-binds":
        # Enable documented Fn brightness/media binds from the Umbriel example.
        text = re.sub(
            r'(?m)^#\s*("XF86(?:MonBrightness(?:Down|Up)|Audio(?:RaiseVolume|LowerVolume|Mute|Play|Next|Prev))".*)$',
            r"\1",
            text,
        )
    elif kind == "visual":
        # Window chrome only: blur, opacity, shadows, rounding, gaps, animation timing.
        for section, key, setting in CAELESTIA_VISUAL:
            text = set_key(text, section, key, setting)
        text = upsert_selectorless_window_rule(text, CAELESTIA_WINDOW_RULE)
    elif kind == "keybinds":
        text = apply_pandora_keybinds(text)
    else:
        raise ValueError(f"unknown repair kind: {kind}")
    tomllib.loads(text)
    return text


def main():
    path = pathlib.Path(sys.argv[2])
    original = path.read_text() if path.exists() else ""
    kind = sys.argv[1]
    value = sys.argv[3] if len(sys.argv) > 3 else ""
    extra = sys.argv[4:]
    updated = repair(original, kind, value, *extra)
    if kind == "greeter" and len(sys.argv) > 4:
        updated = set_key(updated, "session", "default", sys.argv[4])
        tomllib.loads(updated)
    if updated != original:
        if path.exists():
            import shutil
            shutil.copy2(path, str(path) + ".pandora.bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S%f"))
        path.write_text(updated)
        print(f"OK: repaired and validated {path}")
    else:
        print(f"OK: validated {path}")


if __name__ == "__main__":
    main()
