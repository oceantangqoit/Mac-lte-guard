# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>Your USB network adapter dies after your Mac sleeps? It heals itself on wake — no more unplugging.</b><br>
  <sub>macOS menu bar utility · Native Swift · Zero dependencies · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <b>English</b>
</p>

---

## The problem

Many USB LTE modems and USB Ethernet adapters go "zombie" after a Mac sleeps with the lid closed: the LED is still on, the interface still shows up in the system — but there is no traffic. **The only fix is unplugging and replugging it.**

Why: macOS does not cut USB power during sleep (VBUS is managed by SMC firmware, with no public API to control it), yet the device-side USB session is already dead. Restarting the network service does nothing, because what needs resetting is the USB layer.

## The fix

LTE Guard lives in your menu bar and listens for system wake events. On wake it checks the target adapter: if the gateway does not respond, it performs a **software replug** on that USB device via IOKit (`USBDeviceReEnumerate`) — equivalent to physically unplugging and reinserting it. **Recovery typically takes about 8 seconds.**

- 🎯 **Vendor-agnostic** — VID/PID are detected when you pick the adapter; there is no built-in device list
- 🔌 **Works with non-USB adapters too** — falls back to restarting the network service
- 🌙 **Two sleep policies** — *Keep online* (prevent sleep) or *Normal sleep* (heal on wake)
- 🛠 **Post-recovery hook** — run your own command after recovery (reconnect a proxy, redial, …)
- 🌍 **16 languages** — follows your system language, switchable from the menu
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

## Usage

1. A signal icon appears in the menu bar
2. Open the menu → **Choose target…** → select your adapter (entries marked `· USB` support software replug)
3. Done. Close the lid, open it later — if the link dropped, it is already fixed

Other menu items:

| Item | What it does |
|---|---|
| Keep online during sleep | Uses `caffeinate` to prevent deep sleep (power-hungry; good while running long tasks) |
| Normal sleep (heal on wake) | Default mode |
| Check and repair now | Trigger a check manually |
| Open log | Opens `~/.lte-wake.log` |

**Optional** — to make *Keep online* work with the lid closed as well, grant passwordless `pmset` once:

```bash
echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset" | sudo tee /etc/sudoers.d/pmset-nopasswd
```

## Localization

16 languages ship with the app: Simplified/Traditional Chinese, English, Japanese, Korean, Arabic, Russian, French, German, Italian, Finnish, Spanish (incl. Mexico/Argentina) and Portuguese (incl. Brazil).

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

## License

MIT License
