# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>USB-Netzwerkadapter nach dem Ruhezustand tot? Er repariert sich beim Aufwachen selbst — kein Aus- und Einstecken mehr.</b><br>
  <sub>USB-Netzwerkadapter-Wächter in der Menüleiste · natives Swift · ohne Abhängigkeiten · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.ru.md">Русский</a> · <a href="README.rw.md">Ikinyarwanda</a>
</p>

---

## Das Problem

Viele USB-LTE-Modems und USB-Ethernet-Adapter „hängen“, nachdem der Mac mit geschlossenem Deckel geschlafen hat: Die LED leuchtet noch, die Schnittstelle ist im System vorhanden — aber es fließt kein Datenverkehr. **Nur physisches Aus- und Einstecken hilft.**

Ursache: macOS unterbricht im Ruhezustand die USB-Stromversorgung nicht (VBUS wird direkt von der SMC-Firmware verwaltet, ohne öffentliche API), während die USB-Sitzung auf der Geräteseite bereits tot ist. Ein Neustart des Netzwerkdienstes hilft deshalb nicht — zurückgesetzt werden muss die USB-Ebene.

## Über die Suche hierher gekommen?

Diese Formulierungen beschreiben dasselbe Problem:

> USB Ethernet Adapter funktioniert nicht nach Ruhezustand Mac · MacBook LAN Adapter nach Standby ohne Funktion · USB-C Ethernet Adapter nach Zuklappen tot · Dock Netzwerkanschluss wird nach Aufwachen nicht erkannt · LTE Stick verliert Verbindung nach Ruhezustand

In Apples eigenen Foren und auf MacRumors finden sich seit Jahren identische Berichte — auf Intel- wie auf Apple-Silicon-Macs. Die üblichen Ratschläge (SMC-/NVRAM-Reset) gibt es auf Apple Silicon gar nicht mehr und sie beheben die Ursache nicht. **Zuverlässig wirkt nur das Aus- und Einstecken — genau das automatisiert dieses Werkzeug.**

## Die Lösung

LTE Guard sitzt in der Menüleiste und lauscht auf Aufwach-Ereignisse. Danach prüft es den gewählten Adapter: Antwortet das Gateway nicht, führt es über IOKit ein **software-seitiges Aus- und Einstecken (USBDeviceReEnumerate)** durch. Das entspricht dem physischen Vorgang — die Verbindung steht meist **nach rund 8 Sekunden** wieder.

- 🎯 **Herstellerunabhängig** — VID/PID werden bei der Auswahl automatisch erkannt, keine Geräteliste
- 🔌 **Auch für Nicht-USB-Adapter** — greift automatisch auf den Neustart des Netzwerkdienstes zurück
- 🛠 **Befehl nach der Wiederherstellung** — z. B. Proxy neu starten oder erneut einwählen
- 🌍 **28 Sprachen** — folgt der Systemsprache, im Menü umschaltbar
- 🪶 **Keine Abhängigkeiten** — eine einzige App, kein Daemon, kein Homebrew

## Installation

`.dmg` aus den [Releases](../../releases) laden und in „Programme“ ziehen.

Meldet macOS beim ersten Start, der Entwickler könne nicht verifiziert werden (normal bei unsignierten Apps): **Rechtsklick auf die App → Öffnen → Öffnen**, oder im Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/LTEGuard.app
```

## Verwendung

1. Nach dem Start erscheint ein Symbol in der Menüleiste
2. Menü → **Ziel wählen…** → Adapter auswählen (Einträge mit `· USB` unterstützen das Software-Replug)
3. Fertig. Ab jetzt wird nach dem Zuklappen automatisch repariert

Bei Problemen hilft **Diagnose ausführen** im Menü weiter.

---

Ausführliche Dokumentation (Kompatibilitätsmatrix, Konfigurationsdatei, Übersetzungen beisteuern): [English README](README.en.md).

## License

MIT License
