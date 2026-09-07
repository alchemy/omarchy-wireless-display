import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Wireless Display bar-widget.
//
// Everything backend-side runs through bin/omarchy-wireless-display-ctl,
// which drives swaybeam. This file only ever sees that script's
// {status, error, pending, connected, peers} JSON, so the backend can change
// underneath it without touching the UI.
//
// The popout is three rows:
//   1. hero      -- icon, name, description, and a rescan button
//   2. connected -- one box per connected display, each with a disconnect
//   3. available -- one box per discovered display, each offering mirror/extend

Panel {
  id: root
  moduleName: "omarchy-wireless-display"
  ipcTarget: "omarchy-wireless-display"

  // Absolute path to the script shipped alongside this file. Resolved from
  // the component's own URL rather than relying on PATH: the plugin installs
  // to ~/.config/omarchy/plugins/<id>/, which is not on the shell's PATH, so
  // a bare command name simply fails to start. Falls back to the bare name so
  // a PATH install still works.
  readonly property string ctl: {
    var url = Qt.resolvedUrl("bin/omarchy-wireless-display-ctl").toString()
    return url.indexOf("file://") === 0 ? url.substring(7) : "omarchy-wireless-display-ctl"
  }

  readonly property var state: Model.parseState(stateProc.text)
  readonly property var connected: state.connected
  readonly property var available: Model.availablePeers(state)
  readonly property bool busy: Model.isBusy(state)
  readonly property bool scanning: state.status === "discovering"
  readonly property bool canScan: Model.canScan(state)
  readonly property string icon: Model.statusIcon(state)
  readonly property string statusLine: Model.statusText(state)

  function connectTo(peerId, mode) {
    if (!peerId || connectProc.running || root.busy) return
    connectProc.command = [root.ctl, "connect", peerId, mode]
    connectProc.running = true
  }

  function disconnectFrom(peerId) {
    if (disconnectProc.running) return
    disconnectProc.command = [root.ctl, "disconnect", peerId || ""]
    disconnectProc.running = true
  }

  function rescan() {
    if (!root.canScan || scanProc.running) return
    scanProc.command = [root.ctl, "scan-start"]
    scanProc.running = true
  }

  // Discovery is a session, like Bluetooth's: start it while the popup is
  // open, stop it on close so we're not radio-scanning forever. The
  // lightweight `state` poll below runs regardless, so the bar chip stays
  // live even while closed.
  onOpenedChanged: {
    if (opened) {
      scanProc.command = [root.ctl, "scan-start"]
    } else {
      scanProc.command = [root.ctl, "scan-stop"]
    }
    scanProc.running = true
  }

  // The root takes its size from the button, which is what gives the widget a
  // footprint in the bar. Without this the root Item is zero-sized, the button
  // dutifully fills that nothing, and the widget is present and working but
  // completely invisible.
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    Column {
      id: panelColumn
      width: parent.width
      spacing: Style.spacing.md

      // --- row 1: what this is, and a way to look again ------------------
      PanelHero {
        id: hero
        width: parent.width
        title: "Wireless Display"

        // Session state goes in the subtitle rather than the hero's `detail`
        // pill. The pill sizes itself from a width computed against its
        // siblings, so a status phrase long enough to matter -- a display name
        // in "Connecting to ..." -- overlapped the title instead of eliding.
        // The subtitle wraps that up for free and reads as one line of prose.
        meta: {
          if (root.state.status === "error") return "Connection failed"
          if (root.state.status === "idle") return "Mirror or extend onto a Miracast display"
          return root.statusLine
        }
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily

        iconComponent: Component {
          Text {
            text: root.icon
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }
        }

        // Button supplies the chrome -- hover border, press, tooltip -- but
        // renders the glyph itself and spins it about its advance-box centre,
        // which is not where the mark is. It carries no icon of its own here
        // and holds an ActivityGlyph instead; see that file for why this
        // pulses rather than spins.
        trailingControl: Component {
          Button {
            id: rescanButton
            tooltipText: root.canScan
              ? "Scan for displays"
              : "Cannot scan while a display is connected"
            enabled: root.canScan
            foreground: hero.foreground
            fontFamily: hero.fontFamily
            implicitWidth: rescanGlyph.implicitWidth + Style.spacing.controlPaddingX * 2
            implicitHeight: rescanGlyph.implicitHeight + Style.spacing.controlPaddingY * 2
            onClicked: root.rescan()

            ActivityGlyph {
              id: rescanGlyph
              anchors.centerIn: parent
              text: "󰑓"
              color: rescanButton.foreground
              fontFamily: rescanButton.fontFamily
              fontSize: Style.font.icon
              active: root.scanning
            }
          }
        }
      }

      // Errors get their own line: they can be far longer than the hero's
      // detail pill, which elides rather than wraps.
      Text {
        visible: root.state.status === "error" && root.state.error !== ""
        width: parent.width
        text: root.state.error
        color: Color.urgent
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      // --- row 2: connected displays ------------------------------------
      PanelSectionHeader {
        visible: root.connected.length > 0
        width: parent.width
        text: "Connected"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Column {
        width: parent.width
        spacing: Style.spacing.sm
        visible: root.connected.length > 0

        Repeater {
          model: root.connected

          DisplayBox {
            id: connectedBox
            width: parent.width
            bar: root.bar
            title: Model.peerLabel(modelData)
            subtitle: Model.displayDetail(modelData)

            // Carried across explicitly rather than reaching for `modelData`
            // inside the Component: the delegate's model context is not
            // something a separately-instantiated Component should be relied
            // on to see, and the available list below needs the same.
            property string peerId: modelData.id

            actions: Component {
              Button {
                iconText: "󰖭"
                tooltipText: "Disconnect"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.disconnectFrom(connectedBox.peerId)
              }
            }
          }
        }
      }

      // --- row 3: available displays ------------------------------------
      PanelSectionHeader {
        visible: root.available.length > 0
        width: parent.width
        text: "Available"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Column {
        width: parent.width
        spacing: Style.spacing.sm
        visible: root.available.length > 0

        Repeater {
          model: root.available

          DisplayBox {
            id: availableBox
            width: parent.width
            bar: root.bar
            title: Model.peerLabel(modelData)
            subtitle: Model.protocolLabel(modelData.protocol)

            // Mirror and extend are peers, not a default plus an option, so
            // both are offered directly rather than hiding one behind a menu.
            actions: Component {
              Row {
                spacing: Style.spacing.controlGap

                Button {
                  text: "Mirror"
                  iconText: "󰽛"
                  tooltipText: "Duplicate this screen onto the display"
                  enabled: !root.busy
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onClicked: root.connectTo(availableBox.peerId, "mirror")
                }

                Button {
                  text: "Extend"
                  iconText: "󰍺"
                  tooltipText: "Add the display as a second monitor"
                  enabled: !root.busy
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onClicked: root.connectTo(availableBox.peerId, "extend")
                }
              }
            }

            property string peerId: modelData.id
          }
        }
      }

      // --- nothing to show ----------------------------------------------
      Text {
        visible: root.connected.length === 0 && root.available.length === 0
        width: parent.width
        text: root.scanning ? "Scanning…" : "No wireless displays found"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }

  // --- backend processes ------------------------------------------------

  // Lightweight, always running while this widget is mounted so the chip
  // icon reflects connection state even with the popup closed.
  //
  // StdioCollector, not SplitParser: `ctl state` emits pretty-printed JSON
  // spanning many lines, and SplitParser hands over one line at a time — so
  // `text` held just the final "}", JSON.parse threw, and parseState fell
  // back to its empty default. Collect the whole stream and parse once.
  Process {
    id: stateProc
    command: [root.ctl, "state"]
    property string text: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: stateProc.text = text
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!stateProc.running) stateProc.running = true
  }

  Process { id: scanProc; onRunningChanged: if (!running) stateProc.running = true }
  Process { id: connectProc; onRunningChanged: if (!running) stateProc.running = true }
  Process { id: disconnectProc; onRunningChanged: if (!running) stateProc.running = true }
}
