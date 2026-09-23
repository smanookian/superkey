import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Superkey coach panel: renders Service.qml's lesson state.
// Contract with omarchy-shell: open(payloadJson), close(), opened.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false

  function open(payloadJson) {
    opened = true
    try {
      var p = JSON.parse(payloadJson || "{}")
      if (p.lesson && service) service.startLesson(p.lesson)
    } catch (e) {}
  }
  function close() { opened = false }

  // IPC surface: `omarchy-shell shell call stevinator.superkey <fn> <arg>`
  function start(lessonId) { if (service) service.startLesson(lessonId || "hyprland.workspaces"); opened = true }
  function stop() { if (service) service.stopLesson() }
  function skip() { if (service) service.skipStep() }
  function confirm() { if (service) service.continueStep() }
  function hint() { if (service) service.showHint() }
  function showme() { if (service) service.showMe() }
  function debug() { return service ? JSON.stringify({ windowSeen: service.windowSeen, activeSeen: service.activeSeen, activeAtStart: service.activeAtStart, layerSeen: service.layerSeen, practice: service.practiceAddresses, snap: service.clientsSnapshot.length, captureStart: service.captureStart, verify: service.step ? service.step.verify : null, stepStart: service.stepStart ? service.stepStart.address : null, info: service.practiceInfo().map(function(c){ return c.address + ":" + c.focusHistoryID + ":" + c.workspace.id }) }) : "{}" }
  function tmuxdebug() { var t = service ? service.tmuxState : null; return t ? JSON.stringify({ active: t.active, lastEvent: t.lastEvent, serial: t.eventSerial, panes: t.paneCount, windows: t.windowCount, added: t.windowsAdded, prefix: t.prefixSeen, watchPrefix: t.watchPrefix, layout: t.layout, order: t.windowOrder, orderStart: t.windowOrderAtStart, changed: t.orderChanged() }) : "none" }
  function setting(kv) { var p = kv.split("="); if (service) service.setSetting(p[0], p[1] === "true"); return JSON.stringify(service.progress.settings) }
  function state() { return service ? JSON.stringify({ phase: service.phase, step: service.stepIndex, results: service.results }) : "{}" }

  readonly property int pad: Style.space(14)
  readonly property var step: service ? service.step : null
  readonly property string phase: service ? service.phase : "idle"

  // Pointing (exact): a click-through fullscreen layer that draws an accent
  // frame around the window the current step is about. Bar pointing was
  // dropped on purpose -- third-party plugins can't read bar geometry, and
  // an approximate arrow is worse than none.
  PanelWindow {
    id: highlight
    visible: root.opened && root.service && root.service.highlightRect !== null
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "superkey-highlight"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    Rectangle {
      readonly property var r: root.service ? root.service.highlightRect : null
      visible: r !== null
      x: r ? r.x - 4 : 0; y: r ? r.y - 4 : 0
      width: r ? r.w + 8 : 0; height: r ? r.h + 8 : 0
      color: "transparent"
      border.color: Color.accent
      border.width: 3
      radius: Style.cornerRadius + 4
      opacity: 0.9
      SequentialAnimation on opacity {
        running: visible && !(root.service && root.service.reduceMotion)
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.9; duration: 700; easing.type: Easing.InOutSine }
      }
      Behavior on x { enabled: !(root.service && root.service.reduceMotion); NumberAnimation { duration: 180 } }
      Behavior on y { enabled: !(root.service && root.service.reduceMotion); NumberAnimation { duration: 180 } }
      Behavior on width { enabled: !(root.service && root.service.reduceMotion); NumberAnimation { duration: 180 } }
      Behavior on height { enabled: !(root.service && root.service.reduceMotion); NumberAnimation { duration: 180 } }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    anchors { bottom: true; right: true }
    margins { bottom: Style.space(24); right: Style.space(24) }
    implicitWidth: Style.space(440)
    implicitHeight: card.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "superkey-coach"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: card
      anchors.fill: parent
      implicitHeight: body.implicitHeight + root.pad * 2
      color: Util.alpha(Color.background, 0.96)
      border.color: root.phase === "success" ? Color.accent : Color.popups.border
      border.width: Math.max(1, Style.space(2))
      radius: Style.cornerRadius

      Column {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.pad }
        spacing: Style.space(8)

        // Header row: robot placeholder + progress line
        Row {
          spacing: Style.space(10)
          width: parent.width
          // Robot: six 64x64 pixel-art states in assets/robot, chosen from
          // engine state. Blink alternates with idle; nothing else animates
          // except a small success bounce (off under Less motion).
          Item {
            id: robot
            width: Style.space(56); height: Style.space(56)
            readonly property bool reduce: root.service && root.service.reduceMotion
            readonly property string state: {
              if (!root.service) return "idle"
              if (root.service.finished) return "done"
              if (root.phase === "success") return "success"
              if (root.phase === "waiting" && root.service.demoNote === "" && (root.service.hintShown || (root.step && root.step.verify && (root.step.verify.type === "loose" || root.step.verify.loose === true)))) return "think"
              if (root.phase === "waiting" && root.service.highlightRect !== null) return "point-right"
              return blinkTimer.blinking ? "blink" : "idle"
            }
            Timer {
              id: blinkTimer
              property bool blinking: false
              running: root.opened && !robot.reduce && robot.state.indexOf("idle") === 0 || robot.state === "blink"
              interval: blinking ? 140 : 3600; repeat: true
              onTriggered: blinking = !blinking
            }
            Image {
              anchors.fill: parent
              source: Qt.resolvedUrl("assets/robot/" + robot.state + ".png")
              smooth: false; mipmap: false
              fillMode: Image.PreserveAspectFit
              scale: robot.state === "success" && !robot.reduce ? 1.12 : 1.0
              Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
            }
          }
          Column {
            spacing: Style.space(2)
            Text {
              text: root.service && root.service.lesson
                ? (root.service.finished ? "Lesson complete" : "Step " + (root.service.stepIndex + 1) + " of " + root.service.lesson.steps.length + " · " + root.service.lesson.title)
                : "Superkey"
              color: Color.popups.text; font.family: Style.font.family; font.bold: true; font.pixelSize: Style.font.title
            }
            Text {
              text: root.service && root.service.lesson ? "Workspace " + root.service.focusedWorkspace : "Learn Omarchy shortcuts by doing."
              color: Util.alpha(Color.popups.text, 0.7); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // Lesson map (idle)
        Column {
          width: parent.width
          visible: root.service && !root.service.lesson && root.service.index
          spacing: Style.space(4)
          Repeater {
            model: root.service && root.service.index ? root.service.index.tracks : []
            delegate: Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(3)
              Text { text: modelData.title + " \u2014 " + modelData.blurb; color: Util.alpha(Color.popups.text, 0.7); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
              Repeater {
                model: modelData.lessons
                delegate: Rectangle {
                  required property string modelData
                  readonly property var prog: root.service ? root.service.lessonProgress(modelData) : null
                  width: parent.width; height: Style.space(26); radius: Style.space(4)
                  color: lm.containsMouse ? Util.alpha(Color.accent, 0.25) : Util.alpha(Color.popups.text, 0.06)
                  Row {
                    anchors.fill: parent; anchors.leftMargin: Style.space(8); anchors.rightMargin: Style.space(8); spacing: Style.space(8)
                    Text { anchors.verticalCenter: parent.verticalCenter; text: root.lessonTitle(modelData); color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: prog ? (prog.done + prog.loose) + "/" + prog.total + (prog.done + prog.loose === prog.total ? " \u2713" : "") : ""; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
                  }
                  MouseArea { id: lm; anchors.fill: parent; hoverEnabled: true; onClicked: root.service.startLesson(modelData) }
                }
              }
            }
          }
        }

        // Step note (loose verification)
        Text {
          width: parent.width; visible: text !== ""; text: root.phase === "waiting" ? root.stepNote() : ""
          color: Util.alpha(Color.popups.text, 0.55); font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
        }

        // Instruction
        Text {
          width: parent.width
          visible: root.step !== null || (root.service && root.service.finished)
          text: root.service && root.service.finished ? root.summaryText() : (root.step ? root.step.say : "")
          color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.subtitle
          wrapMode: Text.WordWrap
        }

        // Keycaps
        Row {
          visible: root.step !== null && !root.service.finished
          spacing: Style.space(6)
          Repeater {
            model: root.step ? root.step.keys : []
            delegate: Rectangle {
              required property string modelData
              width: kt.implicitWidth + Style.space(16); height: Style.space(28); radius: Style.space(5)
              color: root.phase === "success" ? Color.accent : Util.alpha(Color.popups.text, 0.12)
              border.color: Util.alpha(Color.popups.text, 0.35); border.width: 1
              Text { id: kt; anchors.centerIn: parent; text: modelData; color: root.phase === "success" ? Color.background : Color.popups.text; font.family: Style.font.family; font.bold: true; font.pixelSize: Style.font.body }
            }
          }
        }

        // Hint / why line
        Text {
          width: parent.width
          visible: text !== ""
          text: root.phase === "success" && root.step ? root.step.why
              : (root.service && root.service.demoNote !== "" ? root.service.demoNote
              : (root.service && root.service.hintShown && root.step ? root.step.hint : ""))
          color: Util.alpha(Color.popups.text, 0.8); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // Actions
        Row {
          spacing: Style.space(8)
          CoachButton { text: "Continue"; visible: root.step !== null && root.phase === "waiting" && root.step.verify && root.step.verify.type === "loose"; onClicked: root.service.continueStep() }
          CoachButton { text: "Hint"; visible: root.step !== null && root.phase === "waiting"; onClicked: root.service.showHint() }
          CoachButton { text: "Show me"; visible: root.step !== null && root.phase === "waiting" && root.step.showme; onClicked: root.service.showMe() }
          CoachButton { text: "Skip"; visible: root.step !== null && root.phase === "waiting"; onClicked: root.service.skipStep() }
          CoachButton { text: "Again"; visible: root.service && root.service.finished; onClicked: root.service.startLesson(root.service.lesson.id) }
          CoachButton { text: "Lessons"; visible: root.service && (root.service.finished || !root.service.lesson); onClicked: { if (root.service) root.service.stopLesson() } }
          CoachButton { text: root.service && root.service.muted ? "Unmute" : "Mute"; visible: root.service && !root.service.lesson; onClicked: root.service.setSetting("muted", !root.service.muted) }
          CoachButton { text: root.service && root.service.reduceMotion ? "Motion on" : "Less motion"; visible: root.service && !root.service.lesson; onClicked: root.service.setSetting("reduceMotion", !root.service.reduceMotion) }
          CoachButton { text: "Close"; onClicked: { if (root.service) root.service.stopLesson(); root.close() } }
        }
      }
    }
  }

  readonly property var lessonTitles: ({
    "hyprland.essentials": "Essentials", "hyprland.windows-1": "Windows I \u2014 focus & tiling",
    "hyprland.windows-2": "Windows II \u2014 size & shape", "hyprland.windows-3": "Windows III \u2014 groups",
    "hyprland.workspaces": "Workspaces", "hyprland.scratchpad": "Scratchpad", "hyprland.panels": "Panels & tools",
    "tmux.sessions": "Sessions & windows", "tmux.panes": "Panes", "nvim.basics": "Editor basics"
  })
  function lessonTitle(id) { return lessonTitles[id] || id }

  function summaryText() {
    var done = 0, loose = 0, skipped = 0
    for (var k in service.results) { if (service.results[k] === "done") done++; else if (service.results[k] === "loose") loose++; else skipped++ }
    var t = done + " verified"
    if (loose) t += ", " + loose + " confirmed by you"
    if (skipped) t += ", " + skipped + " skipped"
    return t + ". Read more in Module " + service.lesson.course.module + ", section " + service.lesson.course.section + "."
  }
  function stepNote() {
    if (!step || !step.verify) return ""
    if (step.verify.type === "loose") return "I can't see this one \u2014 press Continue when you've done it."
    if (step.verify.loose === true) return "I can only see that a menu or panel opened, not which one."
    return ""
  }

  component CoachButton: Rectangle {
    property string text: ""
    signal clicked()
    width: bt.implicitWidth + Style.space(18); height: Style.space(26); radius: Style.space(5)
    color: ma.containsMouse ? Util.alpha(Color.accent, 0.35) : Util.alpha(Color.popups.text, 0.1)
    Text { id: bt; anchors.centerIn: parent; text: parent.text; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked() }
  }
}
