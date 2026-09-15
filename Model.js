// Pure logic for the Wireless Display panel. No Quickshell/QML imports here —
// keep this testable the same way panels/monitor/Model.js and
// panels/bluetooth/Model.js are: plain functions over plain data.
//
// State shape produced by `omarchy-wireless-display-ctl state`:
//
// {
//   "status": "idle" | "discovering" | "pairing" | "negotiating" | "streaming" | "error",
//   "error": "",
//   "pending": null | { "id", "name", "protocol", "mode", "output" },
//   "connected": [ { "id", "name", "protocol", "mode", "output" } ],
//   "peers": [ { "id", "name", "protocol", "signal", "state" } ]
// }
//
// `connected` is a list because the panel renders one box per connected
// display. It holds at most one today — waycast is a single-session process
// — but nothing in the panel assumes that, so lifting the limit is a backend
// change alone.
//
// "protocol" is what makes this the *wireless display* panel rather than the
// *Miracast* panel: only "miracast" peers are produced today, but nothing
// branches on protocol beyond picking a label, so a future AirPlay backend
// needs no shell-side rework.

function parseState(raw) {
  var parsed
  try {
    parsed = raw ? JSON.parse(String(raw)) : {}
  } catch (e) {
    parsed = {}
  }
  if (!parsed || typeof parsed !== "object") parsed = {}

  var connected = Array.isArray(parsed.connected)
    ? parsed.connected.filter(isValidPeer)
    : []
  var peers = Array.isArray(parsed.peers) ? parsed.peers.filter(isValidPeer) : []

  return {
    status: typeof parsed.status === "string" ? parsed.status : "idle",
    error: typeof parsed.error === "string" ? parsed.error : "",
    pending: isValidPeer(parsed.pending) ? parsed.pending : null,
    connected: connected,
    peers: sortPeers(peers)
  }
}

function isValidPeer(peer) {
  return !!peer && typeof peer === "object" && typeof peer.id === "string" && peer.id !== ""
}

// One list, connected first, the way the panel draws it.
//
// The connected display and the discovered peers are separate fields in the
// state file, and the same display can legitimately appear in both while a
// session is being set up. Merging here rather than rendering two sections
// means the panel never shows one display twice, and a display that is
// connected keeps its position in the list instead of jumping between
// sections as it connects and disconnects.
//
// `pending` is folded in too, so the display being connected to shows its
// progress in place rather than vanishing until the session is up.
function displays(state) {
  var out = []
  var seen = {}

  function push(entry, connected, pending) {
    if (!entry || seen[entry.id]) return
    seen[entry.id] = true
    out.push({
      id: entry.id,
      name: peerLabel(entry),
      protocol: entry.protocol,
      mode: entry.mode || "",
      output: entry.output || "",
      connected: !!connected,
      pending: !!pending
    })
  }

  state.connected.forEach(function(d) { push(d, true, false) })
  push(state.pending, false, true)
  sortPeers(state.peers).forEach(function(p) { push(p, false, false) })
  return out
}

function hasConnected(state) {
  return state.connected.length > 0
}

function sortPeers(peers) {
  return peers.slice().sort(function(a, b) {
    var aSignal = isFinite(a.signal) ? Number(a.signal) : -1
    var bSignal = isFinite(b.signal) ? Number(b.signal) : -1
    if (aSignal !== bSignal) return bSignal - aSignal
    return peerLabel(a).localeCompare(peerLabel(b))
  })
}

function peerLabel(peer) {
  if (!peer) return ""
  var name = String(peer.name || "").trim()
  return name !== "" ? name : String(peer.id || "").trim()
}

// Short, protocol-neutral badge text. Deliberately not "WFD"/"Miracast" as
// the only case handled forever — add a branch here, not a new field on the
// panel, when the AirPlay backend lands.
function protocolLabel(protocol) {
  switch (protocol) {
    case "miracast": return "Miracast"
    case "airplay": return "AirPlay"
    default: return protocol ? String(protocol) : "Wireless"
  }
}

function modeLabel(mode) {
  return mode === "mirror" ? "Mirroring" : "Extending"
}

// What a connected display is doing, and where. Extend mode names the output
// Hyprland created so it can be matched against `hyprctl monitors`; mirroring
// creates no output, so there is nothing to name.
function displayDetail(display) {
  if (!display) return ""
  var label = modeLabel(display.mode)
  var output = String(display.output || "").trim()
  return output !== "" ? label + " · " + output : label
}

// The line under the title. The mockup puts the connection state here, so
// this is what the panel shows instead of a fixed description once anything
// is happening.
function headerSubtitle(state) {
  switch (state.status) {
    case "discovering": return "Searching for displays…"
    case "pairing":
    case "negotiating":
      return state.pending
        ? "Connecting to " + peerLabel(state.pending) + "…"
        : "Connecting…"
    case "streaming":
      return state.connected.length === 1
        ? "Connected to " + peerLabel(state.connected[0])
        : state.connected.length + " displays connected"
    case "error": return "Connection failed"
    default: return "Mirror or extend onto a Miracast display"
  }
}

// What a row says under the display's name. Disconnected rows carry just the
// protocol, as the mockup has it; a connected row also names the mode it
// actually negotiated. The row's own Extend switch reports the same thing
// while the display is live, so this is the second place it appears -- kept
// because the switch says "extend or not" and this says what that means.
function displaySubtitle(display) {
  var label = protocolLabel(display.protocol)
  if (display.connected && display.mode) {
    return label + " · " + modeLabel(display.mode)
  }
  return label
}

function statusText(state) {
  switch (state.status) {
    case "discovering": return "Looking for displays…"
    case "pairing": return "Pairing…"
    case "negotiating":
      return state.pending
        ? "Connecting to " + peerLabel(state.pending) + "…"
        : "Connecting…"
    case "streaming":
      return state.connected.length === 1
        ? modeLabel(state.connected[0].mode) + " onto " + peerLabel(state.connected[0])
        : state.connected.length + " displays connected"
    case "error": return state.error || "Connection failed"
    default:
      return state.peers.length > 0
        ? state.peers.length + " display" + (state.peers.length === 1 ? "" : "s") + " found"
        : "No wireless display connected"
  }
}

// Bar-chip glyph. All verified present in CaskaydiaMono Nerd Font — the
// obvious plain-Unicode choices (↻ U+21BB, ⏏ U+23CF, ✕ U+2715) are *not* in
// it and render as blanks, so every symbol here is a Nerd Font one.
function statusIcon(state) {
  switch (state.status) {
    case "discovering": return "󰕐"
    case "pairing":
    case "negotiating": return "󰦟"
    case "streaming": return "󰍹"
    case "error": return "󰀦"
    default: return "󰐹"
  }
}

// A session owns the backend when one is connected or being connected.
//
// Both of these read the same two fields the control script's own
// `session_active` reads, deliberately. They used to be phrased in terms of
// `status`, which made them a second, subtly different rule: "error" counted
// as scannable here and as not-scannable there, so the rescan button was
// offered after a failed connect and then did nothing when pressed.
function isBusy(state) {
  return state.pending !== null
}

// Discovery contends with an active session for the Wi-Fi radio, so
// rescanning yields to one -- but anything else, an error included, is a
// valid moment to look again.
function canScan(state) {
  return state.pending === null && state.connected.length === 0
}

if (typeof module !== "undefined") {
  module.exports = {
    parseState: parseState,
    isValidPeer: isValidPeer,
    displays: displays,
    hasConnected: hasConnected,
    headerSubtitle: headerSubtitle,
    displaySubtitle: displaySubtitle,
    sortPeers: sortPeers,
    peerLabel: peerLabel,
    protocolLabel: protocolLabel,
    modeLabel: modeLabel,
    displayDetail: displayDetail,
    statusText: statusText,
    statusIcon: statusIcon,
    isBusy: isBusy,
    canScan: canScan
  }
}
