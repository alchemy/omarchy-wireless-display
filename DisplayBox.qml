import QtQuick
import qs.Ui
import qs.Commons

// One display, as a bordered box: its name, a line of detail, and whatever
// controls the caller supplies on the trailing edge.
//
// Both display lists in the panel are the same shape -- only the detail line
// and the buttons differ -- so they share this rather than each hand-rolling
// a Rectangle and getting the padding subtly different.
BorderSurface {
  id: root

  property var bar: null
  property string title: ""
  property string subtitle: ""

  // Buttons for this display. A Component, not an Item, so each delegate gets
  // its own instance; see the note at the call site about `modelData` not
  // resolving inside it.
  property Component actions: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.4)

  color: Color.background
  borderSpec: Border.flat(dim, Math.max(1, Style.space(1)))
  radius: Style.cornerRadius

  implicitHeight: Math.max(labels.implicitHeight, actionLoader.implicitHeight)
    + Style.spacing.sm * 2

  // No leading glyph. Every row in both lists would carry the same one, so it
  // distinguished nothing -- the name and the mode line already say which
  // display this is and what it is doing.
  Column {
    id: labels
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.sm
    anchors.right: actionLoader.left
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: root.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      visible: root.subtitle !== ""
      width: parent.width
      text: root.subtitle
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Loader {
    id: actionLoader
    sourceComponent: root.actions
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
  }
}
