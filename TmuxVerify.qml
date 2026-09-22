import QtQuick
import Quickshell
import Quickshell.Io

// Tmux observer for Superkey. Runs a private tmux server (-L superkey) so the
// user's own sessions are never touched, attaches a control-mode client to
// it, and turns %notifications into observable state. The user's real
// ~/.config/tmux/tmux.conf still loads, so the bindings they practice are
// the ones they'll actually use.
Item {
  id: root

  readonly property string socket: "superkey"
  property bool active: false

  // Observed state
  property int windowCount: 0
  property int paneCount: 1
  property bool zoomed: false
  property string layout: ""
  property string sessionName: ""
  property string visibleSession: ""      // session the user's (non-control) client is on
  property string visibleSessionAtStart: ""
  property var windowOrder: []          // window ids in index order
  property string lastEvent: ""
  property string lastMessage: ""
  property int eventSerial: 0           // bumps on every notification

  // Step-relative counters (reset by beginStep)
  property int windowsAdded: 0
  property int windowsClosed: 0
  property int windowsRenamed: 0
  property int paneFocusChanges: 0
  property int layoutChanges: 0
  property int sessionChanges: 0
  property int windowSwitches: 0
  property int detaches: 0
  property int modeChanges: 0
  property int paneCountAtStart: 1
  property string layoutAtStart: ""
  property var windowOrderAtStart: []
  property bool prefixSeen: false

  function beginStep() {
    windowsAdded = 0; windowsClosed = 0; windowsRenamed = 0; paneFocusChanges = 0
    layoutChanges = 0; sessionChanges = 0; windowSwitches = 0; detaches = 0; modeChanges = 0
    paneCountAtStart = paneCount; layoutAtStart = layout; windowOrderAtStart = windowOrder.slice()
    prefixSeen = false
    visibleSessionAtStart = visibleSession
  }

  function start() {
    if (active) return
    active = true
    serverProc.running = true
  }

  function stop() {
    active = false
    ctlProc.running = false
    killProc.running = true
  }

  // 1. server with two sessions (session-switch lessons need a second one)
  Process {
    id: serverProc
    command: ["bash", "-c",
      "tmux -L " + root.socket + " kill-server 2>/dev/null; " +
      "tmux -L " + root.socket + " new-session -d -s practice -c \"$HOME\" && " +
      "tmux -L " + root.socket + " new-session -d -s scratch -c \"$HOME\""]
    onExited: (code) => { if (root.active) { root.refresh(); ctlProc.running = true } }
  }

  Process { id: killProc; command: ["tmux", "-L", root.socket, "kill-server"] }

  // 2. control-mode client. stdin must stay open or tmux exits at EOF.
  Process {
    id: ctlProc
    command: ["tmux", "-L", root.socket, "-C", "attach", "-t", "practice"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: (line) => root.handle(line)
    }
  }

  function handle(line) {
    if (line.length === 0 || line[0] !== "%") return
    var sp = line.indexOf(" ")
    var name = sp === -1 ? line : line.substring(0, sp)
    var rest = sp === -1 ? "" : line.substring(sp + 1)
    if (name === "%output" || name === "%begin" || name === "%end") return
    lastEvent = name
    switch (name) {
    case "%window-add": case "%unlinked-window-add": windowsAdded++; refresh(); break
    case "%window-close": case "%unlinked-window-close": windowsClosed++; refresh(); break
    case "%window-renamed": case "%unlinked-window-renamed": windowsRenamed++; break
    case "%window-pane-changed": paneFocusChanges++; break
    case "%layout-change": {
      layoutChanges++
      // "%layout-change @1 <window-layout> <visible-layout> <flags>"
      var parts = rest.split(" ")
      if (parts.length >= 3) layout = parts[2]
      zoomed = parts.length >= 4 && parts[3].indexOf("Z") !== -1
      refresh()
      break }
    case "%session-changed": sessionChanges++; sessionName = rest.split(" ").slice(1).join(" "); break
    case "%session-window-changed": windowSwitches++; break
    case "%client-detached": detaches++; break
    case "%pane-mode-changed": modeChanges++; break
    case "%message": lastMessage = rest; if (rest.indexOf("superkey:reloaded") !== -1) reloadSeen = true; break
    }
    eventSerial++
    refresh()
  }

  // Snapshot of pane count and window order (control mode gives ids but not
  // counts directly).
  Process {
    id: refreshProc
    command: ["bash", "-c",
      "tmux -L " + root.socket + " list-panes -t practice -F '#{pane_id}' | wc -l; " +
      "tmux -L " + root.socket + " list-windows -t practice -F '#{window_id}' | tr '\\n' ' '; echo; " +
      "tmux -L " + root.socket + " list-clients -F '#{client_control_mode} #{session_name}' | awk '$1==0 {print $2; exit}'"]
    stdout: StdioCollector { onStreamFinished: {
      var lines = text.split("\n")
      var n = parseInt(lines[0]); if (!isNaN(n)) root.paneCount = n
      root.windowOrder = (lines[1] || "").trim().split(" ").filter(function(x) { return x !== "" })
      root.windowCount = root.windowOrder.length
      root.visibleSession = (lines[2] || "").trim()
      root.eventSerial++
      if (root.refreshPending) { root.refreshPending = false; root.refresh() }
    } }
  }
  property bool refreshPending: false
  function refresh() {
    if (refreshProc.running) { refreshPending = true; return }
    refreshProc.running = true
  }

  // Prefix detection: any attached client with client_prefix = 1.
  Process {
    id: prefixProc
    command: ["tmux", "-L", root.socket, "list-clients", "-F", "#{client_prefix}"]
    stdout: StdioCollector { onStreamFinished: { if (text.indexOf("1") !== -1) root.prefixSeen = true; root.eventSerial++ } }
  }
  property bool watchPrefix: false
  // Some commands (swap-window, resize) emit no notification; poll while a
  // step is waiting so nothing observable is missed.
  property bool polling: false
  Timer { running: root.active && root.polling; interval: 400; repeat: true; onTriggered: root.refresh() }
  Timer { running: root.active && root.watchPrefix; interval: 120; repeat: true; onTriggered: if (!prefixProc.running) prefixProc.running = true }

  // Reload detection. `display-message` only reaches its target client, so
  // the user's Prefix+q message never reaches us. On the private server we
  // extend whichever prefix key runs source-file with a message to the
  // control client. The user's config file is untouched, and the reload
  // itself restores the original binding.
  property bool reloadSeen: false
  Process {
    id: armReload
    command: ["bash", "-c",
      "T=\"tmux -L " + root.socket + "\"; " +
      "CTL=$($T list-clients -F '#{client_control_mode} #{client_name}' | awk '$1==1{print $2; exit}'); " +
      "LINE=$($T list-keys -T prefix | grep -m1 'source-file'); [ -z \"$LINE\" ] && exit 0; " +
      "KEY=$(echo \"$LINE\" | awk '{print $4}'); CMD=$(echo \"$LINE\" | sed -E 's/^bind-key +-T +prefix +[^ ]+ +//'); " +
      "$T bind-key -T prefix \"$KEY\" \"$CMD \\; display-message -c $CTL superkey:reloaded\""]
  }
  function armReloadDetection() { reloadSeen = false; armReload.running = true }

  function orderChanged() {
    if (windowOrder.length !== windowOrderAtStart.length) return false
    for (var i = 0; i < windowOrder.length; i++) if (windowOrder[i] !== windowOrderAtStart[i]) return true
    return false
  }
}
