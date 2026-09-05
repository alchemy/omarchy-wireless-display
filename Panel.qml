import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Wireless Display bar-widget. Structurally modeled on
// panels/monitor/Panel.qml (bash-script + Process + JSON, since no native
// Quickshell service exists for this) and panels/bluetooth/Panel.qml (the
// discover -> pick -> connect list, and its scan-while-open discovery
// session).
//
// Everything backend-side runs through bin/omarchy-wireless-display-ctl,
// which drives swaybeam. This file only ever sees that script's
// {status, peers, activePeer, activeOutput, error} JSON, so the backend can
// change underneath it without touching the UI.

Panel {
  id: root
  moduleName: "omarchy-wireless-display"
  ipcTarget: "omarchy-wireless-display"

  // Absolute path to the script shipped alongside this file. Resolved from
  // the component's own URL rather than relying on PATH: the plugin
  // installs to ~/.config/omarchy/plugins/<id>/, which is not on the
  // shell's PATH, so a bare command name simply fails to start (confirmed:
  // "Process failed to start, likely because the binary could not be
  // found"). Falls back to the bare name if the URL isn't a local file, so
  // a PATH install still works.
  readonly property string ctl: {
    var url = Qt.resolvedUrl("bin/omarchy-wireless-display-ctl").toString()
    return url.indexOf("file://") === 0 ? url.substring(7) : "omarchy-wireless-display-ctl"
  }

  readonly property var state: Model.parseState(stateProc.text)
  readonly property var peers: state.peers
  readonly property var activePeer: state.activePeer
  readonly property bool busy: Model.isBusy(state)
  readonly property string icon: Model.statusIcon(state)
  readonly property string statusLine: Model.statusText(state)

  property int selectedIndex: -1

  function peerLabel(peer) { return Model.peerLabel(peer) }
  function protocolLabel(protocol) { return Model.protocolLabel(protocol) }

  function connectTo(peerId) {
    if (!peerId || connectProc.running) return
    connectProc.command = [root.ctl, "connect", peerId]
    connectProc.running = true
  }

  function disconnect() {
    if (disconnectProc.running) return
    disconnectProc.command = [root.ctl, "disconnect"]
    disconnectProc.running = true
  }

  // Discovery is a session, like Bluetooth's: start it while the popup is
  // open, stop it on close so we're not radio-scanning in the background
  // forever. The lightweight `state` poll below keeps running regardless,
  // so the bar chip stays live even while closed.
  onOpenedChanged: {
    if (opened) {
      scanProc.command = [root.ctl, "scan-start"]
      scanProc.running = true
    } else {
      scanProc.command = [root.ctl, "scan-stop"]
      scanProc.running = true
      selectedIndex = -1
    }
  }

  // --- bar chip + popout ------------------------------------------------
  // BarIconButton and KeyboardPanel are the shell's own idiom for a
  // bar-widget with a popout (see panels/monitor). They handle bar styling,
  // hover/press, anchoring the panel to the button, sizing and focus --
  // all of which an earlier hand-rolled Row + Rectangle got wrong: it
  // anchored children inside a Row (which Row rejects outright) and called
  // Style.radius()/Style.fontSize()/Color.surface, none of which exist.

  // The root takes its size from the button, which is what actually gives
  // the widget a footprint in the bar. Without this the root Item is
  // zero-sized, the button dutifully fills that nothing, and the widget is
  // present and working but completely invisible -- which is exactly how it
  // first appeared in the bar.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(520))

    Column {
      id: panelColumn
      width: parent.width
      spacing: Style.spacing.md

      Text {
        text: root.statusLine
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        width: parent.width
        elide: Text.ElideRight
      }

      // Connected peer + disconnect
      Row {
        visible: !!root.activePeer
        width: parent.width
        spacing: Style.spacing.controlGap

        Text {
          text: root.activePeer
            ? Model.peerLabel(root.activePeer) + " · " + Model.protocolLabel(root.activePeer.protocol)
            : ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Button {
          text: "Disconnect"
          onClicked: root.disconnect()
        }
      }

      Repeater {
        model: root.peers

        Row {
          width: panelColumn.width
          spacing: Style.spacing.controlGap

          Text {
            text: Model.peerLabel(modelData) + " (" + Model.protocolLabel(modelData.protocol) + ")"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Button {
            visible: modelData.state !== "connected"
            enabled: !root.busy
            text: root.busy && root.selectedIndex === index ? "…" : "Connect"
            onClicked: {
              root.selectedIndex = index
              root.connectTo(modelData.id)
            }
          }
        }
      }

      Text {
        visible: root.peers.length === 0
        text: root.state.status === "discovering" ? "Scanning…" : "No wireless displays found"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // --- backend processes ------------------------------------------------

  // Lightweight, always running while this widget is mounted (i.e. whenever
  // the bar is up) so the chip icon reflects connection state even with the
  // popup closed — same split monitor/bluetooth make between a cheap status
  // poll and an expensive discovery session.
  Process {
    id: stateProc
    command: [root.ctl, "state"]
    property string text: ""
    stdout: SplitParser {
      onRead: data => stateProc.text = data
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!stateProc.running) stateProc.running = true
  }

  Process { id: scanProc }
  Process { id: connectProc; onRunningChanged: if (!running) stateProc.running = true }
  Process { id: disconnectProc; onRunningChanged: if (!running) stateProc.running = true }
}
