# Superkey — Design

**Learn Omarchy shortcuts by doing.** A free Omarchy 4 shell plugin that
guides you through the real keybindings on your real desktop, verifies each
one actually happened, and links every lesson back to the Stevinator course.

Status: design only. No code exists. Decisions below were made with the
author on 2026-09-22; facts about Omarchy were verified on Omarchy 4.0.4 /
Hyprland 0.56.2 / Quickshell 0.3.1 / tmux 3.7 / Ghostty 1.3.1.

---

## 1. Decisions already made

| Topic | Decision |
|---|---|
| Name | **Superkey** — plugin id `stevinator.superkey` |
| Form | Omarchy 4 shell plugin, pure QML. Zero packages beyond a stock Omarchy 4 install. |
| Target | Omarchy ≥ 4.0.4. Plugin API is young; expect to touch the plugin after major Omarchy releases. |
| Shape | Guided lessons (not arcade, not ambient coach) |
| Tracks (v1) | Hyprland (42) · Tmux (18) · Neovim/LazyVim (7). 5 text-only cards. |
| Price | Free. Course is free too (stevinator.com/courses/omarchy); handbook/products are the paid tier. |
| Look | Follows the user's Omarchy theme. Stevinator mark only on the start screen. |
| Mascot | Playful pixel robot, generated with Nano Banana Pro from a brief (separate doc). No voice. |
| Sound | CC0 packs (Kenney), played with `pw-play`. Mutable. |
| Distribution | GitHub repo *is* the plugin: `omarchy plugin add https://github.com/smanookian/superkey.git` |
| Data source | `pdfCreator/handbook/src/data/keybindings.json` (already audited against 4.0.4) seeds the lesson content. |
| Not in scope | VMs, accounts, cross-device sync, arcade games, editing any user config. |

Related existing things, and why they don't overlap:
- `smanookian/omarchy-course-verify` — read-only system health check (Bash). Superkey's first-run screen may *link* to it; nothing to merge.
- `webapp/` Shortcut Trainer — browser flashcards/quiz, no OS access. Stays as the "not on Omarchy right now" companion; shares the same JSON.

---

## 2. Platform facts the design relies on (all verified)

- Omarchy 4's desktop is **one Quickshell process** (`quickshell -p /usr/share/omarchy/shell`). Bar, menus, panels, OSD, lock screen are plugins inside it. Third-party plugins load from `~/.config/omarchy/plugins/<id>/` with a `manifest.json`; kinds: `bar-widget`, `panel`, `overlay`, `menu`, `service`, `bar`. Code hot-reloads on save. `keepLoaded: true` keeps a plugin mounted between summons.
- `omarchy plugin add <git-url>` clones, **warns that plugins run unsandboxed, and installs disabled**. The user must `omarchy plugin enable stevinator.superkey`. `--yes --enable` exists for scripts.
- IPC: `omarchy-shell shell summon|hide|toggle|call <id> ...`. Plugins can register their own IPC targets.
- Quickshell `Hyprland` singleton (import `Quickshell.Hyprland`): `rawEvent(event)` stream, `focusedWorkspace`, `focusedMonitor`, `activeToplevel`, `workspaces`, `toplevels`, `monitors`, `dispatch(request)`.
- Hyprland on Omarchy 4 is **Lua-configured**; `dispatch` takes the Lua form used in `/usr/share/omarchy/default/hypr/bindings/*.lua`, e.g. `hl.dsp.focus({ workspace = "2" })`, `hl.dsp.window.close()`, `hl.dsp.workspace.toggle_special("scratchpad")`. Classic `hyprctl dispatch exec foo` **fails** with a Lua parse error.
- `hyprctl binds -j` returns every live bind with a human `description` (210 binds, 208 described). `hyprctl clients -j` exposes `class`, `title`, `initialClass`, `workspace`, `floating`, `fullscreen`, `grouped`, `pinned`, `address`.
- Quickshell `Io` module: `Process` (+ `SplitParser` for line-streamed stdout), `Socket`, `FileView`. No `qt6-multimedia` on Omarchy → no `MediaPlayer`; audio via `Process { command: ["pw-play", path] }`.
- Ghostty: `--class=<app-id>` and `--title=<title>` are real config keys.
- tmux 3.7: control mode (`tmux -C`) emits `%window-add`, `%window-close`, `%window-renamed`, `%layout-change`, `%session-window-changed`, `%window-pane-changed`, `%client-detached`, `%pane-mode-changed`, `%sessions-changed`, `%session-renamed`. Hooks: `after-split-window`, `pane-focus-in`, `window-renamed`, `session-created`, `client-detached`, … Omarchy ships `/usr/share/omarchy/config/tmux/tmux.conf` with `bind -N` descriptions; prefix is `C-Space` (primary) and `C-b` (`prefix2`).
- Neovim 0.12 supports `--listen <socket>` and `--server <socket> --remote-expr <expr>`. Omarchy's Neovim is LazyVim.
- User-scope state convention: `~/.local/state/omarchy/…`. Superkey uses `~/.local/state/superkey/`.

---

## 3. User-facing flow

### 3.1 Install & first run
1. `omarchy plugin add https://github.com/smanookian/superkey.git` → Omarchy warns, clones, installs disabled.
2. User runs `omarchy plugin enable stevinator.superkey` (README and course page show both lines; a `--yes --enable` one-liner is offered for people who've read the code).
3. Superkey adds a small bar widget (robot head) and registers a keybinding *suggestion* — it never writes to `~/.config/hypr`. The start screen is summoned by clicking the widget or `omarchy-shell shell toggle stevinator.superkey`.
4. **Welcome** (overlay, one screen): what Superkey is, what it will and won't touch (see §7), "Start with Essentials".

### 3.2 Start screen (overlay, `kind: overlay`)
- Left: track list — Hyprland · Tmux · Neovim — each with lessons and a completion ring.
- Right: selected lesson's outline (steps as one-liners), "Start", "Reset progress" for this lesson.
- Footer: Stevinator mark, "Companion to the free Omarchy course → module link", mute toggle, "Reduce motion".
- Colors from the shell theme singleton; mark stays in its own palette.

### 3.3 Coach panel (`kind: panel`, `keepLoaded: true`)
A small layer-shell window (~420×160 logical px), anchored **bottom-right of the focused monitor**, above tiled windows, never focusable (the user's keystrokes must go to the real desktop). Contents:

```
┌──────────────────────────────────────────────────┐
│ [robot]  Step 2 of 6 · Workspaces                 │
│          Switch to workspace 2.                  │
│          [Super] + [2]                            │
│          Hint · Show me · Skip          ⏸ ✕      │
└──────────────────────────────────────────────────┘
```

- **Keycaps** light up as modifiers are held (source: `Hyprland.rawEvent` doesn't expose key state; keycap "held" glow is driven by a `GlobalShortcut`-free approach — see §8 open question 1).
- **Verify**: the step's condition (§5) is watched; when it becomes true the step completes: success sound, robot reacts, one-sentence "what just happened", auto-advance after ~1.2 s (configurable / click to advance).
- **Hint**: rephrases with a mnemonic and names the target on screen.
- **Show me**: performs the action *for* the user via `Hyprland.dispatch(...)` or a `tmux`/`nvim` command, then reverts it (where reversible) and asks them to do it themselves. Steps whose action is not safely reversible (e.g. lock screen) have no Show me.
- **Skip**: marks the step skipped, never blocks completion.
- **Pointing**: the robot slides toward the target and points: bar workspace indicator (bar geometry: layer `omarchy-bar` from `hyprctl layers`, workspace index → approximate x; the bar widget's real geometry is *not* exposed to third-party plugins, so pointing at the bar is approximate and stated as such), a window (exact: `hyprctl clients -j` → `at`/`size`), a panel (exact when it's a layer surface with a known namespace; otherwise the robot just looks toward the top-right corner).

### 3.4 Lesson end
Summary card: steps done / skipped, time, "Why this matters" paragraph, deep link to the course module and section (e.g. `stevinator.com/courses/omarchy/module-03#3-29`), "Next lesson".

### 3.5 Returning
Start screen shows progress; the bar widget shows a dot when an unfinished lesson exists. No nagging, no notifications.

---

## 4. Lesson content

Tracks and lessons (Hyprland derived from the audited cheat sheet; ordering by dependency). Counts are bindings, not steps — a step can teach one binding in several forms.

**Hyprland**
1. Essentials (6): Super+Space, Super+Return, Super+Shift+Return, Super+K, Super+W, Super+Escape
2. Windows I — focus & tiling (7): Super+Arrows, Super+Shift+Arrows, Super+T, Super+F, Super+Alt+F, Super+Ctrl+F, Super+J
3. Windows II — size & shape (4): Super+= / -, Super+Shift+= / -, Super+Alt+Home / Super+Home, Super+O
4. Windows III — groups (1): Super+G / Super+Alt+Tab
5. Workspaces (7): Super+1..0, Super+Shift+1..0, Super+Shift+Alt+1..0, Super+Tab, Super+Shift+Tab, Super+Ctrl+Tab, Super+L
6. Scratchpad (2): Super+S, Super+Alt+S
7. Panels & tools (15): Super+Ctrl+{A,B,W,D,C,E,V,T,Q,L,P}, Super+Alt+Space, Super+Ctrl+Shift+Space, Super+Ctrl+Space, Super+Ctrl+Delete

**Tmux** (practice runs in a Superkey-owned tmux server, see §5.2)
8. Sessions & windows (9): prefix, Super+Alt+K, Prefix+c/k/r/s/d, Alt+←/→, Alt+Shift+←/→
9. Panes (9): Prefix+v/h, Alt+Return / Alt+Shift+Return, Ctrl+Alt+Arrows, Ctrl+Alt+Shift+Arrows, Prefix+z, Prefix+x / Alt+Escape, Alt+↑/↓, Prefix+q

**Neovim / LazyVim** (practice runs in a Superkey-owned nvim, see §5.3)
10. Editor basics (7): Super+Shift+N, Space, Space Space, Space S G, Space E, Space G G, Ctrl+←/→

**Text-only cards** (no verification, shown as reading steps): Super+Alt+Return (launch terminal with tmux — verifiable, actually included in lesson 8), Ctrl+R, Ctrl+C, Super+Shift+Ctrl+A (verifiable: window opens; included in lesson 1 as an optional step), Ctrl+Alt+F2 (never practiced; text only with a warning).

### 4.1 Lesson file schema (JSON, one file per lesson, in `lessons/`)

```json
{
  "id": "hyprland.workspaces",
  "track": "hyprland",
  "title": "Workspaces",
  "course": { "module": 3, "section": "3.19" },
  "requires": ["hyprland.essentials"],
  "setup": [ { "spawn": "practice-terminal", "count": 1 } ],
  "steps": [
    {
      "id": "switch-2",
      "say": "Switch to workspace 2.",
      "keys": ["Super", "2"],
      "verify": { "type": "workspace", "id": 2 },
      "point": { "target": "bar-workspace", "id": 2 },
      "showme": { "dispatch": "hl.dsp.focus({ workspace = \"2\" })" },
      "why": "Workspaces are how Omarchy replaces window juggling. One task per workspace."
    }
  ],
  "teardown": [ { "close": "practice-windows" } ]
}
```

Rules: `say` ≤ 90 chars; `keys` are display tokens; `verify` is one of the types in §5; `showme` may be omitted; every step is skippable.

---

## 5. Verification

Principle: **the app never guesses from keystrokes; it observes the effect.** Each binding below lists the observable condition. "Practice window" = a window Superkey spawned with `ghostty --class=superkey-practice --title="Superkey practice"`, tracked by `address`; the app only ever acts on windows it spawned.

### 5.1 Hyprland — via `Quickshell.Hyprland` (`rawEvent`, `toplevels`, `focusedWorkspace`) and `hyprctl clients -j` snapshots

| Binding | Observable condition |
|---|---|
| Super+Space | `openlayer` event for the menu layer (namespace to be confirmed on a live run) |
| Super+Return | new toplevel with a terminal class appears (`openwindow`) |
| Super+Shift+Return | new toplevel with the default browser class appears |
| Super+K | `openlayer` / new window from `omarchy-menu-keybindings` |
| Super+W | practice window's `address` disappears (`closewindow`) |
| Super+Escape | system menu layer opens |
| Super+Arrows | `activewindow` changes to another practice window in the expected direction |
| Super+Shift+Arrows | two practice windows' `at` positions swap |
| Super+T | practice window `floating` flips (`changefloatingmode`) |
| Super+F / Super+Alt+F / Super+Ctrl+F | practice window `fullscreen` becomes 2 / 1 / fullscreen with tiling flag (`fullscreen` event; distinguishing the three uses `hyprctl clients` fields `fullscreen` + `fullscreenClient`) |
| Super+J | layout of the two practice windows changes from side-by-side to stacked (compare `at`/`size`) |
| Super+= / - and Shift variants | practice window `size` changes on the expected axis |
| Super+Alt+Home / Super+Home | width saved then restored: `size.x` returns to recorded value after an intermediate change |
| Super+O | practice window becomes `floating` **and** `pinned` |
| Super+G / Super+Alt+Tab | practice window `grouped` non-empty (`togglegroup`), then active window within group changes |
| Super+1..0 | `focusedWorkspace.id` == N (`workspace` event) |
| Super+Shift+N | practice window `workspace.id` == N **and** focused workspace == N |
| Super+Shift+Alt+N | practice window `workspace.id` == N **and** focused workspace unchanged |
| Super+Tab / Shift+Tab / Ctrl+Tab | focused workspace id +1 / −1 / previous |
| Super+L | `omarchy-hyprland-workspace-layout-toggle` writes state; observe layout change of practice windows (dwindle ↔ scrolling) — condition to be confirmed live |
| Super+S | `activespecial` event with `special:scratchpad` |
| Super+Alt+S | practice window `workspace.name` == `special:scratchpad` |
| Super+Ctrl+A/B/W/D/P | corresponding bar panel opens: layer `openlayer` with the panel's namespace (namespaces to be confirmed live; fallback = "press any key to continue" honesty mode) |
| Super+Ctrl+C / E / V | capture menu / emoji / clipboard layer opens |
| Super+Ctrl+T / Q | new window whose class matches btop / calculator |
| Super+Ctrl+L | session lock: `Hyprland` reports lock; step completes on unlock. **No Show me.** |
| Super+Alt+Space | app launcher layer opens |
| Super+Ctrl+Shift+Space / Super+Ctrl+Space | theme / background picker overlay opens (`omarchy.image-picker` summon → `openlayer`) |
| Super+Ctrl+Delete | monitor list changes (`monitoradded`/`monitorremoved`). **Only offered on laptops with an external display; otherwise text-only.** |
| Super+Shift+Ctrl+A | agent window/terminal appears |

### 5.2 Tmux — via control mode on a private server

Setup: `ghostty --class=superkey-practice -e tmux -L superkey new -s practice`; in parallel `Process { command: ["tmux","-L","superkey","-C","attach","-t","practice"] }` with `SplitParser` reading `%…` notifications. The user's own `~/.config/tmux/tmux.conf` is still loaded, so bindings match what they'll really use. Superkey never touches the default tmux server.

| Binding | Observable condition |
|---|---|
| Ctrl+Space / Ctrl+B (prefix) | `#{client_prefix}` becomes 1 (`tmux display -p` poll during the step) |
| Super+Alt+K | window opens from `omarchy-menu-tmux-keybindings` (Hyprland side) |
| Prefix+c | `%window-add` |
| Prefix+k | `%window-close` |
| Prefix+r | `%window-renamed` |
| Prefix+s | `%pane-mode-changed` into tree mode, then back |
| Prefix+d | `%client-detached` (then Superkey re-attaches the visible client for the next step) |
| Alt+← / → | `%session-window-changed` |
| Alt+Shift+← / → | window index order changes (`tmux list-windows` snapshot) |
| Prefix+v / h, Alt+Return / Alt+Shift+Return | `%layout-change` + pane count +1; orientation from layout string |
| Ctrl+Alt+Arrows | `%window-pane-changed` |
| Ctrl+Alt+Shift+Arrows | `%layout-change` with same pane count, changed sizes |
| Prefix+z | `#{window_zoomed_flag}` == 1 |
| Prefix+x / Alt+Escape | `%layout-change` + pane count −1 |
| Alt+↑ / ↓ | `%client-session-changed` (needs two practice sessions; setup creates both) |
| Prefix+q | tmux prints "Configuration reloaded" (`%message`) |

### 5.3 Neovim — via RPC polling

Setup: practice terminal runs `nvim --listen $XDG_RUNTIME_DIR/superkey-nvim.sock <sample project>`; Superkey polls `nvim --server … --remote-expr '<expr>'` every 200 ms during a step.

| Binding | Observable condition (expr, to be confirmed against Omarchy's LazyVim version) |
|---|---|
| Super+Shift+N | editor window appears (Hyprland side) |
| Space (leader) | which-key popup: a floating window with `filetype == 'which_key'` (or `WhichKey` buffer) exists |
| Space Space | file picker open (LazyVim's picker buffer filetype — `snacks_picker_*` / `TelescopePrompt` depending on version) |
| Space S G | grep picker open (same, with grep source) |
| Space E | explorer buffer present in a window (`neo-tree` / `snacks_picker_list` filetype) |
| Space G G | a terminal buffer whose job command contains `lazygit` |
| Ctrl+← / → | `winwidth(0)` of the explorer window changed |

Exact filetype names are the one thing here that must be checked on a real install before writing lessons.

### 5.4 When verification isn't possible
The step shows "I can't see this one — press Continue when you've done it" and is marked *unverified* in progress. It is never silently marked done.

---

## 6. Plugin structure

```
superkey/                         (git repo root = plugin root)
├── manifest.json                 id stevinator.superkey; kinds: service, panel, overlay, bar-widget
├── Service.qml                   lesson engine: state machine, verifiers, progress I/O, sound
├── Coach.qml                     the panel (keepLoaded)
├── Start.qml                     the overlay (start screen / lesson map)
├── BarWidget.qml                 robot head, summons Start
├── engine/
│   ├── Lesson.js                 loads/validates lesson JSON, step iteration
│   ├── HyprVerify.qml            Hyprland conditions (rawEvent + clients snapshots)
│   ├── TmuxVerify.qml            control-mode reader
│   ├── NvimVerify.qml            remote-expr poller
│   ├── Practice.qml              spawn/track/close practice windows
│   └── Progress.qml              ~/.local/state/superkey/progress.json
├── ui/                           keycaps, robot sprite player, pointer arrow, cards
├── lessons/*.json
├── assets/robot/*.png            sprite sheets (6 states)
├── assets/sfx/*.wav              CC0
└── README.md
```

State file: `~/.local/state/superkey/progress.json` — `{ "version": 1, "lessons": { "<id>": { "done": [...], "skipped": [...], "unverified": [...], "completedAt": "…" } }, "settings": { "muted": false, "reduceMotion": false } }`.

---

## 7. Safety rules (non-negotiable, shown on the welcome screen)

1. Superkey never edits `~/.config/hypr`, `~/.config/tmux`, `~/.config/omarchy`, or any user file. Its only writes are under `~/.local/state/superkey/`.
2. It only closes, moves, floats, or fullscreens windows **it spawned** (class `superkey-practice`, tracked by address). Your windows are never targets.
3. Tmux practice runs on a separate tmux server (`-L superkey`). Your sessions are untouched.
4. Neovim practice opens a sample project in a temp dir; your files are never opened.
5. Steps that would lock the screen, change displays, or reboot are opt-in or text-only, and have no "Show me".
6. Nothing is installed. If a tool a lesson needs is missing, the lesson says so and skips.
7. No network. No telemetry. Course links open in your browser only when you click them.
8. Every step is skippable; skipping never blocks completion.

---

## 8. Open questions (to resolve on a live build, not by assumption)

1. **Keycap "held" glow.** Quickshell has no global key-state API. Options: (a) don't show held state, only the success flash (simplest, honest); (b) poll `/dev/input` — needs `input` group, rejected; (c) a Hyprland `submap` trick, fragile. **Recommendation: (a).**
2. Exact layer namespaces for each panel/menu on 4.0.4 (`hyprctl layers` while each is open).
3. LazyVim picker/explorer filetypes on Omarchy's shipped version.
4. Whether `omarchy-hyprland-workspace-layout-toggle` (Super+L) exposes state we can read.
5. Bar workspace-indicator geometry for pointing: approximate from bar height + widget order, or drop bar pointing in v1.
6. Multi-monitor: v1 = focused monitor only, others ignored; confirm the panel follows `focusedMonitor` correctly.

---

## 9. Milestones (no dates; order only)

1. Skeleton plugin loads in `omarchy-shell`: manifest, empty panel, bar widget, hot-reload confirmed.
2. Hyprland verifier + practice windows; lesson 5 (Workspaces) end-to-end with placeholder art and no sound.
3. Lesson JSON loader, progress file, start screen, remaining Hyprland lessons.
4. Tmux verifier + lessons 8–9.
5. Neovim verifier + lesson 10.
6. Robot sprites, pointing, sound, reduce-motion.
7. README, install flow test on a clean Omarchy 4.0.4, course-page links, GitHub release.
