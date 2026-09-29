import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import qs.Commons
import qs.Ui

// The plugin's status mark: the monitor glyph the stock monitor plugin uses,
// with wireless waves drawn inside its screen, or a warning sign on error.
//
// The monitor is the font's own glyph, placed by the shell's OpticalGlyph
// exactly as a plain bar icon would be, so its bezel matches the monitor
// plugin's pixel for pixel. Only what goes inside the screen is drawn.
//
// That space is small. In the bar the glyph is 13px, which leaves a screen
// about ten by seven logical pixels -- eight device rows at 1.25x scaling,
// under seven at 1x. Waves positioned in logical units land between device
// pixels there and antialias into a grey smudge, so they are laid out in
// device pixels instead: whole-pixel strokes, whole-pixel gaps, each arc's
// crest on a pixel row. As many of the three waves are drawn as fit with two
// clear pixels between them: two in the bar at 1x-1.6x, where the screen is
// seven to nine rows tall, and all three at the panel header's size.
//
// Modes:
//   idle        waves dimmed -- ready, nothing happening; still distinct from
//               the plain monitor icon, which may sit beside it in the bar
//   scanning    waves appear one at a time, then all together, in a loop
//   connecting  all waves, breathing, as the pair button does
//   streaming   all waves at full strength
//   error       a warning sign inside the screen instead of waves
//
// Colour never carries the state. The shell's "active" colour is its urgent
// red, and a working stream shown in red would read as a fault.
Item {
  id: root

  property string mode: "idle"
  property color color: Color.foreground
  property string fontFamily: Style.font.family
  property real fontSize: Style.bar.iconFont

  readonly property string monitorGlyph: "\u{F0379}"   // md-monitor
  readonly property string warningGlyph: "\u{F0026}"   // md-alert

  // A standalone use -- the panel header -- sizes itself from the glyph. In
  // the bar the icon canvas sets the size and this is ignored.
  implicitWidth: Math.ceil(monitorMetrics.boundingRect.width)
  implicitHeight: Math.ceil(monitorMetrics.boundingRect.height)

  OpticalGlyph {
    id: monitor
    anchors.fill: parent
    text: root.monitorGlyph
    fontFamily: root.fontFamily
    fontSize: root.fontSize
    color: root.color
  }

  TextMetrics {
    id: monitorMetrics
    font.family: root.fontFamily
    font.pixelSize: monitor.renderedFontSize
    text: root.monitorGlyph
  }

  // --- where the screen is ---------------------------------------------
  //
  // Fractions of the glyph's ink box, measured from CaskaydiaMono's outline
  // at 400pt: the bezel is 9.2% of the ink width thick, and the screen spans
  // 9.2-90.5% of the width and 10.2-70.1% of the height; the rest is stand.

  readonly property real inkWidth: monitorMetrics.tightBoundingRect.width
  readonly property real inkHeight: monitorMetrics.tightBoundingRect.height
  readonly property real inkLeft: monitor.paintedCenterX - inkWidth / 2
  readonly property real inkTop: monitor.baselineY + monitorMetrics.tightBoundingRect.y

  // Device-pixel layout. `origin` is where this item sits in the window, so
  // that "a whole device pixel" means one on the screen, not one relative to
  // an item that may itself start mid-pixel.
  //
  // The ratio is the window's, not the screen's. Under Wayland fractional
  // scaling Screen.devicePixelRatio reports the integer buffer scale -- 2 on
  // both a 1.25x and a 1.6x output, measured in the shell -- so snapping to
  // it put every stroke off the real pixel grid.
  readonly property real dpr: {
    var w = root.Window.window
    if (w && w.devicePixelRatio > 0) return w.devicePixelRatio
    return Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  }
  property point origin: Qt.point(0, 0)

  function realign() {
    var p = root.mapToItem(null, 0, 0)
    if (p.x !== origin.x || p.y !== origin.y) origin = Qt.point(p.x, p.y)
  }

  // Nothing tells an item that an ancestor moved, and the bar lays its
  // widgets out after they are created -- measured in the shell, every copy
  // reported the same origin as its first sibling and snapped to a grid it
  // was not on. So every ancestor's position is watched, and the one-off
  // reads at creation and on resize are only a start.
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

  function toDeviceX(x) { return (origin.x + x) * dpr }
  function toDeviceY(y) { return (origin.y + y) * dpr }
  function fromDeviceX(d) { return d / dpr - origin.x }
  function fromDeviceY(d) { return d / dpr - origin.y }

  readonly property real screenLeft: Math.ceil(toDeviceX(inkLeft + inkWidth * 0.092))
  readonly property real screenRight: Math.floor(toDeviceX(inkLeft + inkWidth * 0.905))
  readonly property real screenTop: Math.ceil(toDeviceY(inkTop + inkHeight * 0.102))
  readonly property real screenBottom: Math.floor(toDeviceY(inkTop + inkHeight * 0.701))

  // Strokes a little lighter than the bezel, so the waves read as content
  // and not as more frame. `margin` keeps them off the bezel; `gap` keeps
  // them off each other, and is never under two pixels. One-pixel gaps were
  // tried and measured: three 1px arcs a pixel apart in the bar's seven rows
  // blend along their diagonals into a grey texture, however exactly each
  // crest lands. Two waves that stay apart read; three that touch do not.
  readonly property int stroke: Math.max(1, Math.round(inkWidth * 0.092 * dpr * 0.8))
  readonly property int margin: Math.max(1, Math.floor(stroke * 0.75))
  readonly property int gap: Math.max(2, Math.round(stroke * 0.75))
  readonly property int innerRadius: Math.max(3, 2 * stroke)
  readonly property int step: stroke + gap

  // Height a stack of n waves needs: from the innermost arc's ends -- the
  // lowest ink, at 45 degrees below its crest -- up to the outermost crest.
  function stackHeight(n) { return 0.293 * innerRadius + (n - 1) * step + stroke }
  readonly property int waveCount: {
    var room = (screenBottom - screenTop) - 2 * margin
    for (var n = 3; n > 0; n--) {
      if (stackHeight(n) <= room) return n
    }
    return 0
  }

  // The stack is centred in the screen, with its outermost crest on a pixel
  // boundary so every crest after it is too. An odd spare row goes above:
  // the waves rise from a source below them, and sitting a row high they
  // read as crowding the bezel.
  readonly property real crestTop: {
    var spare = (screenBottom - screenTop) - 2 * margin - stackHeight(Math.max(1, waveCount))
    return screenTop + margin + Math.ceil(Math.max(0, spare) / 2)
  }
  readonly property real centerDeviceX: (screenLeft + screenRight) / 2
  readonly property real centerDeviceY: crestTop + stroke / 2 + innerRadius + (Math.max(1, waveCount) - 1) * step

  function radius(k) { return (innerRadius + k * step) / dpr }

  // --- what is shown -----------------------------------------------------

  // One arc, `index` counting outward from the innermost.
  component Wave: ShapePath {
    required property int index
    readonly property bool shown: index < root.waveCount && index < root.lit
    strokeWidth: shown ? root.stroke / root.dpr : 0
    strokeColor: shown ? root.color : "transparent"
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    PathAngleArc {
      centerX: root.fromDeviceX(root.centerDeviceX)
      centerY: root.fromDeviceY(root.centerDeviceY)
      radiusX: root.radius(index)
      radiusY: root.radius(index)
      startAngle: -135
      sweepAngle: 90
      moveToStart: true
    }
  }

  // How many waves are lit. Everything but scanning shows them all.
  property int lit: waveCount

  Timer {
    id: scanTimer
    // One, two, three -- with three held for two beats, so the full mark is
    // seen before the loop starts over.
    interval: 380
    repeat: true
    running: root.mode === "scanning" && root.visible && root.waveCount > 0
    property int beat: 0
    onRunningChanged: {
      beat = 0
      root.lit = running ? 1 : root.waveCount
    }
    onTriggered: {
      beat = (beat + 1) % (root.waveCount + 1)
      root.lit = Math.min(beat + 1, root.waveCount)
    }
  }
  onWaveCountChanged: if (!scanTimer.running) lit = waveCount

  Shape {
    id: waves
    anchors.fill: parent
    visible: root.mode !== "error" && root.waveCount > 0
    preferredRendererType: Shape.CurveRenderer

    // Dimmed when idle: the mark says "ready" without claiming anything is
    // happening.
    opacity: root.mode === "idle" ? 0.45 : 1.0

    SequentialAnimation on opacity {
      running: root.mode === "connecting"
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.35; duration: 550; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 550; easing.type: Easing.InOutSine }
    }

    Wave { index: 0 }
    Wave { index: 1 }
    Wave { index: 2 }
  }

  // --- error ---------------------------------------------------------------

  // The font's own warning sign, fitted to the screen with a pixel's margin.
  // At the bar's size its exclamation mark is barely there; the triangle is
  // what reads, and it points up as a warning should.
  TextMetrics {
    id: warningMetrics
    font.family: root.fontFamily
    font.pixelSize: 100
    text: root.warningGlyph
  }

  Text {
    id: warning
    visible: root.mode === "error"
    textFormat: Text.PlainText
    text: root.warningGlyph
    color: root.color
    font.family: root.fontFamily
    // Grayscale outline rendering. At the fractional size this is fitted to,
    // the default path antialiased it with coloured subpixel fringes.
    renderType: Text.CurveRendering

    readonly property real room: (root.screenBottom - root.screenTop - 2 * root.margin) / root.dpr
    readonly property real roomWidth: (root.screenRight - root.screenLeft - 2 * root.margin) / root.dpr
    readonly property real scale100: Math.min(room / warningMetrics.tightBoundingRect.height,
                                              roomWidth / warningMetrics.tightBoundingRect.width)
    font.pixelSize: Math.max(1, 100 * scale100)

    x: root.fromDeviceX(root.centerDeviceX)
      - (warningMetrics.tightBoundingRect.x + warningMetrics.tightBoundingRect.width / 2) * scale100
    y: root.fromDeviceY((root.screenTop + root.screenBottom) / 2)
      - (warningMetrics.tightBoundingRect.y + warningMetrics.tightBoundingRect.height / 2) * scale100
      + warningMetrics.boundingRect.y * scale100
  }
}
