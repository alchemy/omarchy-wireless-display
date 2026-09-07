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
// display. It holds at most one today — swaybeam is a single-session process
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

// Displays offering a connection: everything discovered that isn't already
// connected, and isn't the one mid-connect. Without this filter a display
// appears in both lists at once during the handover from pending to connected.
function availablePeers(state) {
  var taken = {}
  state.connected.forEach(function(d) { taken[d.id] = true })
  if (state.pending) taken[state.pending.id] = true
  return state.peers.filter(function(p) { return !taken[p.id] })
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

function modeIcon(mode) {
  return mode === "mirror" ? "󰽛" : "󰍺"
}

// A connect is in flight, so a second one must not start.
function isBusy(state) {
  return state.status === "pairing" || state.status === "negotiating"
}

// Discovery contends with an active session for the Wi-Fi interface, so
// rescanning is only offered when nothing is connected or connecting.
function canScan(state) {
  return !isBusy(state) && state.connected.length === 0
}

if (typeof module !== "undefined") {
  module.exports = {
    parseState: parseState,
    isValidPeer: isValidPeer,
    availablePeers: availablePeers,
    sortPeers: sortPeers,
    peerLabel: peerLabel,
    protocolLabel: protocolLabel,
    modeLabel: modeLabel,
    displayDetail: displayDetail,
    statusText: statusText,
    statusIcon: statusIcon,
    modeIcon: modeIcon,
    isBusy: isBusy,
    canScan: canScan
  }
}
