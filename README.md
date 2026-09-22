# Superkey

Learn Omarchy shortcuts by doing. A free Omarchy 4 shell plugin that guides
you through the real keybindings on your real desktop and confirms each one
actually happened. Companion to the free Stevinator Omarchy course.

**Status: milestone 2 — first lesson (Workspaces) works end to end.** See [DESIGN.md](DESIGN.md) for the plan.

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
