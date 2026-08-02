# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>Your USB network adapter dies after your Mac sleeps? It heals itself on wake — no more unplugging.</b><br>
  <sub>A USB network adapter watchdog that lives in your menu bar · Native Swift · Zero dependencies · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <b>English</b> · <a href="README.ja.md">日本語</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.rw.md">Ikinyarwanda</a>
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

### Not just network adapters

The same "dead after wake, only a replug fixes it" behaviour shows up across other USB gear too — [Apple's own forums](https://discussions.apple.com/thread/7745583), [MacRumors](https://forums.macrumors.com/threads/mac-mini-m1-usb-ports-not-working-after-wake-from-sleep.2326616/) and the [Plugable knowledge base](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos) are full of reports about audio interfaces, webcams, external drives, card readers and individual components inside docks.

Since the underlying mechanism is identical, the menu includes **Reset a USB device**: it lists every connected USB device and replugs the one you pick in software. Devices other than the guarded adapter are triggered manually — automatic detection only covers networking, where "reachable or not" is a clear test, whereas a webcam or audio interface is hard to probe reliably.

> ⚠️ For storage devices, stop any reads/writes and eject first — otherwise you risk data loss.

## Found this by searching?

Below are phrasings that actually appear in forum posts. If any of them is why you're here, this tool was written for you.

### Real thread titles, quoted verbatim

From Apple Support Communities, MacRumors and vendor knowledge bases — not paraphrased:

> `Ethernet USB-C adapter doesn't wake up after sleep` · `Ethernet adapter doesn't want to wake up after sleep` · `Usb ethernet adapter is not working after sleep` · `Ethernet not waking after sleep` · `Ethernet reset/disconnect on wake-up` · `Ethernet disconnected after sleep` · `MacBook Air 2020 USB LAN issue after sleep` · `USB devices aren't working after waking from sleep` · `USB A ports no power after wake up` · `Mac Mini M1 — USB Ports not working after wake from sleep` · `USB device does not wake up after sleep` · `Hardwired internet via a USB hub is not working after the MBP sleeps` · `Devices are not detected after waking from sleep or after rebooting on macOS` · `Ethernet connection downgraded while asleep` · `Loosing Ethernet connection nearly every day` · `After updating to macOS Tahoe external USB devices disconnect after sleep` · `USB ports NOT working after macOS Tahoe` · `AX 88179a Ethernet Adapter not recognized` · `macOS 26 Third Party Ethernet Support` · `Mouse freezes after macOS Tahoe 26.5`

### Search phrases people type

> `usb ethernet adapter not working after sleep mac` · `macbook ethernet doesn't wake up after sleep` · `usb-c ethernet adapter stops working after lid close` · `mac dock ethernet not detected after wake` · `lte modem disconnects after macbook sleeps` · `have to unplug and replug ethernet adapter macos` · `usb device dead after wake macos` · `thunderbolt dock ethernet not working after sleep` · `external drive not mounting after sleep mac` · `usb hub stops working after sleep macbook` · `macos re-enumerate usb device without unplugging` · `software unplug usb mac` · `reset usb port macos command line` · `macos usb reset without physically unplugging` · `automatically replug usb adapter after wake`

### By device type

| Your device | How people describe it |
|---|---|
| USB / wired network adapter | LED on but no traffic, shows "Not Connected", `en5` still listed but ping fails, only a replug fixes it |
| LTE / 4G / 5G modem, mobile hotspot | Drops after closing the lid, no internet after wake, needs a replug before it will dial again |
| Dock (Belkin, Plugable, Anker, CalDigit, OWC, UGREEN) | Nothing on the dock is recognised after wake, have to unplug the whole dock |
| External drive / SSD | Won't mount after sleep, "Disk Not Ejected Properly", only reappears after replugging |
| Webcam / capture card / audio interface | Gone from the device list after wake, can't be selected in the app |
| Card reader / dongle / keyboard & mouse | Unresponsive after wake, one replug brings it back |

### Chipsets named most often in those threads

> ASIX `AX88179` / `AX88179A` · Realtek `RTL8153` · `RTL8156` 2.5G · Quectel `EC25` · various `CM3xx` series · Intel `I225-V` (behind Thunderbolt docks)

### Ten years on, still unfixed — and worse in the latest release

This is not an old bug that was quietly resolved years ago. Laid out chronologically, the public reports form an unbroken line:

| Period | State of play |
|---|---|
| Intel Mac era | Apple's forums already carried plenty of "USB ethernet adapter dead after sleep" threads; the earliest ones sit in the 7686532 range |
| After the Apple Silicon transition | The problem did not go away with the new architecture — it kept appearing on M1 machines, and docks and external drives started showing the same symptoms |
| macOS 15 Sequoia | Still present; some users reported adapters that "used to work fine and stopped after the upgrade" |
| **October 2025, macOS 26 Tahoe** | [External USB devices disconnect after sleep](https://discussions.apple.com/thread/256157526) — **26 "me too" votes**. The reporter reproduced it with two different Thunderbolt docks and several storage devices, filed a Feedback ticket, and **still has no fix**. Their words: "I have to fully unplug and reconnect the dock before the drives are detected" |
| **November 2025, macOS 26** | [Third-party ethernet adapters no longer work](https://discussions.apple.com/thread/256192666) — ASIX AX88179 chipset, fine on Sequoia, broken after upgrading to Tahoe. The workaround the reporter eventually found: delete the network service and re-insert the adapter so it re-initialises |
| **2026, macOS 26.5.1** | Devices [still freezing after wake](https://discussions.apple.com/thread/256306656). Sites like MacPaw have published dedicated "USB devices disconnecting on macOS Tahoe" guides — people generally only write guides for high-frequency problems |

In other words: **the problem survived the Intel → Apple Silicon transition, survived at least four or five major macOS releases, is still present in the latest 2026 point release, and has taken on new and more severe forms on macOS 26.**

### Why hasn't Apple fixed something this simple in ten years?

Not because it can't be fixed, but because this class of bug lands at the intersection of several unfavourable factors:

1. **It isn't one bug, it's a family of symptoms.** They all look like "dead after wake", but the root causes number at least seven or eight: timing deviations in third-party chipset firmware coming out of low power, drivers failing to re-initialise on wake, edge cases in the xHCI controller state machine, Thunderbolt tunnels failing to rebuild… fix one and the others remain.
2. **Responsibility falls in a grey zone.** Almost every affected device uses a third-party chipset (AX88179, RTL8153 and friends), plenty of which shipped once they "worked on Windows" without strictly conforming to the USB spec. Apple sees a device implementation problem; the vendor sees a system that behaves fine elsewhere. Nobody owns the middle.
3. **What can't be reproduced can't be fixed.** It depends on the exact combination: Mac model + chipset + whether a hub is involved + the cable + how deeply the machine slept + the OS point release — and it is often probabilistic. An engineer who tries the hardware on hand for a day without reproducing it closes the ticket.
4. **Sleep/wake is one of the hardest areas in any OS.** It requires firmware (SMC/EFI), kernel, drivers, userspace and the peripheral's own firmware to **cooperate under power constraints across five layers**; any timeout or state mismatch anywhere breaks it. This is not Apple-specific — Linux USB autosuspend and Windows selective suspend carry nearly identical long-standing bugs.
5. **The architecture keeps moving, so old scars reopen as new wounds.** Intel → Apple Silicon rewrote the whole USB stack; kext → DriverKit migrated the driver model. Every major release can introduce regressions — hence "worked on Sequoia, broke on Tahoe".
6. **Having a workaround lowers the pressure to fix it.** A problem you can clear by unplugging and replugging tends to sit low in triage, permanently behind anything that affects revenue.
7. **A closed ecosystem is a disadvantage here.** There is no public bug tracker, Feedback submissions vanish into silence, and the community can neither collaborate on debugging nor ship its own patch the way it can on Linux.

Here's the interesting part: **the fact that this tool works tells you what kind of problem it is.** The hardware is fine and the system's USB stack has not crashed — one re-enumeration brings it back, which means the **session state machine is simply stuck in an intermediate state**. That class of "state desynchronisation" bug is the hardest to eradicate in a large system, because it isn't a line of wrong code but an edge case in a state machine under particular timing; fixing it means re-auditing the whole chain for a payoff only a minority of users would notice.

So a more accurate framing might be: it isn't that Apple *can't* fix it — it's that **the problem never reaches the top of a cost/benefit queue**. Which is exactly the gap a third-party tool can fill: not by curing it, but by kicking the state machine back on track within eight seconds of it happening.

### More reports of the same kind

Reports span years, both Intel and Apple Silicon, across Apple's own forums, MacRumors and vendor knowledge bases:

- [Ethernet USB-C adapter doesn't wake up after sleep](https://forums.macrumors.com/threads/ethernet-usb-c-adapter-doesnt-wake-up-after-sleep.2220969/) — MacRumors
- [Ethernet adapter doesn't want to wake up after sleep](https://discussions.apple.com/thread/8272273) — Apple Support Communities
- [MacBook Air 2020 USB LAN issue after sleep](https://discussions.apple.com/thread/255925525) — Apple Support Communities
- [Usb ethernet adapter is not working after sleep](https://discussions.apple.com/thread/7686532) · [Ethernet not waking after sleep](https://discussions.apple.com/thread/250166501) · [Ethernet reset/disconnect on wake-up](https://discussions.apple.com/thread/251074085) · [Ethernet disconnected after sleep](https://discussions.apple.com/thread/8425667)
- [Devices are not detected after waking from sleep on macOS](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos) — Plugable knowledge base

### Why the usual advice doesn't fix it

| Commonly suggested | Why it fails here |
|---|---|
| Reset SMC / NVRAM | Apple Silicon Macs **have no SMC reset** at all; on Intel it may help once, but the next lid close brings the problem straight back |
| Turn off "Wake for network access" | That setting governs being woken *by* the network while asleep — a different thing from the USB session being dead *after* waking |
| Full power cycle / update macOS | Effective but absurd — reboot the machine after every lid close? |
| Unplug the cable instead of the adapter | Frequently suggested in threads; the original poster's own reply was "tried that too, doesn't work" |
| **Unplug the USB adapter and plug it back in** | The one thing that reliably works — **and precisely what this tool automates** |

## The fix

LTE Guard is a watchdog that sits in your menu bar and listens for system wake events. On wake it **immediately** performs a **software replug** on the target USB device via IOKit (`USBDeviceReEnumerate`) — equivalent to physically unplugging and reinserting it. No "should we repair?" pre-checks: if you installed this tool, you are a zombie-device victim, and checking just wastes time. Recovery counts only when the **gateway actually answers a ping**, typically in **about 8 seconds** — close to the physical limit of a manual replug.

- 🎯 **Vendor-agnostic** — VID/PID are detected when you pick the adapter; there is no built-in device list
- 🖇 **Guards several adapters at once** — tick as many as you like; each is checked and repaired independently, in parallel
- 🔌 **Works with non-USB adapters too** — falls back to restarting the network service
- 🛠 **Two-phase command hooks** — one set runs **the moment disconnection is detected** (e.g. open the Network pane and watch the repair live), another **after recovery** (reconnect a proxy, redial, …)
- 🔔 **Success-only notifications** — you get exactly one notification, when the adapter is back *and* the internet is verified to actually work (with the time it took); repair-in-progress, offline and failure states show on the menu bar icon instead (spinner / `✓8s` / `⚠︎` / `✕`)
- 🌍 **62 languages** — UI and logs fully localized, follows your system language, switchable from the menu
- 🪶 **Zero dependencies** — a single app; no daemons, no Homebrew, no elevated privileges

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
2. Open the menu → **Choose target…** → tick your adapter — **multiple selections allowed** (entries marked `· USB` support software replug)
3. Done. Close the lid, open it later — if the link dropped, it is already fixed

Other menu items:

| Item | What it does |
|---|---|
| Check and repair now | Trigger a check manually |
| Open log | Opens `~/Library/Application Support/LTE Guard/lte-guard.log` |
| Launch at login | Toggle any time (works for DMG installs too) |
| Run diagnostics | Self-check with concrete fixes |
| Command after recovery… | Two-phase hooks: "on disconnection" (e.g. open the Network pane to watch the repair) and "after recovery" (e.g. reconnect a proxy) — one command per line, run in order, plus common ones you can just tick |
| Reset a USB device | Lists all USB devices and software-replugs the one you choose — works for audio interfaces, webcams, drives and docks too |
| Menu bar icon | Always show / only when there is a problem / hidden (**to bring it back, just open the app again from Applications**) |
| Open config folder | Reveals the config file, log and language folder in Finder |
| Language | Switch among 62 languages; the submenu can edit the current language or open the language folder |

## Right-to-left languages (RTL)

Four bundled languages are written right to left: **العربية** (Arabic), **עברית** (Hebrew), **فارسی** (Persian) and **اردو** (Urdu).

Because language switching is implemented in-app (reading `lang/*.ini`) rather than through macOS `.lproj` localization, the system never mirrors the interface on its own. Two things are therefore handled explicitly:

1. **Mirrored layout** — menus and submenus are set to `.rightToLeft` for RTL languages: text right-aligned, icons on the right, submenu arrows flipped.
2. **Bidi isolation** — values interpolated into strings (interface names like `en2`, `2c7c:0125`, service names) are Latin script and digits. Dropped straight into an Arabic sentence, the Unicode bidirectional algorithm reorders them and **colons and parentheses end up on the wrong side**. Every placeholder substitution is therefore wrapped in `U+2068 FSI` / `U+2069 PDI` (the W3C i18n recommendation) so each value becomes its own directional unit.
3. The *command after recovery* field is forced left-to-right — shell commands are Latin text and read badly right-aligned.

## Localization

**62 languages** ship with the app. The menu lists Chinese and its varieties first, then other languages by code.

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

`~/Library/Application Support/LTE Guard/lte-guard.conf` (maintained by the app, editable by hand; old single-target configs upgrade automatically):

```sh
# one heal target per line, tab-separated: interface, service name, USB_VID, USB_PID
TARGETS='en2	My LTE	2c7c	0125'
PRE_CMD=''             # runs the moment disconnection is detected (network is down — don't rely on it)
POST_CMD=''            # runs after recovery, e.g. restart a proxy
```

**Both hooks take multiple commands** — one per line, run in order. `PRE_CMD` fires **instantly** on detection: open the Network pane there and it comes up just in time to watch the whole repair.

The dialog offers checkboxes in two groups — ticking writes into the matching text box immediately, unticking removes it:

**Common** (always offered)

- Open System Settings → Network (goes to the on-disconnection box) — watch the dropped connection come back with your own eyes
- Play a sound
- Send a webhook notification (replace the placeholder URL with your own; good for unattended machines)

The recovery notification and internet check are **built in** — nothing to tick: after repair the app probes the internet through that very adapter, and notifies only when it genuinely works (with the seconds it took). Interface-up-but-offline shows `⚠︎`, failure shows `✕` — icon only, no nagging.

For example, opening the Network pane on disconnection, then restarting a proxy and playing a sound after recovery:

```sh
PRE_CMD='open "x-apple.systempreferences:com.apple.Network-Settings.extension"'
POST_CMD='launchctl kickstart -k gui/$(id -u)/com.user.gost-lte\nafplay /System/Library/Sounds/Glass.aiff'
```

In the config file, newlines are written as `\n` and single quotes as `\'` (the app escapes them automatically; follow the same form if editing by hand).

## How it works

```
System wake (IORegisterForSystemPower + NSWorkspace, belt and braces)
      ↓  run PRE_CMD immediately (e.g. open the Network pane); wait 1s for USB to power up
USBDeviceReEnumerate                → non-USB: networksetup service restart
      ↓  no pre-checks — if you installed this, you're a zombie-device victim
poll every second: recovered only when the gateway answers a ping (a zombie IP can't fake that)
      ↓  recovered
run POST_CMD → probe the internet through that adapter → notify only if it truly works (with timing)
      ↓
the icon tells the whole story: spinner = repairing, ✓8s = done, ⚠︎ = offline, ✕ = failed
```

Multiple adapters are repaired independently, in parallel. A 15-second cooldown absorbs the duplicate wake signals from the two listeners.

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

If your hardware is not in the table, **please open an issue with the result** (model, `USB VID:PID`, a snippet of `~/Library/Application Support/LTE Guard/lte-guard.log`) — success or failure. That is the most useful contribution right now.

## What this tool cannot fix

Apple has still not fixed the underlying problem — an [October 2025 Tahoe report](https://discussions.apple.com/thread/256157526) collected 26 "me too" votes and a feedback ticket with no resolution, and people were [still reporting it on 26.5.1 in 2026](https://discussions.apple.com/thread/256306656). But precisely because there is more than one root cause, this tool only covers one class of them, and the boundary is worth stating plainly:

| Situation | Can this tool help? |
|---|---|
| Device still present in the system, USB session dead (the most common case, and the author's own adapter) | ✅ Yes — re-enumeration usually restores it in about 8 seconds |
| The whole USB port stops working (reported on Tahoe) | ❌ No. The port itself is gone; software cannot reach it, only a reboot will |
| Driver-level crash or incompatibility (e.g. how some AX88179 adapters behave on macOS 26) | ⚠️ Maybe. Re-enumeration can trigger a driver reload, or may do nothing |
| An entire dock drops off | ⚠️ It can reset the dock, but that resets everything else attached to it — not advisable while a drive is being written to |

A simple rule of thumb: **if unplugging and replugging by hand brings it back, this tool can do that for you automatically; if even a replug does not help and only a reboot does, this tool will not help either.**

## Known limitations

- **Actually cutting USB power is not possible** — VBUS on Apple Silicon is controlled by SMC firmware with no public API. For real power cycling, use an external hub with per-port power switching (PPPS) plus [uhubctl](https://github.com/mvp/uhubctl).
- **Intel Macs** may require root for `USBDeviceReEnumerate`; the log will say `try sudo`.
- **Dial-up style modems** (not ECM/NCM) may need to redial after re-enumeration — use `POST_CMD`.
- The app is not notarized, so the first launch needs right-click → Open.

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.oceantang.lteguard
rm -f ~/Library/LaunchAgents/com.oceantang.lteguard.plist
rm -rf /Applications/LTEGuard.app ~/Library/"Application Support"/"LTE Guard"
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

**Ocean Tang (唐海洋)** is a practising lawyer at Beijing DOCVIT (Shenzhen) Law Firm, in the profession since 2011 and admitted since 2012.

- **Practice areas**: commercial litigation and arbitration, criminal defence and victim representation, employment disputes, corporate counsel work, due diligence
- **Track record**: 500+ contentious and non-contentious matters; standing counsel to a number of companies

**Why a lawyer writes apps**: CCNA in 2002, CIW Security Analyst in 2003, law degree from Wuhan University of Technology in 2005 — and years of writing VBA + Excel case-management tooling for his own practice (matter tracking, document generation, OCR extraction, automated mail). This app has an equally concrete origin: he converted a first-gen DJI video link into LTE backhaul and used it as a 4G modem — then had to unplug and replug it after every single lid close before the network would come back. Annoyed enough, he built this app together with Claude.

Happy to talk law or code — [Discussions](../../discussions) or an issue both work.

## License

MIT License
