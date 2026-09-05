// Pure logic for the Wireless Display panel. No Quickshell/QML imports here —
// keep this testable the same way panels/monitor/Model.js and
// panels/bluetooth/Model.js are: plain functions over plain data, unit-tested
// under test/shell.d/ once this plugin lands in the main tree.
//
// State shape produced by `omarchy-wireless-display-ctl state` (see
// ../ARCH.md for the daemon design this stubs out):
//
// {
//   "status": "idle" | "discovering" | "pairing" | "negotiating" | "streaming" | "error",
//   "error": "",
//   "activePeer": null | { "id", "name", "protocol" },
//   "activeOutput": "",
//   "peers": [ { "id", "name", "protocol", "signal", "state" } ]
// }
//
// "protocol" is what makes this the *wireless display* panel rather than the
// *Miracast* panel: today only "miracast" peers are ever produced, but the
// panel and this model never branch on protocol beyond picking a label/icon
// for it, so a future "airplay" backend needs no shell-side rework.

function parseState(raw) {
  var parsed
  try {
    parsed = raw ? JSON.parse(String(raw)) : {}
  } catch (e) {
    parsed = {}
  }
  if (!parsed || typeof parsed !== "object") parsed = {}

  var peers = Array.isArray(parsed.peers) ? parsed.peers.filter(isValidPeer) : []

  return {
    status: typeof parsed.status === "string" ? parsed.status : "idle",
    error: typeof parsed.error === "string" ? parsed.error : "",
    activePeer: isValidPeer(parsed.activePeer) ? parsed.activePeer : null,
    activeOutput: typeof parsed.activeOutput === "string" ? parsed.activeOutput : "",
    peers: sortPeers(peers)
  }
}

function isValidPeer(peer) {
  return !!peer && typeof peer === "object" && typeof peer.id === "string" && peer.id !== ""
}

// Connected/active peer first, then by signal strength (missing signal sorts
// last), stable otherwise — mirrors the "connected, known, discovered" triage
// bluetooth's Model.js does, collapsed to one list since a wireless display
// has no persistent pairing/"known devices" concept the way Bluetooth does.
function sortPeers(peers) {
  return peers.slice().sort(function(a, b) {
    var aConnected = a.state === "connected" ? 1 : 0
    var bConnected = b.state === "connected" ? 1 : 0
    if (aConnected !== bConnected) return bConnected - aConnected

    var aSignal = isFinite(a.signal) ? Number(a.signal) : -1
    var bSignal = isFinite(b.signal) ? Number(b.signal) : -1
    return bSignal - aSignal
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

function statusText(state) {
  switch (state.status) {
    case "discovering": return "Looking for displays…"
    case "pairing": return "Pairing…"
    case "negotiating": return "Connecting…"
    case "streaming":
      return state.activePeer
        ? "Extending onto " + peerLabel(state.activePeer)
        : "Extending desktop"
    case "error": return state.error || "Connection failed"
    default: return "No wireless display connected"
  }
}

// Bar-chip glyph. Placeholder nerd-font-ish glyphs matching the style of
// monitor/bluetooth's icon properties — swap for real ones when this is
// wired into a live shell checkout.
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

function isBusy(state) {
  return state.status === "pairing" || state.status === "negotiating"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseState: parseState,
    isValidPeer: isValidPeer,
    sortPeers: sortPeers,
    peerLabel: peerLabel,
    protocolLabel: protocolLabel,
    statusText: statusText,
    statusIcon: statusIcon,
    isBusy: isBusy
  }
}
