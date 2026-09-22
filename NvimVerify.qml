import QtQuick
import Quickshell
import Quickshell.Io

// Neovim observer for Superkey. The practice editor runs
// `nvim --listen <socket>` on a throwaway sample project; while a Neovim
// step is waiting we poll `nvim --server <socket> --remote-expr` for a JSON
// snapshot of what's open (which-key, picker + its source, explorer,
// lazygit). Verified against Omarchy's LazyVim v16 (snacks.nvim picker,
// neo-tree explorer, which-key v3).
Item {
  id: root

  readonly property string socket: Quickshell.env("XDG_RUNTIME_DIR") + "/superkey-nvim.sock"
  readonly property string projectDir: "/tmp/superkey-practice"
  property bool active: false
  property bool polling: false

  // Observed state
  property bool connected: false
  property bool whichKey: false
  property var pickerSources: []
  property bool explorer: false
  property int explorerWidth: 0
  property bool lazygit: false
  property int serial: 0

  // Step-relative
  property int explorerWidthAtStart: 0
  function beginStep() { explorerWidthAtStart = explorerWidth }

  function start() {
    if (active) return
    active = true
    connected = false
    projectProc.running = true
  }
  function stop() { active = false; polling = false; cleanupProc.running = true }

  // Sample project: a tiny git repo so the explorer, grep, and lazygit all
  // have something real to show. Never touches the user's files.
  Process {
    id: projectProc
    command: ["bash", "-c",
      "D=" + root.projectDir + "; rm -rf \"$D\"; mkdir -p \"$D/src\" && cd \"$D\" && " +
      "printf '# Superkey practice project\\n\\nA throwaway repo for practicing Neovim shortcuts.\\n' > README.md && " +
      "printf 'def greet(name):\\n    return f\"Hello, {name}\"\\n' > src/app.py && " +
      "printf 'TODO: find this line with Space S G\\n' > NOTES.txt && " +
      "git init -q && git -c user.name=Superkey -c user.email=superkey@example.com add -A && " +
      "git -c user.name=Superkey -c user.email=superkey@example.com commit -qm 'Practice project' && rm -f " + root.socket]
  }
  Process { id: cleanupProc; command: ["bash", "-c", "rm -f " + root.socket + "; rm -rf " + root.projectDir] }

  // The command the practice terminal runs.
  readonly property var editorCommand: ["ghostty", "--title=Superkey practice", "--working-directory=" + projectDir,
    "-e", "nvim", "--listen", socket, "README.md"]

  readonly property string expr: "json_encode(luaeval('(function() " +
    "local r = { wk = false, sources = {}, explorer = false, explorer_width = 0, lazygit = false } " +
    "for _, w in ipairs(vim.api.nvim_list_wins()) do local b = vim.api.nvim_win_get_buf(w) local ft = vim.bo[b].filetype " +
    "if ft == \"wk\" then r.wk = true end " +
    "if ft == \"neo-tree\" then r.explorer = true r.explorer_width = vim.api.nvim_win_get_width(w) end end " +
    "local ok, s = pcall(require, \"snacks\") if ok and s.picker then for _, p in ipairs(s.picker.get()) do table.insert(r.sources, p.opts.source or \"\") end end " +
    "for _, b in ipairs(vim.api.nvim_list_bufs()) do if vim.bo[b].buftype == \"terminal\" and vim.api.nvim_buf_get_name(b):find(\"lazygit\") then r.lazygit = true end end " +
    "return r end)()'))"

  Process {
    id: pollProc
    command: ["nvim", "--server", root.socket, "--remote-expr", root.expr]
    stdout: StdioCollector { onStreamFinished: {
      try {
        var j = JSON.parse(text)
        root.connected = true
        root.whichKey = j.wk === true
        root.pickerSources = j.sources || []
        root.explorer = j.explorer === true
        root.explorerWidth = j.explorer_width || 0
        root.lazygit = j.lazygit === true
        root.serial++
      } catch (e) { root.connected = false }
    } }
  }
  Timer { running: root.active && root.polling; interval: 250; repeat: true; onTriggered: if (!pollProc.running) pollProc.running = true }

  function hasSource(name) { return pickerSources.indexOf(name) !== -1 }
}
