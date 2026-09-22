# Superkey

Learn Omarchy shortcuts by doing. A free Omarchy 4 shell plugin that guides
you through the real keybindings on your real desktop and confirms each one
actually happened. Companion to the free Stevinator Omarchy course.

**Status: milestone 1 (skeleton).** See [DESIGN.md](DESIGN.md) for the plan.

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
