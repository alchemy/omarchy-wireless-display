# Wireless Display

Cast your Omarchy desktop to a TV over Wi-Fi — no cable, no dongle.

Adds a bar widget that finds wireless displays and connects to them two ways:

- **Extend** — the TV becomes a second monitor you can drag windows onto.
- **Mirror** — the TV shows a copy of your existing screen.

Two protocols are supported:

|                 | Miracast                         | AirPlay                     |
| --------------- | -------------------------------- | --------------------------- |
| Typical device  | smart TV with _Screen Share_     | Apple TV, some smart TVs    |
| How it connects | Wi-Fi Direct, straight to the TV | your existing network       |
| At once         | one                              | as many as you like         |
| Extend          | yes                              | no — AirPlay always mirrors |

A single Miracast display and any number of AirPlay ones can run together.

> **Status: early.** Confirmed working against real hardware — an LG webOS TV,
> a Samsung Tizen TV and an Apple TV — with picture, sound, and working mouse
> and keyboard. Expect rough edges, and read _If it doesn't work_ before filing
> a bug — TVs vary more than you would hope, and the ones that fail tend to
> fail in ways that look like a bug here.

## What you need

- **Omarchy** with Hyprland 0.55 or newer, with its stock firewall (ufw) in
  place. That is what the automatic networking setup is built against.
- **A Wi-Fi adapter (with Wi-Fi Direct support for Miracast).** Nearly all do. To check:

  ```bash
  iw list | grep -A 3 "valid interface combinations"
  ```

  You want a line offering `managed` alongside `P2P-client` or `P2P-GO`.

- **A Miracast TV.** Most smart TVs since ~2015 qualify; look for "Screen
  Mirroring", "Screen Share" or "Miracast" in the source menu. Only needed for
  Miracast — AirPlay receivers want none of the above.
- **An AirPlay receiver**, if you want that half: an Apple TV, or a TV that
  advertises AirPlay. It has to be on the same network as this machine.

## Install

### 1. Install the casting backends

```bash
yay -S waycast-bin      # Miracast
yay -S doubletake-bin   # AirPlay
```

[waycast](https://github.com/alchemy/waycast) speaks Miracast and
[doubletake](https://github.com/omarroth/doubletake) speaks AirPlay. The plugin
finds them, drives them, and shows you what they are doing. Install only the
one you need — the panel simply lists nothing for a protocol whose backend is
missing.

Check your system is ready for Miracast:

```bash
waycast doctor
```

### 2. Networking — already handled

Installing `waycast-bin` sets up its networking helper for you. Miracast needs
the _TV_ to open a connection back to your laptop, and on a stock Omarchy
firewall that is blocked; the helper opens exactly what a session needs, for
as long as that session lasts, and closes it again afterwards.

You are not asked for a password when you cast: authorisation is granted once
at install time, and casting is then available to whoever is logged in at the
machine.

Two things to know:

- **A `ufw reload` ends any active session.** Reloading rebuilds the chain the
  helper is using. Reconnect from the panel afterwards.
- **A custom firewall needs its own rule.** The helper hooks into ufw. If you
  also run your own `/etc/nftables.conf` with a drop policy, an allow in ufw
  does not override a drop there — add `tcp dport 7236 accept` to your input
  chain. Stock Omarchy has no such ruleset and needs nothing.

If casting fails and you suspect the helper, check it is running:

```bash
systemctl status waycast-networkd
```

AirPlay needs none of this. It runs over the network you are already on, and
its video and control channels are outbound connections, so a stock firewall
does not block them.

### 3. Install the plugin

```bash
omarchy plugin add https://github.com/alchemy/omarchy-wireless-display.git --enable
```

It asks where to place the widget in the bar, then a 󰐹 icon appears there.

The command clones the plugin, registers it with the shell and enables it, so
no restart is needed. If the icon does not show up, `omarchy restart shell`.

To update it later, `omarchy plugin update omarchy-wireless-display`.

## Using it

**On the TV first:** open its screen-sharing mode and leave that screen up.
It is usually under the source or input menu — _Screen Share_ on LG,
_Screen Mirroring_ on Samsung. Most TVs only accept connections while it is
open.

**Then click the 󰐹 icon.** The panel searches automatically and lists what it
finds.

- Each display carries its own **EXTEND** switch. Off — the default — the TV
  mirrors the screen you already have; on, it becomes a second monitor. Set it
  before connecting: once a display is live the switch shows what it
  negotiated and stops accepting clicks, because changing it means
  reconnecting. **AirPlay ignores it** and always mirrors; the switch is there
  so every row looks the same, not because it does anything on those.
- Click **󰌷** on a display to connect. The TV usually asks you to approve the
  first connection from a new machine.
- **If an AirPlay receiver wants a PIN**, the row opens a field for it — the
  same prompt the Wi-Fi panel uses for a passphrase. Type the code shown on the
  receiver and press Enter, or **󰄬**. Escape gives up and ends the attempt.
  You are asked once; the credentials are saved and reused afterwards.
- Connected displays move to the top of the list on a lighter background, each
  with a **󰅙** button to disconnect it.
- Connecting a second **Miracast** display disconnects the first — Wi-Fi Direct
  allows one at a time. **AirPlay** receivers have no such limit: connect as
  many as you like, and a Miracast display alongside them.
- One connection is set up at a time. While a display is connecting the other
  rows' buttons are inactive; they come back when it settles.
- **󰑓** searches again. If something is connected it asks first, because
  searching ends the session.

The bar icon doubles as a status light: 󰕐 searching, 󰦟 connecting,
󰍹 connected, 󰀦 something went wrong.

Extending gives you a 1920×1080 monitor placed beside your existing one, which
Hyprland treats like any other display — drag windows to it, and your mouse and
keyboard work across both.

## If it doesn't work

**Nothing is found.** Check the TV's sharing screen is still open — many TVs
close it after a minute. Discovery is radio work, not network work, so a
firewall cannot be the cause of an empty list.

**It finds the TV, connects, then fails after a few seconds.** The TV's
connection is being dropped somewhere. Check the helper is running and has a
session, then look for a second firewall that the helper does not manage:

```bash
systemctl status waycast-networkd
sudo nft list ruleset | grep -E '7236|waycast'
```

If reverse-path filtering is discarding the TV's packets the counter climbs
while you try:

```bash
nstat -az | grep IPReversePathFilter
```

That is worth checking before changing, since the kernel takes the _higher_ of
the global and per-interface settings and the relevant interface is the `p2p-*`
one that only exists during a session.

**The TV shows a spinner but no picture.** Give it a few seconds — the first
frame can take a moment. If it persists, your TV may want a narrower video
format than the 1080p this sends.

**It worked once, now every attempt times out.** Give the TV 30–60 seconds.
TVs generally need to fully reset a session before accepting a new one, and
rapid reconnects fail reliably until they do.

**The picture arrives but only fills part of the screen.** Some TVs display a
1080p signal at its native size rather than scaling it up. Look for a
zoom, aspect or _Screen Fit_ option in the TV's own picture menu.

**No AirPlay devices are listed.** The receiver has to be on the same network
and reachable by mDNS — a guest network or client isolation on the access point
will hide it. Check from a terminal:

```bash
doubletake -daemonize
doubletake-ctl discover
```

**An AirPlay device says "Wrong PIN or password".** The receiver rejected the
code. Connect again and it will ask afresh — the digits change each time.

Note that a _PIN_ and a _password_ are different things, and the prompt says
which one it wants. A PIN appears on the receiver's own screen when you
connect. A password is one you set on the device beforehand (Apple TV:
Settings → AirPlay and HomeKit → Require Password) and nothing is shown on
screen at all — if you are waiting for a code to appear there, it never will.

Either way you are asked once. The credentials are saved and reused, so later
connections go straight through.

**The panel says no displays even with the TV ready.** The shell may not be
able to find `waycast` or `doubletake`. Its `PATH` is the graphical session's,
not your terminal's:

```bash
tr '\0' '\n' < /proc/$(pgrep -f 'quickshell.*omarchy' | head -1)/environ | grep ^PATH
```

Installing the `-bin` packages from the AUR puts both in `/usr/bin`, which is
always on that `PATH`. A copy built by hand in `~/.cargo/bin` or a checkout's
`bin/` is not.

**Still stuck?** The session log says where it stopped:

```bash
cat "$XDG_RUNTIME_DIR/omarchy-wireless-display/daemon.jsonl"        # Miracast
cat "$XDG_RUNTIME_DIR/omarchy-wireless-display/daemon.err"          # Miracast
cat "$XDG_RUNTIME_DIR/omarchy-wireless-display/airplay-daemon.log"  # AirPlay
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

| Variable                                            | Default          | Purpose                                |
| --------------------------------------------------- | ---------------- | -------------------------------------- |
| `OMARCHY_WIRELESS_DISPLAY_WAYCAST_BIN`              | `waycast`        | Path to the waycast binary             |
| `OMARCHY_WIRELESS_DISPLAY_DOUBLETAKE_BIN`           | `doubletake`     | Path to the doubletake binary          |
| `OMARCHY_WIRELESS_DISPLAY_DOUBLETAKE_CTL_BIN`       | `doubletake-ctl` | Path to its control client             |
| `OMARCHY_WIRELESS_DISPLAY_INTERFACE`                | autodetected     | Wi-Fi interface for Miracast discovery |
| `OMARCHY_WIRELESS_DISPLAY_DISCOVER_TIMEOUT`         | `8`              | Search duration, seconds               |
| `OMARCHY_WIRELESS_DISPLAY_DISCONNECT_GRACE_SECONDS` | `10`             | Teardown grace before force-kill       |

### How the two backends are driven

They are shaped differently, and the control script follows each rather than
forcing a shared abstraction on them.

**waycast** is one blocking process per session that streams JSONL events. The
script launches it, tails the log, and folds each event into the state file.
One session at a time: it holds the Wi-Fi Direct interface, and in extend mode
an edit to `~/.config/hypr/xdph.conf`.

**doubletake** is a daemon that owns every stream itself and answers `status`
with the full list. There is nothing to tail and no pid to track — the script
asks the daemon what it has and makes its own state agree. That reconciliation
covers every case an event feed would need separate handling for, including a
stream started by some other doubletake client, which the panel adopts and can
end. The daemon is started when the panel first wants AirPlay and stopped again
once nothing is using it, so an unopened panel leaves no mDNS chatter on the
network. A daemon you started yourself is left alone.

Display ids are namespaced — `miracast:<mac>`, `airplay:<ip>` — so the panel
hands one back without knowing which backend owns it, and the two lists cannot
collide.

A receiver waiting for a PIN or password stays in `pending` with an `awaiting`
field naming which of the two it asked for, and the panel expands that row into
a prompt. The answer travels on stdin the whole way — from the panel's `Process`
into `omarchy-wireless-display-ctl credential <id>`, and from there straight to
doubletake's control socket, which the script speaks itself rather than going
through `doubletake-ctl`. That client takes the code as a command-line
argument, and an argument is readable by every local user with `ps`.

Only one connection is set up at a time, whichever protocol. Both backends
reach for the screencast portal while they start, and waycast arms a one-shot
picker override for its headless output moments before its own request; a
second connect landing in that window could consume the override and be handed
waycast's output instead of the screen it asked for.

### How the networking gets out of your way

Miracast forms a direct Wi-Fi link between your machine and the TV, separate
from your home network. Which end _hosts_ that link is negotiated, and neither
side chooses:

- When the **TV hosts**, it assigns your machine an address and opens a control
  connection to it on TCP **7236**.
- When **your machine hosts**, it becomes the TV's DHCP server and has to
  answer the TV's requests.

An LG TV took the host role every time in testing; a Samsung about one time in
four. Since the outcome is effectively random, both directions have to work,
and neither is allowed by a stock desktop firewall.

Rather than have you open ports permanently, waycast ships a small root helper,
`waycast-networkd`. The unprivileged part of waycast asks it over D-Bus to
begin a session; the helper resolves the peer itself, watches for the real P2P
interface to appear, and adds allowances scoped to that interface and to the
ports actually negotiated — including the media sockets, which are chosen at
runtime and cannot be known in advance. When the session ends, so do the rules.
Polkit grants this to an active local session, which is why casting needs no
password after installation.

The practical consequence is that firewall configuration is not part of using
this plugin, and a permanently open port is not the price of casting.

### Limitations

- **1920×1080, not 4K over Miracast.** Classic Miracast has no 4K in its
  negotiable formats, so 4K TVs still cap at 1080p there. AirPlay negotiates
  its own canvas with the receiver.
- **One Miracast display at a time.** That backend holds the Wi-Fi Direct
  interface and the portal for a single session. AirPlay has no such limit.
- **No AirPlay extend.** doubletake mirrors; there is no second-monitor mode to
  drive. The row's switch is ignored on those displays.
- **A rejected PIN means starting over.** doubletake does not re-prompt within
  the same attempt, so a mistyped code ends the connection and you connect
  again — with a fresh code, since receivers change theirs each time.
- **No signal strength** — neither backend reports it.
- **Mouse only** in the panel; no keyboard navigation yet.
- **Reconnects need a cooldown**, per the troubleshooting note above.
- **A forced kill leaks state.** `SIGKILL` skips cleanup, leaving a stray
  headless output; the next run detects and clears it. A normal quit, `SIGINT`
  or `SIGTERM` all clean up properly.

## License

MIT — see [LICENSE](LICENSE).
