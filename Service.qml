import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Superkey lesson engine (headless). Owns: lesson index + loading, step state,
// practice windows, verification against live Hyprland state, progress file.
// Coach.qml / Start.qml only render what's here and call the functions below.
Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  // ---- live Hyprland state --------------------------------------------
  readonly property int focusedWorkspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property string focusedWorkspaceName: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.name : ""

  // ---- lesson index ----------------------------------------------------
  property var index: null               // parsed lessons/index.json
  readonly property string lessonsDir: Qt.resolvedUrl("lessons/")

  FileView {
    id: indexFile
    path: Qt.resolvedUrl("lessons/index.json")
    onLoaded: { try { root.index = JSON.parse(text()) } catch (e) { root.lastMessage = "index.json: " + e } }
  }

  // ---- progress ---------------------------------------------------------
  readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") !== "" ? Quickshell.env("XDG_STATE_HOME") + "/superkey" : Quickshell.env("HOME") + "/.local/state/superkey"
  property var progress: ({ version: 1, lessons: {}, settings: { muted: false, reduceMotion: false } })

  Process { id: mkdir; command: ["mkdir", "-p", root.stateDir] }
  FileView {
    id: progressFile
    path: root.stateDir + "/progress.json"
    blockLoading: true
    onLoaded: { try { var p = JSON.parse(text()); if (p && p.version === 1) root.progress = p } catch (e) {} }
  }
  Component.onCompleted: mkdir.running = true

  function saveProgress() {
    progressFile.setText(JSON.stringify(progress, null, 2))
  }

  function lessonProgress(id) { return progress.lessons[id] || null }

  readonly property bool welcomeSeen: progress.settings && progress.settings.welcomeSeen === true
  readonly property bool muted: progress.settings && progress.settings.muted === true
  readonly property bool reduceMotion: progress.settings && progress.settings.reduceMotion === true
  function setSetting(key, value) {
    var p = ({}); for (var i in progress) p[i] = progress[i]
    var st = ({}); for (var j in progress.settings) st[j] = progress.settings[j]
    st[key] = value; p.settings = st; progress = p; saveProgress()
  }

  // Sound: qt6-multimedia isn't on Omarchy, pw-play is. Tiny synthesized
  // WAVs in assets/sfx, owned outright.
  readonly property string sfxDir: Qt.resolvedUrl("assets/sfx/").toString().replace("file://", "")
  Process { id: sfxProc; command: ["pw-play", ""] }
  function play(name) {
    if (muted) return
    if (sfxProc.running) return
    sfxProc.command = ["pw-play", sfxDir + name + ".wav"]
    sfxProc.running = true
  }

  function recordLessonResult() {
    if (!lesson) return
    var done = 0, skipped = 0, loose = 0
    for (var k in results) { if (results[k] === "done") done++; else if (results[k] === "loose") loose++; else skipped++ }
    var p = ({}); for (var i in progress) p[i] = progress[i]
    var lessons = ({}); for (var j in progress.lessons) lessons[j] = progress.lessons[j]
    lessons[lesson.id] = { done: done, loose: loose, skipped: skipped, total: lesson.steps.length, completedAt: new Date().toISOString() }
    p.lessons = lessons
    progress = p
    saveProgress()
  }

  function resetProgress() {
    progress = ({ version: 1, lessons: {}, settings: progress.settings })
    saveProgress()
  }

  // Keybinding suggestion. Superkey never writes ~/.config/hypr; it copies
  // one line to the clipboard for the user to paste into bindings.lua.
  // Super+K, Super+Alt+K and Super+Ctrl+K are all taken on stock Omarchy 4.0.4;
  // Super+Ctrl+Shift+K is free.
  readonly property string suggestedKeys: "Super + Ctrl + Shift + K"
  readonly property string suggestedBinding: 'o.bind("SUPER + CTRL + SHIFT + K", "Superkey", "omarchy-shell shell toggle stevinator.superkey \'{}\'")'
  Process { id: clip; command: ["wl-copy", ""] }
  function copyBinding() { clip.command = ["wl-copy", "--", suggestedBinding]; clip.running = true }

  // Quit = disable the plugin. The bar button disappears and the coach
  // unloads; `omarchy plugin enable stevinator.superkey` brings it back.
  Process { id: quitProc; command: ["omarchy", "plugin", "disable", "stevinator.superkey"] }
  function quit() { stopLesson(); quitProc.running = true }

  // ---- lesson state ----------------------------------------------------
  property var lesson: null
  property int stepIndex: -1
  readonly property var step: lesson && stepIndex >= 0 && stepIndex < lesson.steps.length ? lesson.steps[stepIndex] : null
  property bool finished: false
  property string phase: "idle"          // idle | waiting | success | done
  property bool hintShown: false
  property var results: ({})             // stepId -> "done" | "loose" | "skipped"
  property string lastMessage: ""
  property int stepStartWorkspace: -1
  property var stepStart: ({})           // snapshot of practice window state at step start

  // ---- practice windows -----------------------------------------------
  readonly property string practiceTitle: "Superkey practice"
  property var practiceAddresses: []
  property bool awaitingPractice: false
  property int practiceWanted: 0

  function norm(a) { a = String(a); return a.indexOf("0x") === 0 ? a : "0x" + a }
  function isPractice(tl) { return practiceAddresses.indexOf(norm(tl.address)) !== -1 }

  function practiceClients() {
    var out = [], tl = Hyprland.toplevels.values
    for (var i = 0; i < tl.length; i++) if (isPractice(tl[i])) out.push(tl[i])
    return out
  }

  function practiceClient() {
    var all = practiceClients()
    for (var i = 0; i < all.length; i++) if (all[i].activated) return all[i]
    for (var j = 0; j < all.length; j++) if (all[j].workspace && all[j].workspace.id === focusedWorkspace) return all[j]
    return all.length ? all[0] : null
  }

  function closeStrayPractice() {
    var tl = Hyprland.toplevels.values
    for (var i = 0; i < tl.length; i++)
      if (tl[i].title === practiceTitle)
        Hyprland.dispatch("hl.dsp.window.close({ window = \"address:" + norm(tl[i].address) + "\" })")
  }

  TmuxVerify { id: tmux }
  NvimVerify { id: nvim }
  readonly property var tmuxState: tmux
  readonly property var nvimState: nvim
  readonly property bool tmuxLesson: lesson !== null && lesson.setup && lesson.setup.tmux === true
  readonly property bool nvimLesson: lesson !== null && lesson.setup && lesson.setup.nvim === true

  function spawnPractice(count) {
    practiceWanted = practiceAddresses.length + count
    awaitingPractice = true
    for (var i = 0; i < count; i++) {
      if (tmuxLesson)
        Quickshell.execDetached(["ghostty", "--title=" + practiceTitle, "-e", "tmux", "-L", tmux.socket, "attach", "-t", "practice"])
      else if (nvimLesson)
        Quickshell.execDetached(nvim.editorCommand)
      else
        Quickshell.execDetached(["ghostty", "--title=" + practiceTitle, "-e", "bash", "-c",
          "printf '\\n  Superkey practice window " + (i + 1) + ".\\n  Do the shortcuts on THIS window when asked.\\n\\n'; exec bash"])
    }
  }

  function closePractice() {
    for (var i = 0; i < practiceAddresses.length; i++)
      Hyprland.dispatch("hl.dsp.window.close({ window = \"address:" + practiceAddresses[i] + "\" })")
    practiceAddresses = []
  }

  // Snapshot of every practice window, for before/after comparisons. Uses
  // `hyprctl clients -j` because toplevel objects don't expose geometry.
  property var clientsSnapshot: []
  Process {
    id: clientsProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector { onStreamFinished: {
      try { root.clientsSnapshot = JSON.parse(text) } catch (e) {}
      root.verifyNow()
      if (root.refreshPending) { root.refreshPending = false; root.refreshClients() }
    } }
  }
  property bool refreshPending: false
  function refreshClients() {
    if (clientsProc.running) { refreshPending = true; return }
    clientsProc.running = true
  }
  // Geometry of the window the current step is about (for the highlight
  // overlay). Empty when nothing should be pointed at.
  readonly property var highlightRect: {
    if (phase !== "waiting" || !step || !step.verify || step.verify.type.indexOf("practice") !== 0 && step.verify.type !== "focusChanged") return null
    var info = practiceInfo()
    if (!info.length || info[0].workspace.id !== focusedWorkspace) return null
    return { x: info[0].at[0], y: info[0].at[1], w: info[0].size[0], h: info[0].size[1] }
  }

  function practiceInfo() {
    var out = []
    for (var i = 0; i < clientsSnapshot.length; i++) {
      var c = clientsSnapshot[i]
      if (practiceAddresses.indexOf(c.address) !== -1) out.push(c)
    }
    // Most recently focused first (focusHistoryID 0 = currently focused).
    out.sort(function(a, b) { return a.focusHistoryID - b.focusHistoryID })
    return out
  }

  // ---- practice workspace (isolation) ---------------------------------
  // Window lessons run on an empty workspace that is not in Omarchy's
  // "scrolling" layout (split/resize semantics differ there), and away from
  // the user's own windows. Scrolling workspaces are the ones with a file in
  // ~/.local/state/omarchy/workspace-layouts/<n>.lua.
  property var scrollingWorkspaces: []
  property int homeWorkspace: -1
  property int practiceWorkspace: -1
  Process {
    id: layoutsProc
    command: ["bash", "-c", "ls \"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workspace-layouts\" 2>/dev/null | sed 's/\\.lua$//'"]
    stdout: StdioCollector { onStreamFinished: {
      var ids = []
      var lines = text.split("\n")
      for (var i = 0; i < lines.length; i++) { var n = parseInt(lines[i]); if (!isNaN(n)) ids.push(n) }
      root.scrollingWorkspaces = ids
      root.beginLesson()
    } }
  }

  function pickPracticeWorkspace() {
    var occupied = {}
    var ws = Hyprland.workspaces.values
    for (var i = 0; i < ws.length; i++) occupied[ws[i].id] = true
    for (var n = 2; n <= 10; n++) {
      if (scrollingWorkspaces.indexOf(n) !== -1) continue
      if (occupied[n]) continue
      return n
    }
    return -1
  }

  // ---- lesson control -------------------------------------------------
  property var pendingLesson: null

  function startLesson(id) {
    lessonLoader.path = ""
    lessonLoader.path = lessonsDir + id + ".json"
  }

  FileView {
    id: lessonLoader
    onLoaded: {
      try {
        root.pendingLesson = JSON.parse(text())
        layoutsProc.running = true   // -> beginLesson()
      } catch (e) {
        root.lastMessage = "Lesson failed to load: " + e
      }
    }
  }

  function beginLesson() {
    var parsed = pendingLesson
    if (!parsed) return
    pendingLesson = null
    lesson = parsed
    results = ({})
    finished = false
    stepIndex = -1
    closeStrayPractice()
    practiceAddresses = []
    homeWorkspace = focusedWorkspace
    practiceWorkspace = -1
    if (parsed.setup && parsed.setup.isolate) {
      practiceWorkspace = pickPracticeWorkspace()
      if (practiceWorkspace !== -1) Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + practiceWorkspace + "\" })")
    }
    if (parsed.setup && parsed.setup.tmux === true) { tmux.start(); spawnLater.interval = 900 }
    else if (parsed.setup && parsed.setup.nvim === true) { nvim.start(); spawnLater.interval = 900 }
    else spawnLater.interval = 250
    if (parsed.setup && parsed.setup.practiceWindows > 0) spawnLater.restart()
    else nextStep()
  }
  // Spawn after the workspace switch has landed so the windows open there.
  Timer { id: spawnLater; interval: 250; onTriggered: { root.spawnPractice(root.lesson.setup.practiceWindows); root.nextStep() } }

  function nextStep() {
    if (!lesson) return
    stepIndex += 1
    hintShown = false
    demoNote = ""
    stepStartWorkspace = focusedWorkspace
    seqProgress = 0
    layerSeen = ""
    captureLayers = true
    windowSeen = ""
    activeAtStart = activeSeen
    activeSeen = ""
    specialSeen = false
    if (stepIndex >= lesson.steps.length) {
      finished = true
      phase = "done"
      closePractice()
      recordLessonResult()
      goHome()
      return
    }
    phase = "waiting"
    tmux.beginStep()
    tmux.polling = tmuxLesson
    nvim.beginStep()
    nvim.polling = nvimLesson
    if (tmuxLesson && lesson.steps[stepIndex].verify && lesson.steps[stepIndex].verify.type === "tmuxReload") tmux.armReloadDetection()
    tmux.watchPrefix = lesson.steps[stepIndex].verify && lesson.steps[stepIndex].verify.type === "tmuxPrefix"
    practiceCountAtStart = practiceAddresses.length
    var s = lesson.steps[stepIndex]
    if (s.verify && s.verify.type.indexOf("practice") === 0) {
      var want = lesson.setup && lesson.setup.practiceWindows ? lesson.setup.practiceWindows : 1
      if (!awaitingPractice && practiceAddresses.length < want) {
        // The user closed one early (or a previous step closed it). Bring it back.
        spawnPractice(want - practiceAddresses.length)
        practiceCountAtStart = want
      } else {
        var pc = practiceClient()
        if (pc) Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + norm(pc.address) + "\" })")
      }
    }
    // Take the "before" snapshot slightly after focusing so geometry is settled.
    snapshotTimer.restart()
  }
  Timer { id: snapshotTimer; interval: 200; onTriggered: { root.refreshClients(); root.captureStart = true } }
  property bool captureStart: false

  // Loose steps can't be observed; the user confirms them.
  function continueStep() {
    if (!step || phase !== "waiting") return
    if (step.verify && step.verify.type === "loose") markDone(true)
  }

  property int practiceCountAtStart: 0

  function markDone(loose) {
    if (!step || phase !== "waiting") return
    if (demoing) {
      demoNote = "That's the effect. Putting it back\u2026"
      if (step.revert || (step.verify && step.verify.type.indexOf("practice") === 0) || step.verify.type.indexOf("workspace") === 0) demoHold.restart()
      else { demoNote = "That's it \u2014 close it, then do it yourself."; demoing = false; demoTimeout.stop() }
      return
    }
    demoNote = ""
    var r = ({}); for (var k in results) r[k] = results[k]; r[step.id] = loose ? "loose" : "done"; results = r
    phase = "success"
    play(stepIndex === lesson.steps.length - 1 ? "complete" : "success")
    advanceTimer.restart()
  }

  function skipStep() {
    if (!step) return
    var r = ({}); for (var k in results) r[k] = results[k]; r[step.id] = "skipped"; results = r
    play("skip")
    nextStep()
  }

  function showHint() { hintShown = true }

  function teardownTmux() { tmux.polling = false; if (tmux.active) tmux.stop(); if (nvim.active) nvim.stop() }

  function goHome() {
    teardownTmux()
    if (homeWorkspace !== -1 && homeWorkspace !== focusedWorkspace) Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + homeWorkspace + "\" })")
    practiceWorkspace = -1
  }

  function stopLesson() {
    closePractice()
    goHome()
    lesson = null
    stepIndex = -1
    finished = false
    phase = "idle"
    demoing = false
    demoNote = ""
  }

  Timer { id: advanceTimer; interval: 1400; onTriggered: root.nextStep() }

  // ---- Show me: demo, hold, revert, "Now you." ---------------------------
  property bool demoing: false
  property string demoNote: ""
  property string demoWindow: ""

  function showMe() {
    if (!step || !step.showme || phase !== "waiting") return
    demoing = true
    demoNote = "Watch\u2026"
    var pc = practiceClient(); demoWindow = pc ? norm(pc.address) : ""
    if (step.showme.indexOf("hl.") === 0) Hyprland.dispatch(step.showme)
    else Quickshell.execDetached(["sh", "-c", step.showme])
    demoTimeout.restart()
  }
  Timer { id: demoTimeout; interval: 2500; onTriggered: root.endDemo() }
  Timer { id: demoHold; interval: 1200; onTriggered: root.revertDemo() }
  function endDemo() { demoing = false; if (demoNote === "Watch\u2026") demoNote = "" }
  function revertDemo() {
    if (step && step.revert) {
      Hyprland.dispatch(step.revert.replace("$WIN", "address:" + demoWindow).replace("$WS", String(stepStartWorkspace)))
    } else {
      if (demoWindow !== "")
        Hyprland.dispatch("hl.dsp.window.move({ window = \"address:" + demoWindow + "\", workspace = \"" + stepStartWorkspace + "\", follow = false })")
      Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + stepStartWorkspace + "\" })")
    }
    demoNote = "Now you."
    demoing = false
    demoTimeout.stop()
    snapshotTimer.restart()
  }

  // ---- verification ---------------------------------------------------
  property int seqProgress: 0
  property string layerSeen: ""
  property string windowSeen: ""
  property string activeSeen: ""
  property string activeAtStart: ""
  property bool specialSeen: false

  function verifyNow() {
    if (!step || phase !== "waiting" || !step.verify) return
    var v = step.verify
    var info = practiceInfo()
    if (captureStart) { stepStart = info.length ? JSON.parse(JSON.stringify(info[0])) : ({}); captureStart = false; return }

    switch (v.type) {
    case "workspace":
      if (focusedWorkspace === v.id && focusedWorkspace !== stepStartWorkspace) markDone(false); break
    case "workspaceDelta":
      if (v.delta > 0 ? focusedWorkspace > stepStartWorkspace : focusedWorkspace < stepStartWorkspace) markDone(false); break
    case "workspaceSequence":
      if (seqProgress < v.ids.length && focusedWorkspace === v.ids[seqProgress]) { seqProgress += 1; if (seqProgress === v.ids.length) markDone(false) }
      break
    case "practiceWindowOnWorkspace": {
      var onTarget = false
      for (var i = 0; i < info.length; i++) if (info[i].workspace && info[i].workspace.id === v.id) onTarget = true
      if (!onTarget) return
      if (v.follow === true && focusedWorkspace === v.id) markDone(false)
      if (v.follow === false && focusedWorkspace !== v.id) markDone(false)
      break }
    case "layer":       // a layer surface with this namespace appeared (loose if flagged)
      if (layerSeen === v.namespace) { markDone(v.loose === true); break }
      if (layersNow.indexOf(v.namespace) !== -1 && layersAtStart.indexOf(v.namespace) === -1) markDone(v.loose === true)
      break
    case "windowClass": // a window with this class opened, or focus moved onto one (single-instance apps)
      if (windowSeen === v["class"] || (activeSeen === v["class"] && activeAtStart !== v["class"])) markDone(false); break
    case "special":     // scratchpad toggled on
      if (specialSeen) markDone(false); break
    case "practiceFloating":
      if (info.length && info[0].floating === v.value) markDone(false); break
    case "practiceFullscreen":
      if (info.length && info[0].fullscreen === v.value) markDone(false); break
    case "practicePinned":
      if (info.length && info[0].pinned === true && info[0].floating === true) markDone(false); break
    case "practiceGrouped":
      if (info.length && info[0].grouped && info[0].grouped.length > 0) markDone(false); break
    case "practiceOnSpecial":
      for (var j = 0; j < info.length; j++) if (info[j].workspace && String(info[j].workspace.name).indexOf("special") === 0) markDone(false); break
    case "practiceResized": {  // size changed on axis "x"|"y" vs. step start
      if (!info.length || !stepStart.size) return
      var ax = v.axis === "y" ? 1 : 0
      if (Math.abs(info[0].size[ax] - stepStart.size[ax]) >= 10) markDone(false)
      break }
    case "practiceMoved": {    // position changed vs. step start (swap / orientation)
      if (!info.length || !stepStart.at) return
      if (info[0].at[0] !== stepStart.at[0] || info[0].at[1] !== stepStart.at[1]) markDone(false)
      break }
    case "tmuxPrefix":        if (tmux.prefixSeen) markDone(false); break
    case "tmuxWindowAdd":     if (tmux.windowsAdded > 0) markDone(false); break
    case "tmuxWindowClose":   if (tmux.windowsClosed > 0) markDone(false); break
    case "tmuxWindowRenamed": if (tmux.windowsRenamed > 0) markDone(false); break
    case "tmuxTree":          if (tmux.modeChanges > 0) markDone(false); break
    case "tmuxDetach":        if (tmux.detaches > 0) markDone(false); break
    case "tmuxWindowSwitch":  if (tmux.windowSwitches > 0) markDone(false); break
    case "tmuxWindowMoved":   if (tmux.orderChanged()) markDone(false); break
    case "tmuxSplit": {       // pane count up; orientation optional: "h" side-by-side ({), "v" stacked ([)
      if (tmux.paneCount <= tmux.paneCountAtStart) return
      if (v.orientation === "h" && tmux.layout.indexOf("{") === -1) return
      if (v.orientation === "v" && tmux.layout.indexOf("[") === -1) return
      markDone(false); break }
    case "tmuxPaneFocus":     if (tmux.paneFocusChanges > 0) markDone(false); break
    case "tmuxPaneResize":    if (tmux.layoutChanges > 0 && tmux.paneCount === tmux.paneCountAtStart && !tmux.zoomed && tmux.layout !== tmux.layoutAtStart) markDone(false); break
    case "tmuxZoom":          if (tmux.zoomed) markDone(false); break
    case "tmuxPaneClose":     if (tmux.paneCount < tmux.paneCountAtStart) markDone(false); break
    case "tmuxSessionSwitch": if (tmux.visibleSession !== "" && tmux.visibleSessionAtStart !== "" && tmux.visibleSession !== tmux.visibleSessionAtStart) markDone(false); break
    case "tmuxReload":        if (tmux.reloadSeen) markDone(false); break
    case "nvimWhichKey":     if (nvim.whichKey) markDone(false); break
    case "nvimPicker":       if (nvim.hasSource(v.source)) markDone(false); break
    case "nvimExplorer":     if (nvim.explorer) markDone(false); break
    case "nvimExplorerResized": if (nvim.explorer && nvim.explorerWidthAtStart > 0 && nvim.explorerWidth !== nvim.explorerWidthAtStart) markDone(false); break
    case "nvimLazygit":      if (nvim.lazygit) markDone(false); break
    case "practiceClosed":
      if (practiceAddresses.length < practiceCountAtStart) markDone(false); break
    case "loose":
      break
    case "focusChanged":       // the focused practice window is a different one than at step start
      if (info.length && stepStart.address && info[0].address !== stepStart.address && info[0].focusHistoryID === 0) markDone(false)
      break
    }
  }

  onFocusedWorkspaceChanged: verifyNow()
  Connections { target: tmux; function onEventSerialChanged() { root.verifyNow() } }
  Connections { target: nvim; function onSerialChanged() { root.verifyNow() } }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event.name, d = event.data
      if (n === "openwindow") {
        var parts = d.split(",")
        if (root.awaitingPractice && parts.length >= 4 && parts.slice(3).join(",") === root.practiceTitle) {
          var a = root.practiceAddresses.slice(); a.push("0x" + parts[0]); root.practiceAddresses = a
          var k = a.length - 1
          var park = root.lesson && root.lesson.setup && root.lesson.setup.workspaces ? root.lesson.setup.workspaces[k] : undefined
          if (park !== undefined && park !== root.focusedWorkspace)
            Hyprland.dispatch("hl.dsp.window.move({ window = \"address:0x" + parts[0] + "\", workspace = \"" + park + "\", follow = false })")
          if (a.length >= root.practiceWanted) root.awaitingPractice = false
        }
        if (parts.length >= 3) root.windowSeen = parts[2]
      } else if (n === "closewindow") {
        var idx = root.practiceAddresses.indexOf("0x" + d)
        if (idx !== -1) { var b = root.practiceAddresses.slice(); b.splice(idx, 1); root.practiceAddresses = b }
      } else if (n === "activewindow") {
        root.activeSeen = d.split(",")[0]
      } else if (n === "openlayer") {
        root.layerSeen = d
      } else if (n === "activespecial" || n === "activespecialv2") {
        if (d.indexOf("special") !== -1) root.specialSeen = true
      }
      recheck.restart()
    }
  }
  Timer { id: recheck; interval: 80; onTriggered: root.refreshClients() }
  // Safety net: nothing observable should ever be missed because an event
  // raced a snapshot in flight.
  Timer { running: root.phase === "waiting"; interval: 600; repeat: true; onTriggered: root.refreshClients() }

  // Some shell surfaces (the bar panels) are one keepLoaded layer that maps
  // and unmaps without a reliable openlayer event; `hyprctl layers` lists a
  // layer only while it is mapped, so poll it during layer steps.
  property var layersAtStart: []
  property var layersNow: []
  Process {
    id: layersProc
    command: ["hyprctl", "layers", "-j"]
    stdout: StdioCollector { onStreamFinished: {
      var names = []
      try {
        var j = JSON.parse(text)
        for (var mon in j) { var lv = j[mon].levels; for (var l in lv) for (var i = 0; i < lv[l].length; i++) names.push(lv[l][i].namespace) }
      } catch (e) {}
      if (root.captureLayers) { root.layersAtStart = names; root.captureLayers = false }
      root.layersNow = names
      root.verifyNow()
    } }
  }
  property bool captureLayers: false
  Timer {
    running: root.phase === "waiting" && root.step !== null && root.step.verify && root.step.verify.type === "layer"
    interval: 300; repeat: true; triggeredOnStart: true
    onTriggered: if (!layersProc.running) layersProc.running = true
  }
  Timer {
    running: root.phase === "waiting" && root.step !== null && root.step.verify && root.step.verify.type.indexOf("practice") === 0
    interval: 300; repeat: true
    onTriggered: root.refreshClients()
  }
}
