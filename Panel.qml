import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Scaffold for the Wireless Display bar-widget. Structurally modeled on
// panels/monitor/Panel.qml (bash-script + Process + JSON, no native
// Quickshell service exists for this) and panels/bluetooth/Panel.qml (the
// discover -> pick -> connect list interaction). See ../ARCH.md for why this
// shape was chosen and what's still stubbed vs real.
//
// Everything backend-side runs through bin/omarchy-wireless-display-ctl.
// Today that script is a hand-written stub simulating a Miracast session;
// it gets replaced by the real omarchy-wireless-displayd once the swaybeam
// fork (ARCH.md, "Build vs. adopt: swaybeam") lands. Nothing in this file
// should need to change when that happens — it only ever sees the
// {status, peers, activePeer, activeOutput, error} JSON contract.

Panel {
  id: root
  moduleName: "omarchy-wireless-display"
  ipcTarget: "omarchy-wireless-display"

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
    connectProc.command = ["omarchy-wireless-display-ctl", "connect", peerId]
    connectProc.running = true
  }

  function disconnect() {
    if (disconnectProc.running) return
    disconnectProc.command = ["omarchy-wireless-display-ctl", "disconnect"]
    disconnectProc.running = true
  }

  // Discovery is a session, like Bluetooth's: start it while the popup is
  // open, stop it on close so we're not radio-scanning in the background
  // forever. The lightweight `state` poll below keeps running regardless,
  // so the bar chip stays live even while closed.
  onOpenedChanged: {
    if (opened) {
      scanProc.command = ["omarchy-wireless-display-ctl", "scan-start"]
      scanProc.running = true
    } else {
      scanProc.command = ["omarchy-wireless-display-ctl", "scan-stop"]
      scanProc.running = true
      selectedIndex = -1
    }
  }

  // --- bar chip -------------------------------------------------------
  implicitWidth: chip.implicitWidth
  implicitHeight: chip.implicitHeight

  Row {
    id: chip
    spacing: Style.space(4)

    Text {
      text: root.icon
      color: root.barForeground
      font.pixelSize: Style.fontSize(16)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.toggle()
    }
  }

  // --- popup content ---------------------------------------------------
  // Real popups elsewhere (monitor, bluetooth) anchor a Rectangle-based
  // popout to the bar chip via PanelController; that plumbing is intentionally
  // left out of this scaffold so it can be dropped straight into a live shell
  // checkout's existing popout host. `visible: root.opened` stands in for it.
  Rectangle {
    id: popout
    visible: root.opened
    width: Style.space(320)
    implicitHeight: content.implicitHeight + Style.space(24)
    color: Color.surface
    radius: Style.radius(12)

    Column {
      id: content
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(8)

      Text {
        text: root.statusLine
        color: root.barForeground
        font.pixelSize: Style.fontSize(14)
      }

      Row {
        visible: !!root.activePeer
        spacing: Style.space(8)

        Text {
          text: root.activePeer ? Model.peerLabel(root.activePeer) + " · " + Model.protocolLabel(root.activePeer.protocol) : ""
          color: root.barForeground
        }

        Button {
          text: "Disconnect"
          onClicked: root.disconnect()
        }
      }

      Repeater {
        model: root.peers

        Row {
          spacing: Style.space(8)
          width: content.width

          Text {
            text: Model.peerLabel(modelData) + " (" + Model.protocolLabel(modelData.protocol) + ")"
            color: root.barForeground
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
        visible: root.peers.length === 0 && state.status === "discovering"
        text: "Scanning…"
        color: root.barForeground
      }

      Text {
        visible: root.peers.length === 0 && state.status !== "discovering"
        text: "No wireless displays found"
        color: root.barForeground
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
    command: ["omarchy-wireless-display-ctl", "state"]
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
