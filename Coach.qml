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
  function hint() { if (service) service.showHint() }
  function showme() { if (service) service.showMe() }
  function state() { return service ? JSON.stringify({ phase: service.phase, step: service.stepIndex, results: service.results }) : "{}" }

  readonly property int pad: Style.space(14)
  readonly property var step: service ? service.step : null
  readonly property string phase: service ? service.phase : "idle"

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
          Rectangle {
            width: Style.space(40); height: Style.space(40); radius: Style.space(6)
            color: root.phase === "success" ? Color.accent : Util.alpha(Color.accent, 0.5)
            Text { anchors.centerIn: parent; text: root.phase === "success" ? "✓" : "SK"; color: Color.background; font.bold: true; font.family: Style.font.family; font.pixelSize: Style.font.title }
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
          CoachButton { text: "Start lesson"; visible: !(root.service && root.service.lesson); onClicked: root.service.startLesson("hyprland.workspaces") }
          CoachButton { text: "Hint"; visible: root.step !== null && root.phase === "waiting"; onClicked: root.service.showHint() }
          CoachButton { text: "Show me"; visible: root.step !== null && root.phase === "waiting" && root.step.showme; onClicked: root.service.showMe() }
          CoachButton { text: "Skip"; visible: root.step !== null && root.phase === "waiting"; onClicked: root.service.skipStep() }
          CoachButton { text: "Again"; visible: root.service && root.service.finished; onClicked: root.service.startLesson("hyprland.workspaces") }
          CoachButton { text: "Close"; onClicked: { if (root.service) root.service.stopLesson(); root.close() } }
        }
      }
    }
  }

  function summaryText() {
    var done = 0, skipped = 0
    for (var k in service.results) { if (service.results[k] === "done") done++; else skipped++ }
    return done + " done, " + skipped + " skipped. Read more in Module " + service.lesson.course.module + ", section " + service.lesson.course.section + "."
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
