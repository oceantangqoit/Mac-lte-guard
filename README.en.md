# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>Your USB network adapter dies after your Mac sleeps? It heals itself on wake — no more unplugging.</b><br>
  <sub>A USB network adapter watchdog that lives in your menu bar · Native Swift · Zero dependencies · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <b>English</b>
</p>

---

## The problem

Many USB LTE modems and USB Ethernet adapters go "zombie" after a Mac sleeps with the lid closed: the LED is still on, the interface still shows up in the system — but there is no traffic. **The only fix is unplugging and replugging it.**

Why: macOS does not cut USB power during sleep (VBUS is managed by SMC firmware, with no public API to control it), yet the device-side USB session is already dead. Restarting the network service does nothing, because what needs resetting is the USB layer.

## Who runs into this

Anyone whose Mac gets online through a **USB network adapter**:

- 🚁 **Drone video links converted to LTE** — e.g. the popular DJI first-gen transmitter → cellular backhaul mod, with a 4G/5G stick plugged into the Mac for long unattended sessions
- 📡 **USB LTE / 4G / 5G modems, mobile hotspots, cellular USB modules** — fieldwork, vehicles, boats, trade shows, temporary offices
- 🔌 **USB-C / Thunderbolt to Ethernet adapters** — Macs have no Ethernet port; you plug into meeting rooms, racks, client sites
- 🧩 **Adapters built into docks** — Belkin, Plugable, Anker, CalDigit, UGREEN and friends
- 🎥 **Live streaming / RTMP / remote administration** that depends on a stable uplink
- 🖥 **Routers, Raspberry Pis and industrial gear** connected to a Mac over a USB NIC for debugging

Same symptom every time: close the lid once, come back, no network — the LED is still on and **only a physical replug fixes it**.

## The fix

LTE Guard is a watchdog that sits in your menu bar and listens for system wake events. On wake it checks the target adapter: if the gateway does not respond, it performs a **software replug** on that USB device via IOKit (`USBDeviceReEnumerate`) — equivalent to physically unplugging and reinserting it. **Recovery typically takes about 8 seconds.**

- 🎯 **Vendor-agnostic** — VID/PID are detected when you pick the adapter; there is no built-in device list
- 🔌 **Works with non-USB adapters too** — falls back to restarting the network service
- 🛠 **Post-recovery hook** — run your own command after recovery (reconnect a proxy, redial, …)
- 🌍 **28 languages** — follows your system language, switchable from the menu
- 🪶 **Zero dependencies** — a single app; no daemons to install, no Homebrew required

## Install

**Option 1 — download a package** (see [Releases](../../releases))

- `LTEGuard-x.y.z.dmg` — drag into Applications
- `LTEGuard-x.y.z.pkg` — double-click; sets up launch-at-login automatically

On first launch macOS may say the developer cannot be verified (normal for unsigned apps): **right-click the app → Open → Open**, or run

```bash
xattr -dr com.apple.quarantine /Applications/LTEGuard.app
```

**Option 2 — build it yourself** (requires Xcode Command Line Tools)

```bash
git clone https://github.com/oceantangqoit/Mac-lte-guard.git
cd Mac-lte-guard && ./build.sh
```

Artifacts land in `dist/`. Icon rendering needs `brew install librsvg`; without it the build still succeeds (default icon).

## First run

The first launch walks you through: **what it does → pick the adapter to guard → offer to launch at login**.

If anything looks off, use **Run diagnostics** in the menu — it checks each item and tells you the fix:

| Check | What a problem means |
|---|---|
| Location | If it shows `/Volumes/…` you are running it straight from the DMG — drag the app into Applications first |
| Quarantine (Gatekeeper) | Normal for unsigned apps. If it won't open: **right-click → Open → Open**, or `xattr -dr com.apple.quarantine /Applications/LTEGuard.app` |
| Repair tool | Whether `usbreset` is available; it ships inside the app, nothing to install separately |
| Target | Whether an adapter is selected and its interface actually exists (warns if you swapped adapters) |
| Launch at login | When off, it won't start after a reboot — toggle it from the menu |

**Permissions**: none. No Accessibility, no Full Disk Access, no root, no background daemon to install.

## Usage

1. A signal icon appears in the menu bar
2. Open the menu → **Choose target…** → select your adapter (entries marked `· USB` support software replug)
3. Done. Close the lid, open it later — if the link dropped, it is already fixed

Other menu items:

| Item | What it does |
|---|---|
| Check and repair now | Trigger a check manually |
| Open log | Opens `~/.lte-wake.log` |
| Launch at login | Toggle any time (works for DMG installs too) |
| Run diagnostics | Self-check with concrete fixes |
| Command after recovery… | Optional hook: run a shell command once the adapter is back (empty = do nothing) |
| Menu bar icon | Always show / only when there is a problem / hidden (**to bring it back, just open the app again from Applications**) |
| Language | Switch among 28 languages |

## Localization

**28 languages** ship with the app, covering the markets with the highest Mac share as well as regions that rely heavily on mobile broadband:

Simplified/Traditional Chinese · Japanese · Korean · Swedish · Norwegian Bokmål · Danish · Finnish · English · German · French · Dutch · Italian · Polish · Czech · Russian · Ukrainian · Spanish (incl. Mexico/Argentina) · Portuguese (incl. Brazil) · Arabic · Hebrew · Turkish · Vietnamese · Indonesian · Thai

> On Switzerland: there is no "Swiss" language — the official languages are German (~62%), French (23%) and Italian (8%), all three of which are already included.

The app follows your system language at startup; you can also switch it from the **Language** menu (the choice is remembered).

**Language file format** — one INI per language in `lang/`, keyed by numbers:

```ini
[meta]
name=English

[strings]
1=LTE Guard
2=Guarding: {0}  {1}
3=● Online
```

`{0}`, `{1}` are placeholders filled in by the app. **To add a language**, copy any `.ini`, rename it to the target language code (e.g. `nl.ini`) and translate the right-hand side. Dropping it into `~/.lte-guard-lang/` takes effect without rebuilding, and overrides a bundled file of the same name. Translation PRs are very welcome.

## Configuration

`~/.lte-guard.conf` (maintained by the app, editable by hand):

```sh
DEV="en2"              # network interface
SERVICE="My LTE"       # network service name (used for the restart-service fallback)
USB_VID="2c7c"         # USB vendor ID; leave empty to force the restart-service method
USB_PID="0125"         # USB product ID
POST_CMD=''            # command to run after recovery, e.g. restart a proxy
```

`POST_CMD` example — restart a gost proxy bound to that interface:

```sh
POST_CMD='launchctl kickstart -k gui/$(id -u)/com.user.gost-lte'
```

## How it works

```
System wake (IORegisterForSystemPower)
      ↓  wait 5s for the interface to settle
ping the gateway, confirmed twice   → reachable → done
      ↓ unreachable
USBDeviceReEnumerate                → non-USB: networksetup service restart
      ↓  poll until an IP is assigned (up to 60s)
run POST_CMD → write log → refresh the menu bar icon
```

A 90-second cooldown prevents flapping.

## Why there is no "keep online during sleep"

An early version shipped that toggle. It was removed after testing showed it simply does not work:

- **`caffeinate -i -s` cannot block clamshell sleep.** `man caffeinate` states that `-s` *"is valid only when system is running on AC power"*, and what it blocks is **idle sleep** — **closing the lid is a separate trigger path** that it never intercepts. In real logs, caffeinate was running the whole time and the system still logged `Entering Sleep state due to 'Clamshell Sleep'`.
- **The only thing that does block it is `sudo pmset -a disablesleep 1`** (what Amphetamine and InsomniaX do), which requires root — and a laptop that stays awake with the lid shut, inside a bag, **is a genuine overheating risk**.
- The trade-off: this tool does one thing well — heal in ~8 seconds after wake — rather than widen its attack surface for a niche case that needs privilege escalation.

**If you genuinely need the link to stay up with the lid closed** (long downloads, unattended streaming, keeping a remote session alive), pair it with [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) (free, on the App Store): let that keep the machine awake, and let this one repair the adapter if it still drops.

## Compatibility and testing

### Verified working

| Item | Environment |
|---|---|
| Machine | MacBook (Apple Silicon, arm64) |
| OS | macOS 26 (Darwin 25.x) |
| Adapter | Quectel EC25 (VID `2c7c` / PID `0125`), exposed as an ECM/NCM interface `enX` |
| Scenario | Lid closed → on wake the interface exists but the gateway is unreachable → software replug recovers it in **~8 seconds**, reproducible across many cycles |
| Extra | Restarts a proxy bound to that interface afterwards via `POST_CMD` |

### Should work by design — field reports wanted

| Case | What to expect, and what may need adjusting |
|---|---|
| **Intel Macs** | `USBDeviceReEnumerate` may require root on some Intel models; the log will show `open failed … try sudo`. Workaround: run once with `sudo`, or switch to the restart-service method by clearing `USB_VID` in the config |
| **macOS 13 / 14 / 15** | All APIs used (IOKit power notifications, `USBDeviceReEnumerate`, `NSStatusItem.isVisible`) are stable since 13, so it should be fine. Below 13 it will not launch (enforced in Info.plist) |
| **USB-Ethernet adapters** (AX88179, RTL8153, CM3xx …) | Same mechanism, should work. Note some adapters come back with a different interface name (`en5`→`en6`) — just pick the target again from the menu |
| **Dial-up style 4G modems** (PPP/AT rather than ECM/NCM) | They need to redial after re-enumeration, otherwise the 60-second wait fails. Put your redial command in *Command after recovery* |
| **Adapters inside a dock** | If the dock itself is the USB device, re-enumerating resets everything on it (external drives, cameras). With a drive actively writing, prefer the restart-service method |
| **Composite devices** (NIC + card reader + serial in one) | Same caveat — the reset affects the other functions of that USB device |
| **iPhone USB tethering** | Apple's own NCM device; macOS usually recovers it by itself, but the same mechanism applies if it does not |
| **Wi-Fi, Thunderbolt Ethernet and other non-USB interfaces** | Automatically falls back to restarting the network service — fixes software-level hangs, not driver-level ones |

If your hardware is not in the table, **please open an issue with the result** (model, `USB VID:PID`, a snippet of `~/.lte-wake.log`) — success or failure. That is the most useful contribution right now.

## Known limitations

- **Actually cutting USB power is not possible** — VBUS on Apple Silicon is controlled by SMC firmware with no public API. For real power cycling, use an external hub with per-port power switching (PPPS) plus [uhubctl](https://github.com/mvp/uhubctl).
- **Intel Macs** may require root for `USBDeviceReEnumerate`; the log will say `try sudo`.
- **Dial-up style modems** (not ECM/NCM) may need to redial after re-enumeration — use `POST_CMD`.
- The app is not notarized, so the first launch needs right-click → Open.

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.oceantang.lteguard
rm -f ~/Library/LaunchAgents/com.oceantang.lteguard.plist ~/.lte-guard.conf ~/.lte-wake.log
rm -rf /Applications/LTEGuard.app
```

## Support the project

If this saved you from replugging USB over and over:

- ⭐ Star the repo, or pass it on to someone with the same problem
- 🐛 Open an issue with your adapter model and log so more devices get covered
- 🌍 Contribute a translation ([CONTRIBUTING.md](CONTRIBUTING.md) — it's a few lines of INI)
- ☕ Buy me a coffee

## Community & contact

- 💬 Questions and ideas: [Discussions](../../discussions)
- 🐛 Bugs and feature requests: [Issues](../../issues)

### About the author

**Ocean Tang (唐海洋)** is a practising lawyer at Beijing DOCVIT (Shenzhen) Law Firm, admitted in 2012 and a partner there from 2016 to 2021.

- **Practice areas**: commercial litigation and arbitration, criminal defence and victim representation, employment disputes (including class matters with 100+ claimants), corporate counsel work, due diligence
- **Track record**: 400+ contentious and non-contentious matters; clients have included China Merchants Property, ZTE, Semcorp, CITIC and others
- **Before law**: five years as in-house counsel and operations staff at a Taiwanese electronics manufacturer — hence a practical feel for supply chains and factory-floor employment
- **Why a lawyer writes apps**: CCNA in 2002, CIW Security Analyst in 2003, and years of writing VBA case-management tooling for his own practice. This app started when he converted a first-gen DJI video link to LTE backhaul, plugged a 4G stick into his Mac — and got tired of unplugging it after every lid close.

Happy to talk law or code — [Discussions](../../discussions) or an issue both work.

## License

MIT License
