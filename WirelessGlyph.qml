import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import qs.Commons

// The plugin's status mark, after the Material "cast" icon: a standless
// monitor whose frame opens at the bottom-left corner, and from that corner a
// quarter-disc and two arcs -- the three waves.
//
// Modes:
//   idle        the full mark
//   scanning    the waves appear one at a time, then all together, in a loop
//   connecting  all three waves, fading in and out
//   streaming   the waves become one solid pie slice
//   error       the frame closes and a warning sign sits inside it
//
// Colour never carries the state. The shell's "active" colour is its urgent
// red, and a working stream shown in red would read as a fault.
//
// Everything is drawn, and drawn on the device-pixel grid. An earlier version
// put waves inside the font's monitor glyph, and in the bar that left them a
// screen seven device pixels tall: whatever was drawn there antialiased into
// a smudge. Drawing the whole mark gives the waves the corner of the full icon
// canvas, and lets every stroke land on whole pixels -- measured in the shell
// at 1.25x, the frame and the arcs are solid two-pixel strokes.
Item {
  id: root

  property string mode: "idle"
  property color color: Color.foreground
  property string fontFamily: Style.font.family
  // The size a glyph would be set at here. It only sizes a standalone use --
  // the panel header -- on the bar's own ratio of icon canvas to icon font. In
  // the bar the canvas sets the size and this is ignored.
  property real fontSize: Style.bar.iconFont

  readonly property string warningGlyph: "\u{F0026}"   // md-alert

  implicitWidth: Math.round(fontSize * Style.bar.iconCanvas / Style.bar.iconFont)
  implicitHeight: implicitWidth

  // --- the device grid ---------------------------------------------------
  //
  // The ratio is the window's, not the screen's. Under Wayland fractional
  // scaling Screen.devicePixelRatio reports the integer buffer scale -- 2 on
  // both a 1.25x and a 1.6x output, measured in the shell -- so snapping to
  // it put every stroke off the real grid.
  readonly property real dpr: {
    var w = root.Window.window
    if (w && w.devicePixelRatio > 0) return w.devicePixelRatio
    return Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  }

  // Where this item sits in the window, so that "a whole device pixel" means
  // one on the screen and not one relative to an item that may itself start
  // mid-pixel.
  property point origin: Qt.point(0, 0)

  function realign() {
    var p = root.mapToItem(null, 0, 0)
    if (p.x !== origin.x || p.y !== origin.y) origin = Qt.point(p.x, p.y)
  }

  // Nothing tells an item that an ancestor moved, and the bar lays its
  // widgets out after they are created -- measured in the shell, every copy
  // reported the same origin as its first sibling and snapped to a grid it
  // was not on. So every ancestor's position is watched.
  property var watched: []
  function watchAncestors() {
    unwatchAncestors()
    var list = []
    for (var item = root.parent; item; item = item.parent) {
      item.xChanged.connect(root.realign)
      item.yChanged.connect(root.realign)
      list.push(item)
    }
    watched = list
  }
  function unwatchAncestors() {
    for (var i = 0; i < watched.length; i++) {
      watched[i].xChanged.disconnect(root.realign)
      watched[i].yChanged.disconnect(root.realign)
    }
    watched = []
  }
  Component.onCompleted: { watchAncestors(); realign() }
  Component.onDestruction: unwatchAncestors()
  onParentChanged: { watchAncestors(); realign() }
  onXChanged: realign()
  onYChanged: realign()
  onWidthChanged: realign()
  onHeightChanged: realign()
  onVisibleChanged: realign()

  // Device coordinates back to this item's.
  function lx(d) { return d / dpr - origin.x }
  function ly(d) { return d / dpr - origin.y }

  // --- layout, in whole device pixels --------------------------------------
  //
  // The reference, in units of its stroke s: a frame 11s by 9s, a dot of
  // radius 1.5s, gaps of about s, and the frame opening 6.5s from the corner,
  // leaving a stub of 1.5s under the top stroke. Those are re-solved here in
  // whole pixels, the gap shrinking first when they do not all fit.
  readonly property int canvas: Math.floor(Math.min(width, height) * dpr)
  readonly property int frameWidth: Math.max(8, canvas - 2)
  readonly property int frameHeight: Math.round(frameWidth * 9 / 11)
  readonly property int stroke: Math.max(1, Math.round(frameWidth * 0.09))
  readonly property int dot: Math.max(2, Math.round(1.5 * stroke))
  readonly property int gap: Math.max(1, Math.min(stroke,
    Math.floor((frameHeight - 2.5 * stroke - dot - 2 * stroke) / 3)))
  readonly property int opening: dot + 3 * gap + 2 * stroke

  readonly property int frameLeft: Math.round(origin.x * dpr + (canvas - frameWidth) / 2)
  readonly property int frameTop: Math.round(origin.y * dpr + (canvas - frameHeight) / 2)
  readonly property int frameRight: frameLeft + frameWidth
  readonly property int frameBottom: frameTop + frameHeight

  // Centrelines of the arcs, counted outward from the dot.
  function arcRadius(k) { return dot + gap + stroke / 2 + k * (stroke + gap) }
  // The connected mark fills exactly the space the waves took.
  readonly property int pieRadius: dot + 2 * gap + 2 * stroke

  readonly property bool closed: mode === "error"

  // --- what is shown -------------------------------------------------------

  // Waves lit, of three: the dot, then each arc. Everything but scanning
  // shows them all.
  property int lit: 3

  Timer {
    // One, two, three -- with three held for two beats, so the full mark is
    // seen before the loop starts over.
    interval: 380
    repeat: true
    running: root.mode === "scanning" && root.visible
    property int beat: 0
    onRunningChanged: {
      beat = 0
      root.lit = running ? 1 : 3
    }
    onTriggered: {
      beat = (beat + 1) % 4
      root.lit = Math.min(beat + 1, 3)
    }
  }

  // A filled quarter-disc of the given radius in the frame's bottom-left
  // corner: the dot, or the connected mark's pie slice.
  component QuarterDisc: ShapePath {
    property real radius: 0
    strokeWidth: 0
    strokeColor: "transparent"
    startX: root.lx(root.frameLeft)
    startY: root.ly(root.frameBottom)
    PathLine { x: root.lx(root.frameLeft); y: root.ly(root.frameBottom - radius) }
    PathArc {
      x: root.lx(root.frameLeft + radius); y: root.ly(root.frameBottom)
      radiusX: radius / root.dpr; radiusY: radius / root.dpr
    }
    PathLine { x: root.lx(root.frameLeft); y: root.ly(root.frameBottom) }
  }

  // One arc about the same corner, `index` counting outward from the dot.
  component Wave: ShapePath {
    required property int index
    readonly property bool shown: index + 2 <= root.lit
    strokeWidth: shown ? root.stroke / root.dpr : 0
    strokeColor: shown ? root.color : "transparent"
    fillColor: "transparent"
    capStyle: ShapePath.FlatCap
    PathAngleArc {
      centerX: root.lx(root.frameLeft)
      centerY: root.ly(root.frameBottom)
      radiusX: root.arcRadius(index) / root.dpr
      radiusY: root.arcRadius(index) / root.dpr
      startAngle: -90
      sweepAngle: 90
      moveToStart: true
    }
  }

  // The frame, drawn along its centreline with flat ends where it opens.
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      id: frame
      readonly property real xl: root.frameLeft + root.stroke / 2
      readonly property real xr: root.frameRight - root.stroke / 2
      readonly property real yt: root.frameTop + root.stroke / 2
      readonly property real yb: root.frameBottom - root.stroke / 2
      readonly property real corner: root.stroke
      strokeWidth: root.stroke / root.dpr
      strokeColor: root.color
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      startX: root.lx(xl)
      startY: root.ly(root.frameBottom - root.opening)
      PathLine { x: root.lx(frame.xl); y: root.ly(frame.yt + frame.corner) }
      PathArc { x: root.lx(frame.xl + frame.corner); y: root.ly(frame.yt); radiusX: frame.corner / root.dpr; radiusY: frame.corner / root.dpr }
      PathLine { x: root.lx(frame.xr - frame.corner); y: root.ly(frame.yt) }
      PathArc { x: root.lx(frame.xr); y: root.ly(frame.yt + frame.corner); radiusX: frame.corner / root.dpr; radiusY: frame.corner / root.dpr }
      PathLine { x: root.lx(frame.xr); y: root.ly(frame.yb - frame.corner) }
      PathArc { x: root.lx(frame.xr - frame.corner); y: root.ly(frame.yb); radiusX: frame.corner / root.dpr; radiusY: frame.corner / root.dpr }
      PathLine {
        x: root.lx(root.closed ? frame.xl + frame.corner : root.frameLeft + root.opening)
        y: root.ly(frame.yb)
      }
    }

    // The rest of the frame, closing it, on error only. A path of its own:
    // a zero-radius arc still draws its chord, so leaving the segment in the
    // open frame with nothing to draw hooked its bottom edge up the left side.
    ShapePath {
      strokeWidth: root.closed ? root.stroke / root.dpr : 0
      strokeColor: root.closed ? root.color : "transparent"
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      startX: root.lx(frame.xl + frame.corner)
      startY: root.ly(frame.yb)
      PathArc { x: root.lx(frame.xl); y: root.ly(frame.yb - frame.corner); radiusX: frame.corner / root.dpr; radiusY: frame.corner / root.dpr }
      PathLine { x: root.lx(frame.xl); y: root.ly(root.frameBottom - root.opening) }
    }
  }

  Shape {
    id: waves
    anchors.fill: parent
    visible: root.mode === "idle" || root.mode === "scanning" || root.mode === "connecting"
    preferredRendererType: Shape.CurveRenderer

    SequentialAnimation on opacity {
      running: root.mode === "connecting"
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.2; duration: 550; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 550; easing.type: Easing.InOutSine }
    }

    QuarterDisc {
      radius: root.dot
      fillColor: root.lit >= 1 ? root.color : "transparent"
    }
    Wave { index: 0 }
    Wave { index: 1 }
  }

  Shape {
    anchors.fill: parent
    visible: root.mode === "streaming"
    preferredRendererType: Shape.CurveRenderer
    QuarterDisc { radius: root.pieRadius; fillColor: root.color }
  }

  // --- error ---------------------------------------------------------------

  // The font's warning sign, fitted inside the closed frame with a pixel's
  // margin, pointing up as a warning should.
  TextMetrics {
    id: warningMetrics
    font.family: root.fontFamily
    font.pixelSize: 100
    text: root.warningGlyph
  }

  Text {
    visible: root.mode === "error"
    textFormat: Text.PlainText
    text: root.warningGlyph
    color: root.color
    font.family: root.fontFamily
    // Grayscale outline rendering. At the fractional size this is fitted to,
    // the default path antialiased it with coloured subpixel fringes.
    renderType: Text.CurveRendering

    readonly property real roomHeight: (root.frameHeight - 2 * root.stroke - 2) / root.dpr
    readonly property real roomWidth: (root.frameWidth - 2 * root.stroke - 2) / root.dpr
    readonly property real k: Math.min(roomHeight / warningMetrics.tightBoundingRect.height,
                                       roomWidth / warningMetrics.tightBoundingRect.width)
    font.pixelSize: Math.max(1, 100 * k)

    x: root.lx((root.frameLeft + root.frameRight) / 2)
      - (warningMetrics.tightBoundingRect.x + warningMetrics.tightBoundingRect.width / 2) * k
    y: root.ly((root.frameTop + root.frameBottom) / 2)
      - (warningMetrics.tightBoundingRect.y + warningMetrics.tightBoundingRect.height / 2) * k
      + warningMetrics.boundingRect.y * k
  }
}
