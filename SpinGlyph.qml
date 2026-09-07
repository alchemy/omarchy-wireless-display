import QtQuick
import qs.Commons

// A glyph that can spin without wobbling.
//
// Rotating a Text about Item.Center -- which is what Ui/Button's
// `iconSpinning` does -- turns it about the centre of its *advance box*, not
// the centre of the mark that is drawn. For a Nerd Font glyph in a monospaced
// family those are not the same point: measured for the refresh glyph
// (U+F0453) in CaskaydiaMono Nerd Font at 16px, the advance is one 9.38px
// cell while the ink spans 14.00px and overflows it. The ink centre lands
// 2.31px right of the advance centre, so the mark orbits a point beside
// itself. Vertically they coincide exactly, which is why the wobble reads as
// purely side-to-side.
//
// TextMetrics reports the ink bounds, so the mark can be placed with its own
// centre at this item's centre and spun about that. Qt gives
// tightBoundingRect relative to the text origin with y measured from the
// baseline, negative above it -- hence adding baselineOffset to reach the
// text item's own coordinates.
//
// The item sizes itself from the ink rather than the advance, so a rotating
// glyph reserves the room it actually sweeps instead of overflowing whatever
// contains it.
Item {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.icon
  property color color: Color.foreground
  property bool spinning: false
  property int period: 900

  readonly property rect _ink: metrics.tightBoundingRect
  readonly property bool _inkUsable: _ink.width > 0 && _ink.height > 0

  readonly property real _inkCenterX: _ink.x + _ink.width / 2
  readonly property real _inkCenterY: glyph.baselineOffset + _ink.y + _ink.height / 2

  // Square, so the mark occupies the same room at every angle.
  readonly property real _extent: Math.ceil(Math.max(_ink.width, _ink.height))
  implicitWidth: _inkUsable ? _extent : glyph.implicitWidth
  implicitHeight: _inkUsable ? _extent : glyph.implicitHeight

  TextMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    text: root.text
  }

  Text {
    id: glyph
    textFormat: Text.PlainText
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.fontSize

    // Offset so the ink's centre coincides with this item's centre. Falls
    // back to plain centring if the metrics are unusable -- an empty string,
    // or a glyph the font lacks -- since a slight wobble beats a mark
    // hanging off its own button.
    x: root._inkUsable ? root.width / 2 - root._inkCenterX : (root.width - implicitWidth) / 2
    y: root._inkUsable ? root.height / 2 - root._inkCenterY : (root.height - implicitHeight) / 2

    transform: Rotation {
      origin.x: root._inkUsable ? root._inkCenterX : glyph.implicitWidth / 2
      origin.y: root._inkUsable ? root._inkCenterY : glyph.implicitHeight / 2
      angle: spin.angle
    }
  }

  QtObject {
    id: spin
    property real angle: 0
  }

  NumberAnimation {
    target: spin
    property: "angle"
    from: 0
    to: 360
    duration: root.period
    loops: Animation.Infinite
    running: root.spinning
    onRunningChanged: if (!running) spin.angle = 0
  }
}
