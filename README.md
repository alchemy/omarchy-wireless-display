# Wireless Display

Cast your Omarchy desktop to a TV over Wi-Fi — no cable, no dongle.

Adds a bar widget that finds Miracast displays and connects to them two ways:

- **Extend** — the TV becomes a second monitor you can drag windows onto.
- **Mirror** — the TV shows a copy of your existing screen.

Most Miracast tools only mirror. Extending is the point of this one.

> **Status: early.** Confirmed working against real hardware — an LG webOS TV
> and a Samsung Tizen TV — with picture, sound, and working mouse and
> keyboard. Expect rough edges, and read *If it doesn't work* before filing a
> bug: most failures are firewall settings rather than the plugin.

## What you need

- **Omarchy** with Hyprland 0.55 or newer.
- **A Wi-Fi adapter that supports Wi-Fi Direct.** Nearly all do. To check:

  ```bash
  iw list | grep -A 3 "valid interface combinations"
  ```

  You want a line offering `managed` alongside `P2P-client` or `P2P-GO`.
- **A Miracast TV.** Most smart TVs since ~2015 qualify; look for "Screen
  Mirroring", "Screen Share" or "Miracast" in the source menu.

## Install

### 1. Install the casting backend

```bash
yay -S waycast-bin
```

[waycast](https://github.com/alchemy/waycast) does the actual casting. The
plugin finds it, drives it, and shows you what it is doing.

Check your system is ready:

```bash
waycast doctor
```

### 2. Let the TV talk to your machine

**This step is not optional, and skipping it fails silently** — the TV simply
never connects, with nothing in any log to say why. Miracast has the *TV* open
a connection back to your laptop, so the firewall has to allow it.

Add these two rules to the `input` chain of `/etc/nftables.conf`:

```
tcp dport 7236 accept comment "Miracast/WFD control connection"
iifname "p2p-*" udp dport 67 accept comment "DHCP for the TV when we host the link"
```

then `sudo systemctl restart nftables`.

If you use **ufw** as well, it needs the same:

```bash
sudo ufw allow 7236/tcp
sudo ufw allow 67/udp
```

Both firewalls apply at once, so a rule in one does not cover the other.
Worth checking even if you think ufw is off: `systemctl is-active ufw`
reporting `inactive` does **not** mean its rules are unloaded.

Finally, relax reverse-path filtering, which otherwise discards the TV's
packets before any firewall rule sees them:

```bash
printf 'net.ipv4.conf.all.rp_filter=2\nnet.ipv4.conf.default.rp_filter=2\n' \
    | sudo tee /etc/sysctl.d/99-miracast-rpf.conf
sudo sysctl --system
```

### 3. Install the plugin

```bash
git clone https://github.com/alchemy/omarchy-wireless-display.git \
    ~/.config/omarchy/plugins/omarchy-wireless-display
omarchy plugin enable omarchy-wireless-display
omarchy restart shell
```

A 󰐹 icon appears in the bar.

## Using it

**On the TV first:** open its screen-sharing mode and leave that screen up.
It is usually under the source or input menu — *Screen Share* on LG,
*Screen Mirroring* on Samsung. Most TVs only accept connections while it is
open.

**Then click the 󰐹 icon.** The panel searches automatically and lists what it
finds.

- Choose **Mirror** or **Extend** with the switch at the top of the list. It
  applies to whichever display you connect next.
- Click **Pair** on a display to connect. The TV usually asks you to approve
  the first connection from a new machine.
- The connected display moves to the top of the list on a lighter background,
  with a **Disconnect** button.
- Pairing with a second display disconnects the first — one at a time.
- **󰑓** searches again. If something is connected it asks first, because
  searching ends the session.

The bar icon doubles as a status light: 󰕐 searching, 󰦟 connecting,
󰍹 connected, 󰀦 something went wrong.

Extending gives you a 1920×1080 monitor placed beside your existing one, which
Hyprland treats like any other display — drag windows to it, and your mouse and
keyboard work across both.

## If it doesn't work

**Nothing is found.** Check the TV's sharing screen is still open — many TVs
close it after a minute. Then check the firewall rules above actually applied:

```bash
sudo nft list ruleset | grep -E '7236|p2p'
```

**It finds the TV, connects, then fails after a few seconds.** Almost always
the firewall. The tell is that the TV's attempts get no reply at all:

```bash
nstat -az | grep IPReversePathFilter   # climbing? rp_filter is dropping packets
```

**The TV shows a spinner but no picture.** Give it a few seconds — the first
frame can take a moment. If it persists, your TV may want a narrower video
format than the 1080p this sends.

**It worked once, now every attempt times out.** Give the TV 30–60 seconds.
TVs generally need to fully reset a session before accepting a new one, and
rapid reconnects fail reliably until they do.

**The picture arrives but only fills part of the screen.** Some TVs display a
1080p signal at its native size rather than scaling it up. Look for a
zoom, aspect or *Screen Fit* option in the TV's own picture menu.

**The panel says no displays even with the TV ready.** The shell may not be
able to find `waycast`. Its `PATH` is the graphical session's, not your
terminal's:

```bash
tr '\0' '\n' < /proc/$(pgrep -f 'quickshell.*omarchy' | head -1)/environ | grep ^PATH
```

Installing `waycast-bin` from the AUR puts it in `/usr/bin`, which is always
on that `PATH`. A copy built by hand in `~/.cargo/bin` is not.

**Still stuck?** The session log says where it stopped:

```bash
cat "$XDG_RUNTIME_DIR/omarchy-wireless-display/daemon.jsonl"
cat "$XDG_RUNTIME_DIR/omarchy-wireless-display/daemon.err"
```

---

## Technical notes

Everything below is background. You do not need it to use the plugin.

### How it fits together

The panel is a thin front end. It polls one shell script —
`bin/omarchy-wireless-display-ctl` — which drives `waycast` and folds its
JSON event stream into a state file the panel reads. The panel never talks to
`waycast` directly, so the backend can change without touching the UI.

Extend mode creates a headless Hyprland output via `hyprctl`, points the
desktop portal at it for one capture request, and streams that output. Mirror
mode has no output to create, so the portal asks which screen to share.

### Driving it from the terminal

```bash
omarchy-wireless-display-ctl scan-start
omarchy-wireless-display-ctl state | jq .
omarchy-wireless-display-ctl extend <display-id>
omarchy-wireless-display-ctl mirror <display-id>
omarchy-wireless-display-ctl rescan        # ends any session, then searches
omarchy-wireless-display-ctl disconnect
```

`state` prints the same JSON the panel reads, which is the quickest way to see
exactly where a connection stalled.

### Configuration

| Variable | Default | Purpose |
|---|---|---|
| `OMARCHY_WIRELESS_DISPLAY_WAYCAST_BIN` | `waycast` | Path to the waycast binary |
| `OMARCHY_WIRELESS_DISPLAY_INTERFACE` | autodetected | Wi-Fi interface for discovery |
| `OMARCHY_WIRELESS_DISPLAY_DISCOVER_TIMEOUT` | `8` | Search duration, seconds |
| `OMARCHY_WIRELESS_DISPLAY_DISCONNECT_GRACE_SECONDS` | `10` | Teardown grace before force-kill |

### Why the firewall rules are what they are

Miracast forms a direct Wi-Fi link between your machine and the TV, separate
from your home network. Which end *hosts* that link is negotiated, and neither
side chooses:

- When the **TV hosts**, it assigns your machine an address and opens a control
  connection to it on TCP **7236**.
- When **your machine hosts**, it becomes the DHCP server for the TV, which
  needs inbound UDP **67** on the `p2p-*` interface.

An LG TV took the host role every time in testing; a Samsung took it about one
time in four. Since the outcome is effectively random, both rules are needed
for reliable pairing.

Reverse-path filtering is separate: in strict mode the kernel discards packets
arriving on the Wi-Fi Direct interface before any firewall rule is consulted,
because the route back does not match. Loose mode (`2`) allows them.

### Limitations

- **1920×1080, not 4K.** Classic Miracast has no 4K in its negotiable formats,
  so 4K TVs still cap at 1080p here.
- **One display at a time.** The panel is built to list several, but the
  backend holds the Wi-Fi radio and the portal for a single session.
- **Miracast only.** The panel is protocol-neutral by design, with AirPlay in
  mind, but no AirPlay backend exists.
- **No signal strength** — discovery does not report it.
- **Mouse only** in the panel; no keyboard navigation yet.
- **Reconnects need a cooldown**, per the troubleshooting note above.
- **A forced kill leaks state.** `SIGKILL` skips cleanup, leaving a stray
  headless output; the next run detects and clears it. A normal quit, `SIGINT`
  or `SIGTERM` all clean up properly.

## License

MIT — see [LICENSE](LICENSE).
