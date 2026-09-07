# Wireless Display

An [Omarchy](https://omarchy.org) shell plugin that finds Miracast displays —
TVs, dongles — and **extends** your desktop onto one, as a real second
monitor you can drag windows to. Not mirroring: Hyprland sees an additional
output.

Adds a bar widget that scans for displays, connects, and shows session
state. The actual casting is done by [swaybeam](https://github.com/alchemy/swaybeam);
this plugin discovers, drives and monitors it.

> **Status: early.** The casting pipeline is confirmed working against a real
> LG webOS TV — picture, extended desktop, working mouse and keyboard. The
> panel UI is young: mouse-only, no keyboard navigation. Expect rough edges,
> and read *Troubleshooting* before filing a bug — most failures are host
> configuration, not the plugin.

## Requirements

**Compositor.** Hyprland 0.55 or newer (Omarchy Quattro). Older Hyprland
used a different config engine and won't work.

**swaybeam — from the fork, not upstream.** Upstream swaybeam's extend mode
is Sway-only; the Hyprland support lives on a branch:

```bash
sudo pacman -S --needed \
    rust gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly \
    pipewire wireplumber networkmanager wpa_supplicant \
    xdg-desktop-portal xdg-desktop-portal-hyprland

git clone -b hyprland-support https://github.com/alchemy/swaybeam.git
cd swaybeam
# Installs to ~/.local/bin, deliberately: the shell launches the plugin's
# helper, and a graphical session's PATH generally does not include
# ~/.cargo/bin (cargo adds that to your *interactive* shell only). Install
# it there and the plugin reports no displays no matter what.
cargo install --path crates/cli --bin swaybeam --root ~/.local
swaybeam doctor                                  # sanity-check the system
```

**Wi-Fi hardware** that can do Wi-Fi Direct alongside your normal
connection. Check:

```bash
iw list | grep -A 3 "valid interface combinations"
```

You want a line offering `managed` together with `P2P-client`/`P2P-GO`.

**Optional but recommended — hardware encoding.** Without it, 1080p H.264 is
encoded on the CPU, which costs battery and adds latency:

```bash
sudo pacman -S intel-media-driver gst-plugin-va   # Intel, Broadwell or newer
# AMD: mesa-va-drivers (usually already installed)
```

### Host setup (required — casting will silently fail without it)

Miracast has the *sink* open a TCP connection back to your machine, so port
7236 must be reachable, and the Wi-Fi Direct interface must not be filtered.
Both defaults on a typical Arch/Omarchy install block this, and the failure
is silent — the TV just never connects.

```bash
# 1. Firewall — do whichever applies to you. Check both; they stack.
sudo ufw allow 7236/tcp                              # if ufw is in use
#    for nftables, add to the input chain of /etc/nftables.conf:
#      tcp dport 7236 accept comment "Miracast/WFD RTSP"
#    then: sudo systemctl restart nftables

# 2. Reverse-path filtering — strict mode drops packets arriving on the
#    Wi-Fi Direct interface, before any firewall rule can allow them.
sudo sysctl -w net.ipv4.conf.all.rp_filter=2
sudo sysctl -w net.ipv4.conf.default.rp_filter=2
printf 'net.ipv4.conf.all.rp_filter=2\nnet.ipv4.conf.default.rp_filter=2\n' \
    | sudo tee /etc/sysctl.d/99-miracast-rpf.conf   # persist across reboots
```

`ufw` is worth checking even if you don't think you use it: `systemctl
is-active ufw` reporting `inactive` does **not** mean its rules are
unloaded.

## Install

```bash
git clone https://github.com/alchemy/omarchy-wireless-display.git \
    ~/.config/omarchy/plugins/omarchy-wireless-display
```

Then enable it and reload the shell:

```bash
omarchy plugin enable omarchy-wireless-display
omarchy restart shell
```

A **Wireless Display** icon (󰐹) appears in the bar. The icon doubles as the
status indicator: 󰕐 scanning, 󰦟 connecting, 󰍹 streaming, 󰀦 error.

Every symbol in the panel is a Nerd Font glyph. The obvious plain-Unicode
choices for these controls -- ↻ (U+21BB), ⏏ (U+23CF), ✕ (U+2715) -- are *not*
in CaskaydiaMono Nerd Font and render as blank boxes, so they are not used.

The plugin finds its own bundled helper script, so nothing needs adding to
your `PATH` for it — only `swaybeam` has to be reachable, per above.

## Using it

On the TV, open its screen-sharing mode first — on LG webOS that's *Home
Dashboard → Screen Share*. Most TVs only accept Miracast connections while
that screen is open.

Then click the bar widget. The panel has three parts:

- **Header** — the plugin's name and what it does, with 󰑓 to scan again. It
  scans automatically while the panel is open; the button is for when a
  display was switched on late. It is disabled while a display is connected,
  because discovery and an active session contend for the Wi-Fi radio.
- **Connected** — one box per connected display, showing whether it is
  mirroring or extending (and, for extend, which output Hyprland created),
  with 󰖭 to disconnect.
- **Available** — one box per display found, each offering **Mirror** and
  **Extend** directly. They are equal choices, not a default and an option.

**Extend** (󰍺) creates a new 1080p output that Hyprland treats as an ordinary
second monitor, so you can drag windows onto it.

**Mirror** (󰽛) duplicates an existing screen instead. Because no new output is
created, the desktop portal asks which screen to share — that dialog is
expected, and you pick your monitor there. Extend does not ask, since the
plugin points the portal at the output it just created.

If your screen and the display have different shapes — a 16:10 laptop panel
mirroring to a 16:9 TV, say — the picture is letterboxed rather than
stretched.

The first connection usually prompts on the TV to accept the device —
approve it there. Later connections from the same machine generally don't
re-ask.

### From the terminal

The panel is a front-end for a script you can drive directly:

```bash
omarchy-wireless-display-ctl scan-start
omarchy-wireless-display-ctl state | jq .
omarchy-wireless-display-ctl extend <peer-id>     # or: connect <peer-id> extend
omarchy-wireless-display-ctl mirror <peer-id>     # or: connect <peer-id> mirror
omarchy-wireless-display-ctl disconnect
```

`connect` defaults to `extend` when no mode is given.

`state` prints the same JSON the panel reads — useful for scripting or for
seeing exactly where a connection stalled.

## Troubleshooting

**Nothing is found when scanning.** Confirm the TV's screen-share mode is
open. Then check the interface: the underlying tool defaults to `wlan0`,
which is not what most current systems call their Wi-Fi. The plugin
autodetects yours, but you can force it:

```bash
iw dev | grep Interface
OMARCHY_WIRELESS_DISPLAY_INTERFACE=wlp3s0 omarchy-wireless-display-ctl scan-start
```

**The panel always says "No wireless displays found", even with the TV
ready.** Most likely the shell can't see `swaybeam`. Its `PATH` is the
graphical session's, not your terminal's — so a `swaybeam` you can run in a
terminal may still be invisible to the plugin:

```bash
tr '\0' '\n' < /proc/$(pgrep -f 'quickshell.*omarchy' | head -1)/environ | grep ^PATH
```

If the directory holding `swaybeam` isn't in there, reinstall it somewhere
that is (`--root ~/.local`, as above).

**Connects, then fails a few seconds later; the TV shows an error.** Almost
always the host setup above — most often the firewall. The tell is that the
TV's connection attempts get no reply at all. Verify with:

```bash
sudo nft list ruleset | grep 7236     # is the port actually allowed?
nstat -az | grep IPReversePathFilter  # climbing? rp_filter is dropping packets
```

**Connects, but the TV just shows a spinner — no picture.** The TV is
receiving a stream it can't decode. This plugin sends 1080p precisely to
avoid that; if you see it anyway, your sink may want something narrower.

**Worked once, now every reconnect times out.** Give the TV 30–60 seconds.
Sinks commonly need to fully reset a session before accepting a new one, and
rapid reconnects fail reliably until they do.

**A screen-share in another app grabbed the wrong display.** Shouldn't
happen — the portal override is armed for exactly one request, immediately
before this plugin's own. If you hit it, that's a real bug worth reporting.

**Check the raw session log** when the panel just says `error`:

```bash
cat "$XDG_RUNTIME_DIR/omarchy-wireless-display/daemon.jsonl"   # state transitions
cat "$XDG_RUNTIME_DIR/omarchy-wireless-display/daemon.err"     # stderr
```

## Limitations

- **1080p, not 4K.** Not a shortcut: classic Miracast has no 4K in its
  negotiable resolution set, so 4K-capable TVs still cap at 1920×1080 here.
- **Miracast only.** The plugin is built protocol-agnostically (peers carry
  a `protocol` field) with AirPlay in mind, but no AirPlay backend exists.
- **No signal strength** — the discovery layer doesn't report it, so the
  list can't sort or display it.
- **No keyboard navigation** in the panel yet; mouse only.
- **One display at a time.** The panel lists connected displays as a list and
  would render several, but the backend refuses a second: swaybeam holds the
  Wi-Fi P2P interface and, in extend mode, an edit to `xdph.conf`, and two
  sessions fight over both.
- **Mirroring shows the portal's screen-share dialog**, because nothing arms
  the plugin's one-shot picker override outside extend mode. Removing that
  prompt needs a swaybeam change (arming the picker for a named existing
  output), not a plugin one.
- **Reconnects need a cooldown**, per *Troubleshooting*.
- **A forced kill leaks state.** `SIGKILL` skips cleanup, leaving a stray
  headless output. The next run detects and clears it automatically; a
  normal quit, `SIGINT` or `SIGTERM` all clean up properly.

## Configuration

Environment variables read by the control script:

| Variable | Default | Purpose |
|---|---|---|
| `OMARCHY_WIRELESS_DISPLAY_INTERFACE` | autodetected | Wi-Fi interface for discovery |
| `OMARCHY_WIRELESS_DISPLAY_SWAYBEAM_BIN` | `swaybeam` | Path to the swaybeam binary |
| `OMARCHY_WIRELESS_DISPLAY_DISCOVER_TIMEOUT` | `8` | Scan duration, seconds |
| `OMARCHY_WIRELESS_DISPLAY_DISCONNECT_GRACE_SECONDS` | `10` | Teardown grace before force-kill |

## License

MIT — see [LICENSE](LICENSE).
