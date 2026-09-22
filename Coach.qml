import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Superkey coach panel. Milestone 1: a bottom-right layer-shell card on the
// focused monitor that shows live Hyprland state coming through Service.qml.
// Contract with omarchy-shell: open(payloadJson), close(), opened.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false

  function open(payloadJson) { opened = true }
  function close() { opened = false }

  readonly property int pad: Style.space(14)

  PanelWindow {
    id: panel
    visible: root.opened
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    anchors { bottom: true; right: true }
    margins { bottom: Style.space(24); right: Style.space(24) }
    implicitWidth: Style.space(420)
    implicitHeight: Style.space(170)
    color: "transparent"
    WlrLayershell.namespace: "superkey-coach"
    WlrLayershell.layer: WlrLayer.Top
    // Keystrokes must keep going to the real desktop, never to the coach.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.96)
      border.color: Color.popups.border
      border.width: Math.max(1, Style.space(2))
      radius: Style.cornerRadius

      Column {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Style.space(6)

        Row {
          spacing: Style.space(10)
          Rectangle { // robot placeholder
            width: Style.space(40); height: Style.space(40)
            radius: Style.space(6)
            color: Color.accent
          }
          Column {
            spacing: Style.space(2)
            Text {
              text: "Superkey · milestone 1"
              color: Color.popups.text
              font.family: Style.font.family
              font.bold: true
              font.pixelSize: Style.font.title
            }
            Text {
              text: root.service
                ? "Workspace " + root.service.focusedWorkspace + "  ·  events seen: " + root.service.eventCount
                : "service not connected"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }

        Text {
          width: parent.width
          text: root.service && root.service.recentEvents.length
            ? root.service.recentEvents.slice(-4).join("\n")
            : "Press Super+2 — the workspace change should appear here."
          color: Util.alpha(Color.popups.text, 0.75)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          wrapMode: Text.NoWrap
          maximumLineCount: 4
        }
      }
    }
  }
}
