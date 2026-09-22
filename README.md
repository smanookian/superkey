# Superkey

Learn Omarchy shortcuts by doing. A free Omarchy 4 shell plugin that guides
you through the real keybindings on your real desktop and confirms each one
actually happened. Companion to the free Stevinator Omarchy course.

**Status: milestone 3 — all seven Hyprland lessons run end to end; progress persists.** See [DESIGN.md](DESIGN.md) for the plan.

## Requirements

Omarchy ≥ 4.0.4. Nothing else — Quickshell, Hyprland, tmux, and Neovim are
already part of Omarchy.

## Install

```bash
omarchy plugin add https://github.com/smanookian/superkey.git
omarchy plugin enable stevinator.superkey
```

Omarchy installs every third-party plugin disabled so you can read the code
first; the second line turns it on. Then click the `SK` button in the bar,
or run `omarchy-shell shell toggle stevinator.superkey '{}'`.

## Develop

Symlink the checkout into the plugins directory so the shell loads it from
the repo:

```bash
ln -sfn "$PWD/superkey" ~/.config/omarchy/plugins/stevinator.superkey
omarchy-shell shell rescanPlugins
omarchy plugin enable stevinator.superkey
```

Superkey is `keepLoaded` (the coach survives between summons), which means
Omarchy does **not** hot-swap its code on save. After editing QML, run
`omarchy-restart-shell`; the plugin stays enabled across restarts.

Useful checks:

```bash
omarchy-shell shell listPlugins | jq '.[] | select(.id=="stevinator.superkey")'
hyprctl layers | grep superkey-coach          # the coach surface exists
journalctl --user -f | grep -i superkey        # load errors, if any
```

## Milestone 1 — verified on Omarchy 4.0.4

- `service` + `panel` + `bar-widget` kinds load in `omarchy-shell`.
- The coach is a layer-shell surface (`superkey-coach`) bottom-right of the
  focused screen, themed from the user's Omarchy theme, never takes
  keyboard focus.
- The service receives Hyprland's raw event stream and focused-workspace
  state; the coach displays them live.
- `Hyprland.dispatch` works in the Lua form Omarchy 4 uses.

## Milestone 2 — first lesson end to end

`lessons/hyprland.workspaces.json` (7 steps) runs on the live desktop:

- Setup spawns two `Superkey practice` terminals and parks one on
  workspace 2, so `Super+Tab` / `Super+Shift+Tab` have somewhere to go.
- Each step is verified by *observed effect*, never by keystroke:
  `workspace` (focused id changed to N), `workspaceDelta` (moved
  forward/back relative to where the step began), `practiceWindowOnWorkspace`
  (a practice window landed on N, with/without focus following),
  `workspaceSequence` (visited N then M in order).
- Hint · Show me · Skip. *Show me* performs the action, holds ~1 s, reverts
  to the step's starting state and says "Now you." — it never completes the
  step for you.
- Success flash + one-line "why", auto-advance, end summary with the course
  module/section, practice windows closed.

Drive it without clicking (handy for testing):

```bash
omarchy-shell shell summon stevinator.superkey '{"lesson":"hyprland.workspaces"}'
omarchy-shell shell call stevinator.superkey state ''     # {"phase":…,"step":…,"results":…}
omarchy-shell shell call stevinator.superkey hint ''
omarchy-shell shell call stevinator.superkey showme ''
omarchy-shell shell call stevinator.superkey skip ''
omarchy-shell shell call stevinator.superkey stop ''
```

Two platform findings worth knowing (both handled):

- `hl.dsp.window.close("address:…")` **ignores its argument** and closes the
  focused window. The table form `hl.dsp.window.close({ window = "address:…" })`
  targets correctly. Same for `window.move`.
- `Hyprland.toplevels[*].workspace` refreshes asynchronously after a move;
  window-based steps poll every 250 ms while waiting.

## Milestone 3 — the Hyprland track

Seven lessons, 45 steps (`lessons/index.json` lists them; the coach shows
a lesson map with per-lesson progress when idle):

| Lesson | Steps | Notes |
|---|---|---|
| Essentials | 6 | menu, terminal, browser, keybindings, close, system menu |
| Windows I — focus & tiling | 9 | focus, swap, float, fullscreen, full width, split |
| Windows II — size & shape | 5 | resize both axes, save/restore width (self-confirmed), pop |
| Windows III — groups | 2 | group toggle, cycle (self-confirmed) |
| Workspaces | 7 | switch, next/prev, move with/without follow, former |
| Scratchpad | 3 | send, show, hide |
| Panels & tools | 13 | every `Super+Ctrl+…` panel, menus, btop, calculator, pickers |

Progress lives in `~/.local/state/superkey/progress.json` (per lesson:
verified / self-confirmed / skipped counts). "Reset progress" is not in the
UI yet; delete the file.

Verification types (all *observed*, never inferred from keys):
`workspace`, `workspaceDelta`, `workspaceSequence`, `practiceWindowOnWorkspace`,
`practiceFloating`, `practiceFullscreen`, `practicePinned`, `practiceGrouped`,
`practiceOnSpecial`, `practiceResized`, `practiceMoved`, `practiceClosed`,
`focusChanged`, `special`, `windowClass`, `layer`, `loose`.
`loose` steps (nothing observable) ask the user to press **Continue** and
are recorded separately from verified ones. `layer` steps with `loose: true`
can only see *a* menu/panel opened, not which — the coach says so.

Platform findings from this milestone (all handled in the engine):

- **Scrolling layout.** A workspace can be in Omarchy's *scrolling* layout
  (`~/.local/state/omarchy/workspace-layouts/<n>.lua`); split toggling and
  vertical resize behave differently there. Window lessons set
  `"isolate": true` and run on an empty, non-scrolling workspace, then
  return you to where you were. This also keeps practice away from your
  real windows.
- **Bar panels don't emit `openlayer`.** Audio/Bluetooth/… share one
  keepLoaded `omarchy-keyboard-panel` surface; `hyprctl layers` lists it only
  while mapped, so layer steps poll that as well as listening for events.
- **Theme and background pickers are the same overlay** (`omarchy-image-selector`).
- **`ghostty --gtk-single-instance`** means a new terminal can take several
  seconds to appear; the engine waits, it never times a step out.
- **Single-instance apps** (the browser) may not open a *new* window;
  `windowClass` also accepts focus moving onto that class.
- **`hl.dsp.group.toggle()`** is the group binding (not `window.group`).
- Resize is edge-relative: `Super+=` on the rightmost window is a no-op.
  Lesson text says to try both keys.
- `hyprctl clients` snapshots are queued, not dropped, when one is already
  running; a 600 ms safety-net re-check runs while any step is waiting.
