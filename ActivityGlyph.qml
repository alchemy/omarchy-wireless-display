import QtQuick
import qs.Commons

// A glyph that shows activity by breathing rather than spinning.
//
// Spinning was tried twice and abandoned. Ui/Button's `iconSpinning` rotates
// about the centre of the glyph's advance box, which for a Nerd Font mark in
// a monospaced family is not where the mark is: measured for the refresh
// glyph (U+F0453), the advance is one cell while the ink is half again wider
// and overflows it, so the mark orbits a point beside itself.
//
// Correcting that with TextMetrics does centre the *bounding box* -- verified
// against the running shell, rotation origin landing on the item's exact
// centre -- and it still reads as eccentric, because the mark is a circular
// arrow with an arrowhead. The box centre is pulled off the arc's centre by
// that spur, and the eye follows the arc. Short of rasterising the outline to
// find its optical centre, per glyph and per font, rotation cannot be made to
// look right here.
//
// A pulse has no centre to get wrong, stays honest at any glyph or size, and
// reads as "working" just as well.
Item {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.icon
  property color color: Color.foreground
  property bool active: false
  property int period: 1100

  implicitWidth: glyph.implicitWidth
  implicitHeight: glyph.implicitHeight

  Text {
    id: glyph
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    opacity: 1.0
    
    SequentialAnimation on opacity {
      running: root.active
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.35; duration: root.period / 2; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: root.period / 2; easing.type: Easing.InOutSine }
    }

    // Leaving the animation mid-fade would strand the glyph dim.
    onOpacityChanged: if (!root.active && opacity !== 1.0) opacity = 1.0
  }
}
