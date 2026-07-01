#!/usr/bin/env python3
"""tmux-jump — an EasyMotion/leap-style "jump to text" for tmux, no plugins.

Inspired by https://github.com/schasse/tmux-jump but reworked so it can live in
this repo (usable where external tmux plugins aren't an option) and to add two
things the upstream plugin lacks: jumping across *every* pane in the window, and
incremental multi-character search. Requires only python3 (ships with macOS).

Why a popup:
  Rendering labels by writing escape codes into other panes' ttys (what upstream
  does for its single pane) is fragile across panes. Instead the ~/.tmux.conf
  binding launches this inside a full-window, borderless `display-popup`. A popup
  is one surface we fully control — reliable rendering — and it owns its own pty,
  so we read keystrokes directly in raw mode and never fight tmux for input. We
  reconstruct every pane's visible text into the popup at its real coordinates.

Interaction (leap-style, fully deterministic):
  * Type characters to search; matches across all panes update live.
  * Each match gets a one-key label, drawn on top of it. Labels are drawn only
    from keys that CANNOT be the next character of your search, so every press is
    unambiguous: press a label -> jump; press anything else -> extends the search.
  * Backspace edits the search; Enter jumps to the first match; Esc cancels.
  * On selection we `select-pane` to the match's pane and put the copy-mode
    cursor on it.

Bound in ~/.tmux.conf as:
  bind / display-popup -B -w 100% -h 100% -E "…/tmux-jump.py"
"""

import os
import termios
import threading
import tty
import subprocess

# Label alphabet, home-row first.
KEYS = list("fjdkslaghrueiwotybvncmxzpq")

DIM = "\x1b[0m\x1b[2m"            # dimmed real text
MATCH = "\x1b[0m\x1b[36m"        # cyan — text that matches the search so far
# Bold Catppuccin-Mocha green (#a6e3a1) on the base background (#1e1e2e), via
# truecolor so it matches the theme regardless of the terminal palette. Tweak
# the two rgb triplets to restyle the jump labels.
LABEL = "\x1b[0m\x1b[1;38;2;166;227;161;48;2;30;30;46m"
FOOTER = "\x1b[0m\x1b[1;30;43m"  # bold black on yellow — the search footer
RESET = "\x1b[0m"


def tmux(*args):
    subprocess.run(("tmux",) + args, check=False)


def tmux_out(*args):
    return subprocess.check_output(("tmux",) + args, text=True)


def get_window():
    """Window size plus every visible pane's geometry and text.

    One `list-panes` call carries the window dimensions and zoom flag (repeated
    on every row) alongside per-pane geometry, so we spend a single tmux
    round-trip on metadata instead of three. The N `capture-pane` calls are then
    run in parallel threads (they're IO-bound on the tmux socket), so total
    capture time is ~one capture rather than the serial sum.

    When a pane is zoomed only it is actually on screen, so we keep just that
    pane and give it the full window geometry (the unzoomed pane_top/left/size
    tmux reports would otherwise misplace it)."""
    fmt = ("#{window_width}\t#{window_height}\t#{window_zoomed_flag}\t#{pane_id}"
           "\t#{pane_active}\t#{pane_width}\t#{pane_height}\t#{pane_top}\t#{pane_left}")
    lines = tmux_out("list-panes", "-F", fmt).splitlines()
    win_w, win_h, zoomed = (int(x) for x in lines[0].split("\t")[:3])

    panes = []
    for line in lines:
        _, _, _, pid, active, w, h, top, left = line.split("\t")
        panes.append({
            "id": pid, "active": active == "1",
            "w": int(w), "h": int(h), "top": int(top), "left": int(left),
        })

    if zoomed:
        panes = [p for p in panes if p["active"]]
        for p in panes:  # the zoomed pane fills the window
            p["w"], p["h"], p["top"], p["left"] = win_w, win_h, 0, 0

    def fill_rows(p):
        text = tmux_out("capture-pane", "-p", "-t", p["id"]).split("\n")
        while len(text) < p["h"]:
            text.append("")
        p["rows"] = [ln[: p["w"]].ljust(p["w"]) for ln in text[: p["h"]]]

    threads = [threading.Thread(target=fill_rows, args=(p,)) for p in panes]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    return win_w, win_h, panes


def build_composite(win_w, win_h, panes):
    """Every pane's text laid onto one window-sized grid of row strings."""
    grid = [[" "] * win_w for _ in range(win_h)]
    for p in panes:
        for r, line in enumerate(p["rows"]):
            wr = p["top"] + r
            if not (0 <= wr < win_h):
                continue
            for c, ch in enumerate(line):
                wc = p["left"] + c
                if 0 <= wc < win_w:
                    grid[wr][wc] = ch
    return ["".join(row) for row in grid]


def find_matches(panes, search):
    """All case-insensitive occurrences of `search` across panes. Each match
    records its pane, pane-local (row, col), window-absolute (wr, wc) for drawing,
    and the char that would continue the search (`nextch`, lowercased)."""
    if not search:
        return []
    needle = search.lower()
    n = len(needle)
    matches = []
    for p in panes:
        for r, line in enumerate(p["rows"]):
            low = line.lower()
            start = 0
            while True:
                c = low.find(needle, start)
                if c < 0:
                    break
                nextch = line[c + n].lower() if c + n < len(line) else None
                matches.append({
                    "pane": p, "row": r, "col": c,
                    "wr": p["top"] + r, "wc": p["left"] + c,
                    "nextch": nextch,
                })
                start = c + 1
    return matches


def assign_labels(matches):
    """Map label -> match using only 'safe' keys (never a possible next search
    char), so a label press can't be confused with extending the search."""
    blocked = {m["nextch"] for m in matches if m["nextch"] in KEYS}
    safe = [k for k in KEYS if k not in blocked] or KEYS
    n = len(matches)
    width = 1
    while len(safe) ** width < n:
        width += 1
    labels = [""]
    for _ in range(width):
        labels = [pre + k for pre in labels for k in safe]
    return {labels[i]: matches[i] for i in range(n)}


def render(fd, base_rows, win_w, win_h, search, matches, label_map):
    """Repaint the popup: dimmed window text, matched substrings highlighted,
    one-key labels on top, and a search footer on the last row."""
    slen = len(search)
    # (row, col) spans to paint as MATCH, and (row, col)->label to paint on top.
    match_span = {}
    for m in matches:
        for k in range(slen):
            match_span[(m["wr"], m["wc"] + k)] = True
    # Labels sit immediately AFTER the typed letters so your search stays visible.
    labels_by_cell = {}
    for label, m in label_map.items():
        base = m["wc"] + slen
        for k, ch in enumerate(label):
            labels_by_cell[(m["wr"], base + k)] = ch

    buf = ["\x1b[?25l\x1b[?7l\x1b[H"]  # hide cursor, disable autowrap, home
    for r in range(win_h):
        cells = list(base_rows[r])
        line = ["\x1b[%d;1H" % (r + 1)]
        mode = None  # 'dim' | 'match' | 'label'
        for c in range(win_w):
            if (r, c) in labels_by_cell:
                want, ch = "label", labels_by_cell[(r, c)]
            elif (r, c) in match_span:
                want, ch = "match", cells[c]
            else:
                want, ch = "dim", cells[c]
            if want != mode:
                line.append({"dim": DIM, "match": MATCH, "label": LABEL}[want])
                mode = want
            line.append(ch)
        line.append(RESET)
        buf.append("".join(line))

    hint = " jump » %s " % search + ("(%d)" % len(matches) if search else "")
    buf.append("\x1b[%d;1H%s%s%s" % (win_h, FOOTER, hint[: win_w - 1], RESET))
    os.write(fd, "".join(buf).encode("utf-8", "replace"))


def read_key():
    """Read one keypress. Returns ('char', c) / 'back' / 'enter' / None (cancel)."""
    b = os.read(0, 1)
    if not b or b in (b"\x1b", b"\x03"):      # EOF, Esc, Ctrl-C
        return None
    if b in (b"\x7f", b"\x08"):               # Backspace
        return "back"
    if b in (b"\r", b"\n"):                    # Enter
        return "enter"
    return ("char", b.decode("utf-8", "replace"))


def jump(match):
    """Focus the match's pane and put the copy-mode cursor on it."""
    pane, row, col = match["pane"], match["row"], match["col"]
    pid = pane["id"]
    tmux("select-pane", "-t", pid)
    tmux("copy-mode", "-t", pid)
    tmux("send-keys", "-X", "-t", pid, "top-line")
    tmux("send-keys", "-X", "-t", pid, "start-of-line")
    if row > 0:
        tmux("send-keys", "-X", "-t", pid, "-N", str(row), "cursor-down")
    if col > 0:
        tmux("send-keys", "-X", "-t", pid, "-N", str(col), "cursor-right")


def main():
    win_w, win_h, panes = get_window()
    base_rows = build_composite(win_w, win_h, panes)

    old = termios.tcgetattr(0)
    tty.setraw(0)
    try:
        search = ""
        while True:
            matches = find_matches(panes, search)
            label_map = assign_labels(matches) if matches else {}
            render(1, base_rows, win_w, win_h, search, matches, label_map)

            key = read_key()
            if key is None:
                return
            if key == "back":
                search = search[:-1]
                continue
            if key == "enter":
                if matches:
                    jump(matches[0])
                    return
                continue

            ch = key[1]
            # A label press is unambiguous (safe keys can't extend the search).
            first_of = {lb[0]: lb for lb in label_map}
            if search and ch in first_of:
                sel = ch
                cands = [lb for lb in label_map if lb.startswith(sel)]
                while len(cands) > 1 or (len(cands) == 1 and len(cands[0]) > len(sel)):
                    k = read_key()
                    if k is None:
                        return
                    if not isinstance(k, tuple):
                        cands = []
                        break
                    sel += k[1]
                    cands = [lb for lb in label_map if lb.startswith(sel)]
                if sel in label_map:
                    jump(label_map[sel])
                    return
                continue  # dead-end label; ignore
            search += ch
    finally:
        termios.tcsetattr(0, termios.TCSADRAIN, old)
        os.write(1, b"\x1b[?7h\x1b[?25h")  # restore autowrap + cursor


if __name__ == "__main__":
    main()
