import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Superkey lesson engine (headless). Owns: lesson loading, step state,
// practice windows, verification against live Hyprland state.
// Coach.qml only renders what's here and calls the functions below.
Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  // ---- live Hyprland state --------------------------------------------
  readonly property int focusedWorkspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  property int previousWorkspace: -1
  property var workspaceHistory: []      // last few focused ids, newest last

  // ---- lesson state ----------------------------------------------------
  property var lesson: null              // parsed lesson JSON
  property int stepIndex: -1
  readonly property var step: lesson && stepIndex >= 0 && stepIndex < lesson.steps.length ? lesson.steps[stepIndex] : null
  readonly property bool running: lesson !== null && stepIndex >= 0 && !finished
  property bool finished: false
  property string phase: "idle"          // idle | waiting | success | done
  property bool hintShown: false
  property var results: ({})             // stepId -> "done" | "skipped"
  property string lastMessage: ""

  // ---- practice windows -----------------------------------------------
  // Only windows Superkey spawned. Matched by title on openwindow; tracked by address.
  readonly property string practiceTitle: "Superkey practice"
  property var practiceAddresses: []
  property bool awaitingPractice: false

  function isPractice(tl) {
    var a = String(tl.address)
    if (a.indexOf("0x") !== 0) a = "0x" + a
    return practiceAddresses.indexOf(a) !== -1
  }

  function practiceClients() {
    var out = [], tl = Hyprland.toplevels.values
    for (var i = 0; i < tl.length; i++) if (isPractice(tl[i])) out.push(tl[i])
    return out
  }

  function practiceClient() {
    var all = practiceClients()
    // prefer the focused one, then one on the current workspace
    for (var i = 0; i < all.length; i++) if (all[i].activated) return all[i]
    for (var j = 0; j < all.length; j++) if (all[j].workspace && all[j].workspace.id === focusedWorkspace) return all[j]
    return all.length ? all[0] : null
  }

  // Close any window with our practice title, tracked or not (stray from a crash).
  function closeStrayPractice() {
    var tl = Hyprland.toplevels.values
    for (var i = 0; i < tl.length; i++)
      if (tl[i].title === practiceTitle) {
        var a = String(tl[i].address); if (a.indexOf("0x") !== 0) a = "0x" + a
        Hyprland.dispatch("hl.dsp.window.close({ window = \"address:" + a + "\" })")
      }
  }

  property int practiceWanted: 0

  function spawnPractice(count) {
    practiceWanted = count
    awaitingPractice = true
    for (var i = 0; i < count; i++)
      Quickshell.execDetached(["ghostty", "--title=" + practiceTitle, "-e", "bash", "-c",
        "printf '\\n  Superkey practice window.\\n  Do the shortcuts on THIS window when asked.\\n\\n'; exec bash"])
  }

  function closePractice() {
    for (var i = 0; i < practiceAddresses.length; i++)
      Hyprland.dispatch("hl.dsp.window.close({ window = \"address:" + practiceAddresses[i] + "\" })")
    practiceAddresses = []
  }

  // ---- lesson control -------------------------------------------------
  function startLesson(id) {
    lessonLoader.path = Qt.resolvedUrl("lessons/" + id + ".json")
  }

  FileView {
    id: lessonLoader
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.lesson = parsed
        root.results = ({})
        root.finished = false
        root.stepIndex = -1
        root.closeStrayPractice()
        root.practiceAddresses = []
        if (parsed.setup && parsed.setup.practiceWindows > 0) root.spawnPractice(parsed.setup.practiceWindows)
        root.nextStep()
      } catch (e) {
        root.lastMessage = "Lesson failed to load: " + e
      }
    }
  }

  property int stepStartWorkspace: -1
  property bool armed: false   // true once the step's start-state has been observed

  function nextStep() {
    if (!lesson) return
    stepIndex += 1
    hintShown = false
    stepStartWorkspace = focusedWorkspace
    armed = true
    if (stepIndex >= lesson.steps.length) {
      finished = true
      phase = "done"
      closePractice()
      return
    }
    phase = "waiting"
    seqProgress = 0
    // Focus the practice window for steps that act on it.
    var s = lesson.steps[stepIndex]
    if (s.verify && s.verify.type.indexOf("practiceWindow") === 0) {
      var pc = practiceClient()
      if (pc) Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + pc.address + "\" })")
    }
  }

  function markDone() {
    if (!step || phase !== "waiting") return
    if (demoing) { demoNote = "That's the effect. Putting it back…"; demoHold.restart(); return }
    demoNote = ""
    var r = ({}); for (var k in results) r[k] = results[k]; r[step.id] = "done"; results = r
    phase = "success"
    advanceTimer.restart()
  }

  function skipStep() {
    if (!step) return
    var r = ({}); for (var k in results) r[k] = results[k]; r[step.id] = "skipped"; results = r
    nextStep()
  }

  function showHint() { hintShown = true }

  // Show me: perform the action, let the user see the effect, revert, then
  // it's their turn. While `demoing` the verifier reverts instead of passing.
  property bool demoing: false
  property string demoNote: ""

  function showMe() {
    if (!step || !step.showme || phase !== "waiting") return
    demoing = true
    demoNote = "Watch…"
    var pc = practiceClient(); demoWindow = pc ? String(pc.address) : ""
    Hyprland.dispatch(step.showme)
    demoTimeout.restart()
  }
  property string demoWindow: ""
  Timer { id: demoTimeout; interval: 2500; onTriggered: root.endDemo() }
  Timer { id: demoHold; interval: 1200; onTriggered: root.revertDemo() }

  function endDemo() { demoing = false; demoNote = "" }

  function revertDemo() {
    // Put things back where the step started so the user can do it themselves.
    if (demoWindow !== "") {
      var a = demoWindow; if (a.indexOf("0x") !== 0) a = "0x" + a
      Hyprland.dispatch("hl.dsp.window.move({ window = \"address:" + a + "\", workspace = \"" + stepStartWorkspace + "\", follow = false })")
    }
    Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + stepStartWorkspace + "\" })")
    demoNote = "Now you."
    demoing = false
    demoTimeout.stop()
  }

  function stopLesson() {
    closePractice()
    lesson = null
    stepIndex = -1
    finished = false
    phase = "idle"
  }

  Timer { id: advanceTimer; interval: 1400; onTriggered: root.nextStep() }

  // ---- verification ---------------------------------------------------
  property int seqProgress: 0

  function verifyNow() {
    if (!step || phase !== "waiting" || !step.verify) return
    var v = step.verify
    if (v.type === "workspace") {
      if (focusedWorkspace === v.id && focusedWorkspace !== stepStartWorkspace) markDone()
    } else if (v.type === "workspaceDelta") {
      // relative: +1 / -1 from where the step started (wraps ignored on purpose)
      if (v.delta > 0 ? focusedWorkspace > stepStartWorkspace : focusedWorkspace < stepStartWorkspace) markDone()
    } else if (v.type === "practiceWindowOnWorkspace") {
      var all = practiceClients(), onTarget = false
      for (var i = 0; i < all.length; i++) if (all[i].workspace && all[i].workspace.id === v.id) onTarget = true
      if (!onTarget) return
      if (v.follow === true && focusedWorkspace === v.id) markDone()
      if (v.follow === false && focusedWorkspace !== v.id) markDone()
    } else if (v.type === "workspaceSequence") {
      // ids must be visited in order; progress advances as each is seen.
      if (seqProgress < v.ids.length && focusedWorkspace === v.ids[seqProgress]) {
        seqProgress += 1
        if (seqProgress === v.ids.length) markDone()
      }
    }
  }

  onFocusedWorkspaceChanged: {
    var h = workspaceHistory.slice(-5); h.push(focusedWorkspace); workspaceHistory = h
    if (h.length >= 2) previousWorkspace = h[h.length - 2]
    verifyNow()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "openwindow" && root.awaitingPractice) {
        var parts = event.data.split(",")
        if (parts.length >= 4 && parts.slice(3).join(",") === root.practiceTitle) {
          var a = root.practiceAddresses.slice(); a.push("0x" + parts[0]); root.practiceAddresses = a
          var n = a.length - 1
          var park = root.lesson && root.lesson.setup && root.lesson.setup.workspaces ? root.lesson.setup.workspaces[n] : undefined
          if (park !== undefined && park !== root.focusedWorkspace)
            Hyprland.dispatch("hl.dsp.window.move({ window = \"address:0x" + parts[0] + "\", workspace = \"" + park + "\", follow = false })")
          if (a.length >= root.practiceWanted) root.awaitingPractice = false
        }
      }
      if (event.name === "closewindow") {
        var idx = root.practiceAddresses.indexOf("0x" + event.data)
        if (idx !== -1) { var b = root.practiceAddresses.slice(); b.splice(idx, 1); root.practiceAddresses = b }
      }
      if (event.name === "movewindow" || event.name === "movewindowv2" || event.name === "workspace") {
        // toplevel workspace pointers refresh async; re-check on next tick.
        recheck.restart()
      }
    }
  }
  Timer { id: recheck; interval: 60; onTriggered: root.verifyNow() }
  Timer {
    // Toplevel workspace pointers refresh asynchronously after a move; poll
    // gently while a window-based step is waiting.
    running: root.phase === "waiting" && root.step !== null && root.step.verify && root.step.verify.type.indexOf("practiceWindow") === 0
    interval: 250; repeat: true
    onTriggered: root.verifyNow()
  }
}
