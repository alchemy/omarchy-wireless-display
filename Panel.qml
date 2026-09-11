import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Wireless Display bar-widget.
//
// Everything backend-side runs through bin/omarchy-wireless-display-ctl,
// which drives waycast. This file only ever sees that script's
// {status, error, pending, connected, peers} JSON, so the backend can change
// underneath it without touching the UI.
//
// The popout, following plugin-mockup.png:
//   1. hero       -- icon, name, what is connected, and a rescan button
//   2. DISPLAYS   -- section label, with a Mirror/Extend toggle beside it
//   3. one list   -- every display, connected first, each offering one action
//
// Mode is a property of the panel rather than of each row: the mockup has a
// single Mirror/Extend toggle governing the whole list, so a row needs only
// one button ("Pair") instead of one per mode.

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
  readonly property var displays: Model.displays(state)
  readonly property bool hasConnected: Model.hasConnected(state)
  readonly property bool busy: Model.isBusy(state)
  readonly property bool scanning: state.status === "discovering"
  readonly property string icon: Model.statusIcon(state)

  // Which mode the whole list pairs in. Extend is the default because it is
  // what this plugin exists for; mirroring is the fallback for a sink or a
  // situation where a second desktop is not wanted.
  property string pairMode: "extend"

  property bool rescanConfirmOpen: false

  function pair(displayId) {
    if (!displayId || connectProc.running || root.busy) return
    // The control script turns this into a switch when something else is
    // already connected: it ends that session first, keeping the discovered
    // list, then pairs. Doing it there rather than here avoids issuing a
    // disconnect and a connect from the UI and racing the two.
    connectProc.command = [root.ctl, "connect", displayId, root.pairMode]
    connectProc.running = true
  }

  function disconnectFrom(displayId) {
    if (disconnectProc.running) return
    disconnectProc.command = [root.ctl, "disconnect", displayId || ""]
    disconnectProc.running = true
  }

  // Rescanning drops any session, so when one exists the user is asked
  // first. `rescan` in the control script does the teardown and the scan in
  // one call, so there is no window where the panel has disconnected but not
  // yet started looking again.
  function requestRescan() {
    if (root.hasConnected) {
      root.rescanConfirmOpen = true
      return
    }
    startRescan()
  }

  function startRescan() {
    root.rescanConfirmOpen = false
    if (scanProc.running) return
    scanProc.command = [root.ctl, "rescan"]
    scanProc.running = true
  }

  // Opening the panel looks for displays, except when one is connected --
  // then it waits for the user, because scanning contends with the session
  // for the radio and would cost them the stream they are watching. Closing
  // ends any discovery session so the radio is not scanning in the
  // background; the cheap state poll below keeps the bar chip live.
  onOpenedChanged: {
    if (opened) {
      if (root.hasConnected) return
      scanProc.command = [root.ctl, "scan-start"]
    } else {
      root.rescanConfirmOpen = false
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
    contentHeight: panel.fittedContentHeight(panelBody.implicitHeight, Style.space(560))

    // An Item rather than the Column directly, so the confirmation can
    // overlay the content instead of being laid out as another row in it.
    Item {
      id: panelBody
      width: parent.width
      implicitHeight: panelColumn.implicitHeight

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.spacing.md

        // --- row 1: what this is, what it is doing, and a way to look again
        PanelHero {
          id: hero
          width: parent.width
          title: "Wireless Display"
          meta: Model.headerSubtitle(root.state)
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
          // renders the glyph itself and spins it about its advance-box
          // centre, which is not where the mark is. It carries no icon of its
          // own here and holds an ActivityGlyph instead; see that file for
          // why this pulses rather than spins.
          trailingControl: Component {
            Button {
              id: rescanButton
              tooltipText: root.hasConnected
                ? "Scan again (disconnects the current display)"
                : "Scan for displays"
              foreground: hero.foreground
              fontFamily: hero.fontFamily
              implicitWidth: rescanGlyph.implicitWidth + Style.spacing.controlPaddingX * 2
              implicitHeight: rescanGlyph.implicitHeight + Style.spacing.controlPaddingY * 2
              onClicked: root.requestRescan()

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
        // subtitle, which elides rather than wraps.
        Text {
          visible: root.state.status === "error" && root.state.error !== ""
          width: parent.width
          text: root.state.error
          color: Color.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { width: parent.width; foreground: root.bar.foreground }

        // --- row 2: the list's label, and the mode the list pairs in ------
        Item {
          width: parent.width
          implicitHeight: Math.max(displaysLabel.implicitHeight, modeToggle.implicitHeight)

          // Deliberately not PanelSectionHeader: this has to match the
          // hero's subtitle exactly, and that is PanelHero's own meta text --
          // uppercased, caption size, bold, letter-spaced, dimmed. The
          // section header uses the same size and weight but neither
          // uppercases nor letter-spaces, so the two would not sit together.
          Text {
            id: displaysLabel
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Displays".toUpperCase()
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          Row {
            id: modeToggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.controlGap

            Text {
              text: "Mirror"
              anchors.verticalCenter: parent.verticalCenter
              color: root.pairMode === "mirror"
                ? root.bar.foreground
                : Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.pairMode === "mirror"
            }

            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              checked: root.pairMode === "extend"
              foreground: root.bar.foreground
              onToggled: root.pairMode = (root.pairMode === "extend" ? "mirror" : "extend")
            }

            Text {
              text: "Extend"
              anchors.verticalCenter: parent.verticalCenter
              color: root.pairMode === "extend"
                ? root.bar.foreground
                : Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.pairMode === "extend"
            }
          }
        }

        // --- row 3: every display, connected first ------------------------
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          visible: root.displays.length > 0

          Repeater {
            model: root.displays

            DisplayBox {
              id: displayRow
              width: parent.width
              bar: root.bar
              title: modelData.name
              subtitle: Model.displaySubtitle(modelData)
              highlighted: modelData.connected

              // Carried across explicitly rather than reaching for
              // `modelData` inside the Component: the delegate's model
              // context is not something a separately-instantiated Component
              // should be relied on to see.
              property string displayId: modelData.id
              property bool isConnected: modelData.connected
              property bool isPending: modelData.pending

              actions: Component {
                Button {
                  text: displayRow.isConnected
                    ? "Disconnect"
                    : (displayRow.isPending ? "Pairing…" : "Pair")
                  enabled: displayRow.isConnected || !root.busy
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onClicked: displayRow.isConnected
                    ? root.disconnectFrom(displayRow.displayId)
                    : root.pair(displayRow.displayId)
                }
              }
            }
          }
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        z: 10
        opened: root.rescanConfirmOpen
        message: root.state.connected.length === 1
          ? "Scanning again will disconnect " + Model.peerLabel(root.state.connected[0]) + "."
          : "Scanning again will disconnect the connected displays."
        // ConfirmDialog's buttons are a fixed Style.space(88) wide with the
        // label centred and no eliding, so a longer phrase overflows rather
        // than shrinking the text or growing the button. Keep them short.
        confirmText: "Proceed"
        cancelText: "Cancel"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onCanceled: root.rescanConfirmOpen = false
        onConfirmed: root.startRescan()
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
