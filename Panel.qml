import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Wireless Display bar-widget.
//
// Everything backend-side runs through bin/omarchy-wireless-display-ctl,
// which drives waycast for Miracast and doubletake for AirPlay. This file
// only ever sees that script's {status, error, pending, connected, peers}
// JSON and never learns which backend answered, so adding the second one
// needed no change here beyond `pending` becoming a list.
//
// The popout, following plugin-mockup.png:
//   1. hero       -- icon, name, what is connected, and a rescan button
//   2. DISPLAYS   -- section label
//   3. one list   -- every display, connected first, each with its own
//                    Extend switch and a pair button
//
// Mode is a property of each row rather than of the panel. It began as one
// Mirror/Extend toggle in the section header, which works only while exactly
// one display can be live: AirPlay fans one capture out to several receivers
// at once, and then a single panel-wide switch can neither describe what each
// of them is doing nor say which one the next change applies to. Putting the
// switch on the row it governs answers both.
//
// AirPlay rows carry no switch. They did briefly, on the argument that a list
// whose rows change shape by protocol reads worse than a control that does
// nothing on some of them. That was the wrong way round: a switch that can be
// thrown and changes nothing is not a consistent list, it is a lie about what
// the row can do. doubletake has no extend mode, so those sessions mirror and
// the row says so in its subtitle instead.

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

  // Per-display mode, keyed by display id. Mirroring is the default: it is
  // the mode every sink supports, it needs no headless output, and it leaves
  // the desktop exactly as it was -- so the button that is one click away
  // does the smaller thing, and extending, which adds a monitor and starts
  // moving windows onto it, is asked for.
  //
  // Reassigned rather than mutated. QML re-evaluates bindings on a `var`
  // property when the property itself changes, not when the object it holds
  // is edited in place, so `pairModes[id] = mode` would flip nothing on
  // screen. Entries for displays that have gone away are left alone: they
  // cost a string each and mean a display that comes back is remembered.
  property var pairModes: ({})

  function modeFor(displayId) {
    return pairModes[displayId] === "extend" ? "extend" : "mirror"
  }

  function setModeFor(displayId, mode) {
    var next = {}
    for (var key in pairModes) next[key] = pairModes[key]
    next[displayId] = mode
    pairModes = next
  }

  property bool rescanConfirmOpen: false

  // The display whose row is expanded into credential entry, and what has been
  // typed into it. Same shape as the stock network panel's `passwordSsid` /
  // `passwordText`: the row owns the prompt, the panel owns which row.
  //
  // The id is tracked rather than a boolean because the prompt has to survive
  // the two-second state poll rebuilding the list underneath it.
  property string credentialId: ""
  property string credentialText: ""

  // A receiver asking for a PIN opens the prompt by itself. Waiting for the
  // user to notice a changed subtitle and click something would be a worse
  // trade: the code is on the display's screen *now*, and several receivers
  // stop showing it after a while.
  readonly property string credentialWanted: Model.awaitingCredential(state)
  onCredentialWantedChanged: {
    if (credentialWanted !== "") credentialId = credentialWanted
    else if (!credentialProc.running) closeCredentialPrompt()
  }

  // Copies the current error. The text goes over stdin rather than into a
  // shell command line: it is a backend's words, not ours, so quoting it into
  // `bash -c` would be trusting a stranger with the shell -- and an argument
  // is readable by every local user with `ps`. The kit's own copyToClipboard
  // does quote into a shell; this does not need to.
  function copyError() {
    var text = Model.errorText(root.state)
    if (text === "") return
    copyProc.secret = text
    copyProc.running = true
  }

  function closeCredentialPrompt() {
    credentialId = ""
    credentialText = ""
  }

  // Cancelling means ending that connection, not just hiding the field: the
  // receiver is sitting in its own pairing flow waiting for an answer, and
  // leaving it there would keep the panel busy and block every rescan.
  function cancelCredentialPrompt() {
    var id = credentialId
    closeCredentialPrompt()
    if (id !== "") disconnectFrom(id)
  }

  function submitCredential() {
    if (credentialId === "" || credentialText === "" || credentialProc.running) return
    credentialProc.secret = credentialText
    credentialProc.command = [root.ctl, "credential", credentialId]
    credentialProc.running = true
  }

  function pair(displayId) {
    if (!displayId || connectProc.running || root.busy) return
    // The control script turns this into a switch when something else is
    // already connected: it ends that session first, keeping the discovered
    // list, then pairs. Doing it there rather than here avoids issuing a
    // disconnect and a connect from the UI and racing the two.
    connectProc.command = [root.ctl, "connect", displayId, root.modeFor(displayId)]
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
      root.closeCredentialPrompt()
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
        Item {
          width: parent.width
          visible: root.state.status === "error" && root.state.error !== ""
          implicitHeight: visible ? errorText.implicitHeight : 0

          Text {
            id: errorText
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: copyError.left
            anchors.rightMargin: Style.spacing.controlGap
            anchors.top: parent.top
            text: Model.errorText(root.state)
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // Backend messages are long, exact, and the thing a bug report needs
          // verbatim -- "configure PTP media clock: SETUP response omitted
          // timingPeerInfo.ClockID" is not something anyone retypes. The panel
          // has no selectable text, so without this the only way to move one
          // out of here is a photograph of the screen.
          //
          // Anchored to the top rather than centred: the message wraps, and a
          // button that drifts down the further it wraps reads as unrelated to
          // the line it belongs to.
          PanelActionButton {
            id: copyError
            anchors.right: parent.right
            anchors.top: parent.top
            iconText: "󰆏"
            tooltipText: "Copy this message"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.copyError()
          }
        }

        PanelSeparator { width: parent.width; foreground: root.bar.foreground }

        // --- row 2: the list's label --------------------------------------
        //
        // Deliberately not PanelSectionHeader: this has to match the hero's
        // subtitle exactly, and that is PanelHero's own meta text --
        // uppercased, caption size, bold, letter-spaced, dimmed. The section
        // header uses the same size and weight but neither uppercases nor
        // letter-spaces, so the two would not sit together.
        Text {
          id: displaysLabel
          textFormat: Text.PlainText
          width: parent.width
          text: "Displays".toUpperCase()
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
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

              // Whether this display's mode is a choice at all. AirPlay has no
              // extend mode, so its rows carry no switch.
              property bool modal: Model.supportsExtend(modelData.protocol)

              // A live display shows the mode it actually negotiated, which
              // is not necessarily the one the switch was left on; everything
              // else shows what the next pairing will ask for.
              property bool live: modelData.connected || modelData.pending
              property string mode: live && modelData.mode
                ? modelData.mode
                : root.modeFor(modelData.id)

              // Which credential this receiver asked for, "" once it has been
              // answered. Kept separate from `expanded`: the field stays up
              // while the answer is in flight, and this has already gone back
              // to "" by then.
              property string awaiting: modelData.awaiting
              expanded: root.credentialId === modelData.id

              actions: Component {
                Row {
                  spacing: Style.spacing.controlGap

                  // Read-only while the display is live. The mode is settled
                  // during pairing -- extend has Hyprland create an output,
                  // mirroring does not -- so changing it means tearing the
                  // session down and pairing again, which is not something a
                  // stray click on a switch should do. `busy` swallows the
                  // click while leaving hover, cursor and tooltip alone,
                  // which is exactly how a read-only switch should behave.
                  //
                  // Sized off the label rather than the theme's control
                  // height, as the network panel's band switch is: at full
                  // size the switch dwarfs the row it sits in.
                  ToggleSwitch {
                    id: modeSwitch
                    visible: displayRow.modal
                    anchors.verticalCenter: parent.verticalCenter
                    trackHeight: Math.round(modeLabel.font.pixelSize * 1.2)
                    cursorPad: Style.space(3)
                    checked: displayRow.mode === "extend"
                    busy: displayRow.live
                    foreground: root.bar.foreground
                    onToggled: root.setModeFor(displayRow.displayId,
                      displayRow.mode === "extend" ? "mirror" : "extend")

                    PanelToolTip {
                      visible: modeSwitch.containsMouse
                      text: displayRow.mode === "extend"
                        ? "Extend mode"
                        : "Mirroring mode"
                      fontFamily: root.bar.fontFamily
                    }
                  }

                  // Names the switch, rather than reporting its state -- the
                  // switch does that. Styled as the DISPLAYS label above is,
                  // so the row reads as a labelled control and not as a
                  // second piece of text about the display.
                  Text {
                    id: modeLabel
                    visible: displayRow.modal
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Extend".toUpperCase()
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                  }

                  // The chain-link glyph is U+F0337, Nerd Font's md-link, not
                  // U+1F517: the plain-Unicode link is absent from
                  // CaskaydiaMono Nerd Font and falls back to Noto Color
                  // Emoji, which renders a colour pictograph beside a row of
                  // monochrome marks.
                  //
                  // It carries an ActivityGlyph rather than the Button's own
                  // iconText so pairing can pulse it; see that file for why
                  // this kit pulses instead of spinning.
                  Button {
                    id: pairButton
                    visible: !displayRow.isConnected
                    anchors.verticalCenter: parent.verticalCenter
                    tooltipText: displayRow.isPending
                      ? "Connecting…"
                      : (displayRow.mode === "extend"
                        ? "Pair, extending onto this display"
                        : "Pair, mirroring onto this display")
                    enabled: !root.busy
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    implicitWidth: pairGlyph.implicitWidth + Style.spacing.controlPaddingX * 2
                    implicitHeight: pairGlyph.implicitHeight + Style.spacing.controlPaddingY * 2
                    onClicked: root.pair(displayRow.displayId)

                    ActivityGlyph {
                      id: pairGlyph
                      anchors.centerIn: parent
                      text: "󰌷"
                      color: pairButton.foreground
                      fontFamily: pairButton.fontFamily
                      fontSize: Style.font.icon
                      active: displayRow.isPending
                    }
                  }

                  // U+F0159, md-close-circle -- the same mark the stock
                  // Bluetooth panel puts on "forget".
                  //
                  // Sized off the pair button rather than off its own glyph:
                  // only one of the two is ever visible, and taking the
                  // other's width keeps the row's right edge in the same
                  // place as a display connects and disconnects. The pair
                  // button carries its glyph as a child rather than as
                  // iconText, so its implicit size is an override and the two
                  // would not otherwise agree.
                  Button {
                    id: disconnectButton
                    visible: displayRow.isConnected
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰅙"
                    iconSize: Style.font.icon
                    tooltipText: "Disconnect"
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    implicitWidth: pairButton.implicitWidth
                    implicitHeight: pairButton.implicitHeight
                    onClicked: root.disconnectFrom(displayRow.displayId)
                  }
                }
              }

              // The credential prompt, revealed inside this row rather than
              // over the panel, so which display is being asked about is never
              // in doubt. Deliberately the same arrangement the stock network
              // panel uses for a Wi-Fi passphrase: a masked field with the
              // submit button on its trailing edge, Enter to send, Escape to
              // give up.
              expansion: Component {
                Item {
                  implicitHeight: credentialField.implicitHeight + hint.implicitHeight + Style.space(4)

                  TextField {
                    id: credentialField
                    anchors.left: parent.left
                    anchors.right: submitButton.left
                    anchors.rightMargin: Style.space(6)
                    anchors.top: parent.top
                    password: true
                    placeholderText: Model.credentialLabel(displayRow.awaiting)
                    enabled: !credentialProc.running
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    foreground: root.bar.foreground
                    horizontalPadding: Style.spacing.controlGap
                    verticalPadding: Style.spacing.controlPaddingY
                    text: root.credentialText

                    onAccepted: root.submitCredential()
                    onTextChanged: if (text !== root.credentialText) root.credentialText = text
                    Keys.onEscapePressed: root.cancelCredentialPrompt()

                    // Qt.callLater, not a direct call: the Loader is still
                    // building this item when Component.onCompleted runs, and
                    // focus handed to an item that is not in the scene yet
                    // goes nowhere.
                    Component.onCompleted: Qt.callLater(forceActiveFocus)
                  }

                  PanelActionButton {
                    id: submitButton
                    anchors.right: parent.right
                    anchors.verticalCenter: credentialField.verticalCenter
                    enabled: root.credentialText !== "" && !credentialProc.running
                    iconText: "󰄬"
                    tooltipText: "Send"
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    onClicked: root.submitCredential()
                  }

                  Text {
                    id: hint
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: credentialField.bottom
                    anchors.topMargin: Style.space(4)
                    text: credentialProc.running
                      ? "Sending…"
                      : Model.credentialHint(displayRow.awaiting)
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
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

  // The code goes over stdin, never argv -- an argument is readable by every
  // local user with `ps`, and the control script hands it straight to
  // doubletake's socket for the same reason. This is the stock network
  // panel's enterprise-passphrase idiom.
  Process {
    id: credentialProc
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
    onRunningChanged: {
      if (running) return
      // Whether it was accepted is not this process's answer to give: the
      // receiver decides, and the next state poll carries the verdict. Clear
      // the typed value either way so a wrong code is not left on screen.
      root.credentialText = ""
      if (root.credentialWanted === "") root.closeCredentialPrompt()
      stateProc.running = true
    }
  }

  Process {
    id: copyProc
    command: ["wl-copy"]
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret)
      secret = ""
      stdinEnabled = false
    }
  }

  Process { id: scanProc; onRunningChanged: if (!running) stateProc.running = true }
  Process { id: connectProc; onRunningChanged: if (!running) stateProc.running = true }
  Process { id: disconnectProc; onRunningChanged: if (!running) stateProc.running = true }
}
