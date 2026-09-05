# omarchy-wireless-display (plugin)

Omarchy Quickshell plugin described in `../ARCH.md`. The shell-side contract
(manifest, panel, model, CLI shape) and the backend it drives
(`bin/omarchy-wireless-display-ctl`, wrapping a patched `swaybeam`) are both
real now — see "Backend" below for exactly what has and hasn't been
exercised against real hardware.

## What's here

| File | Role |
|---|---|
| `manifest.json` | Plugin manifest — `kind: bar-widget`, entry point `Panel.qml`. Modeled on `panels/monitor/manifest.json` and `panels/bluetooth/manifest.json` in the Omarchy repo. |
| `Panel.qml` | Bar chip + popup. Modeled on `panels/monitor/Panel.qml` (bash-script-plus-`Process`-plus-JSON backend, no native Quickshell service exists for this) and `panels/bluetooth/Panel.qml` (discover → pick → connect list, scan-while-open discovery-session ownership). |
| `Model.js` | Pure functions over the state JSON — parsing, sorting, labels, status text/icon. No QML imports, so it can be unit-tested the same way `panels/monitor/Model.js` is. |
| `bin/omarchy-wireless-display-ctl` | Control CLI. Subcommands: `state`, `scan-start`, `scan-stop`, `connect <peer-id>`, `disconnect` — unchanged surface from the original stub, so `Panel.qml` needed zero edits when the backend swapped from fake to real. |

## Backend

`omarchy-wireless-display-ctl` wraps the patched swaybeam fork at
`/home/five/Work/alchemy/swaybeam` (branch `hyprland-support`):

- `scan-start`/`scan-stop` run `swaybeam --json discover --timeout N` in the
  background and land its results into the state file's `peers[]`.
- `connect <id>` launches `swaybeam --json daemon --sink <id> --extend
  --audio` as a background process and tails its JSON-Lines event stream
  (`{"event": "started" | "discovered" | "connected" |
  "virtual_output_created" | "negotiated" | "streaming_started" | "error" |
  "ended", ...}` — see that fork's `crates/cli`'s `daemon_event_json()`,
  pinned by a unit test there) into this plugin's state file, via
  `apply_event()` in the ctl script.
- `disconnect` sends the daemon process `SIGINT` (which its `run()` is
  specifically waiting on to trigger graceful teardown — stop the stream,
  disconnect P2P, remove the headless output, restore `xdph.conf`), with a
  bounded grace period before falling back to `SIGKILL`.

**Verified live, on this machine's real Hyprland session:**
- `swaybeam --json discover` and `--json daemon` (empty-discovery/error
  path) — see ARCH.md, "Wire both into a daemon".
- The Hyprland `VirtualOutput` backend in isolation (`hyprctl output
  create/remove`, `xdph.conf` auto-target, byte-for-byte restore) — see
  ARCH.md, "Build vs. adopt: swaybeam".
- This ctl script's `state`/`scan-start`/`scan-stop`/`connect`/`disconnect`
  against the real (empty) discovery results and the unknown-peer error
  path — confirmed `connect` on an unrecognized id never spawns `swaybeam`.

**Not verified live:** the actual connect → pairing → negotiating →
streaming → extend happy path, and the `SIGKILL` fallback's known gap
(swaybeam's Rust `Drop`-based cleanup doesn't run on `SIGKILL`, so a forced
kill would leak a headless output and a stale `xdph.conf` edit) — both need
a real Miracast sink on the network, which this machine doesn't have access
to. Treat the happy path as designed-and-wired, not confirmed working, until
that's run against real hardware.

## The contract that survives the stub → real daemon swap

`Panel.qml`/`Model.js` only ever see this JSON (from `omarchy-wireless-display-ctl state`):

```json
{
  "status": "idle | discovering | pairing | negotiating | streaming | error",
  "error": "",
  "activePeer": null,
  "activeOutput": "",
  "peers": [
    {"id": "aa:bb:cc:dd:ee:01", "name": "Living Room TV", "protocol": "miracast", "signal": 82, "state": "available | connected"}
  ]
}
```

`protocol` on each peer is what makes this the *wireless display* plugin
rather than the *Miracast* plugin (see `../ARCH.md`, "Future: multi-protocol
support") — the panel only uses it to pick a label, never to branch logic.

## Try it locally

```bash
export PATH="$PWD/bin:$PATH"
export OMARCHY_WIRELESS_DISPLAY_SWAYBEAM_BIN=/home/five/Work/alchemy/swaybeam/target/debug/swaybeam

omarchy-wireless-display-ctl scan-start
sleep 5 && omarchy-wireless-display-ctl state | jq .   # real swaybeam discover; empty without a real sink nearby
omarchy-wireless-display-ctl connect aa:bb:cc:dd:ee:01 # "Unknown peer" unless that id came from a real scan
omarchy-wireless-display-ctl disconnect
```

To see the QML mounted in a live shell, symlink this directory into the
user-plugin location and restart/reload the shell:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/omarchy-wireless-display
```

(Per `shell/plugins/README.md` in the Omarchy repo: user-installed plugins
live under `~/.config/omarchy/plugins/<plugin-id>/` and use the identical
manifest contract first-party plugins do — the shell just doesn't flag them
`__isFirstParty: true`.)

## Known gaps in this pass

- No real bar-popup anchoring (`PanelController`/popout host) is wired up —
  `visible: root.opened` stands in for it. Drop this into a live checkout
  and follow `panels/monitor/Panel.qml`'s popout structure to wire it for
  real.
- No keyboard cursor navigation (bluetooth/monitor's `moveCursor`/`h`/`l`
  handling) — mouse-only for now.
- `id` in `manifest.json` (`omarchy-wireless-display`) is a flat placeholder.
  Third-party plugins in the wild (e.g. `omarchy-airplay`) use reverse-DNS
  ids like `io.github.<user>.omarchy-wireless-display` — rename before any
  public listing if that convention matters.
- The connect → streaming happy path and the `SIGKILL` cleanup-leak edge
  case are wired but not verified live — see "Backend" above.
- No AirPlay backend yet (`protocol` will only ever be `"miracast"` today)
  — see `../ARCH.md`, "Future: multi-protocol support".
