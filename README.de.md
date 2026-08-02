# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>USB-Netzwerkadapter nach dem Zuklappen des Macs ohne Verbindung? Er repariert sich beim Aufwachen selbst – kein Aus- und Einstecken mehr.</b><br>
  <sub>Wächter für USB-Netzwerkadapter in der Menüleiste · natives Swift · ohne Abhängigkeiten · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <b>Deutsch</b> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.rw.md">Ikinyarwanda</a>
</p>

---

## Das Problem

Viele USB-LTE-Modems und USB-Ethernet-Adapter „hängen sich auf“, nachdem der Mac mit geschlossenem Deckel geschlafen hat: Die LED leuchtet noch, die Schnittstelle ist im System weiterhin vorhanden – nur fließen keine Daten mehr. **Erst nach dem Abziehen und erneuten Einstecken** funktioniert alles wieder.

Der Grund: Im Ruhezustand trennt macOS die USB-Stromversorgung nicht (VBUS wird direkt von der SMC-Firmware verwaltet und lässt sich per Software nicht abschalten), während die USB-Sitzung auf der Geräteseite bereits ungültig geworden ist. Ein Neustart des Netzwerkdienstes hilft deshalb nicht – zurückgesetzt werden muss die USB-Ebene.

## Für wen das gedacht ist

Sobald ein Mac über einen **externen USB-Netzwerkadapter** ins Internet geht, kann dieses Problem auftreten:

- 🚁 **Auf LTE umgebaute Drohnen-Videoübertragung** – etwa der Umbau der DJI-Videoübertragung der ersten Generation auf einen Mobilfunk-Rückkanal, während am Mac stundenlang ein 4G-/5G-Stick im Dauerbetrieb steckt
- 📡 **USB-LTE-/4G-/5G-Sticks, mobile WLAN-Router, USB-Mobilfunkmodule** – Außeneinsätze, Fahrzeug- und Bordbetrieb, Messen, temporäre Büros
- 🔌 **USB-C-/Thunderbolt-auf-Ethernet-Adapter** – der Mac hat keinen Netzwerkanschluss, das Kabel steckt im Besprechungsraum, im Serverraum oder beim Kunden
- 🧩 **Netzwerkanschlüsse in Docks** – Belkin, Plugable, Anker, CalDigit und andere
- 🎥 **Livestreaming, RTMP-Streaming und Fernwartung**, die auf einen stabilen Upload angewiesen sind
- 🖥 **Software-Router / Raspberry Pi / Industriegeräte**, die zum Debuggen per USB-Netzwerkadapter direkt am Mac hängen

Das Gemeinsame: einmal zugeklappt, und die Verbindung ist weg. Die LED leuchtet weiter, und **nur Aus- und Einstecken hilft**.

### Nicht nur Netzwerkadapter

Dasselbe Muster – „nach dem Aufwachen tot, nur physisches Aus- und Einstecken hilft“ – ist auch bei anderen USB-Geräten weit verbreitet. In der [offiziellen Apple-Community](https://discussions.apple.com/thread/7745583), bei [MacRumors](https://forums.macrumors.com/threads/mac-mini-m1-usb-ports-not-working-after-wake-from-sleep.2326616/) und in der [Plugable-Wissensdatenbank](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos) finden sich zahllose Berichte: Audio-Interfaces, Webcams, externe Festplatten, Kartenleser und einzelne Komponenten in Docks sind gleichermaßen betroffen.

Weil der zugrunde liegende Mechanismus derselbe ist, bietet das Menü dieses Werkzeugs den Punkt **„USB-Gerät zurücksetzen“**: Es listet alle aktuell angeschlossenen USB-Geräte auf; ein Klick genügt für ein softwareseitiges Aus- und Einstecken – Sie müssen kein Kabel mehr anfassen. Für Geräte außer Netzwerkadaptern ist derzeit ein manueller Anstoß nötig (die automatische Erkennung deckt nur das Netzwerk ab, weil „Verbindung vorhanden oder nicht“ ein eindeutiges Kriterium ist, während sich bei Webcams und Audio-Interfaces kaum automatisch feststellen lässt, ob sie hängen).

> ⚠️ Beenden Sie bei Speichergeräten wie externen Festplatten zuerst alle Lese- und Schreibvorgänge und werfen Sie das Volume aus – andernfalls drohen Datenverluste.

## Falls Sie über eine Suchmaschine hier gelandet sind

Die folgenden Formulierungen beschreiben höchstwahrscheinlich ein und dasselbe Problem – und genau dafür wurde dieses Werkzeug geschrieben:

> Mac Netzwerk geht nach Ruhezustand nicht mehr · USB-Netzwerkadapter nach Zuklappen ohne Verbindung · externer Adapter muss aus- und wieder eingesteckt werden · USB-C-Ethernet-Adapter funktioniert nach Standby nicht mehr · Dock-Netzwerkanschluss nach dem Aufwachen tot · LTE-Stick verliert nach dem Zuklappen die Verbindung · 4G-Stick nach dem Aufwachen ohne Internet · LED leuchtet, aber kein Internet · Schnittstelle vorhanden, aber ping schlägt fehl

Gängige englische Suchbegriffe (dieses Werkzeug passt genauso):

> `usb ethernet adapter not working after sleep mac` · `macbook ethernet doesn't wake up after sleep` · `usb-c ethernet adapter stops working after lid close` · `mac dock ethernet not detected after wake` · `lte modem disconnects after macbook sleeps` · `have to unplug and replug ethernet adapter macos`

### Wie verbreitet ist das Problem?

In der offiziellen Apple-Community, bei MacRumors und in der Plugable-Wissensdatenbank ziehen sich gleichartige Hilferufe über viele Jahre – und betreffen Intel- ebenso wie Apple-Silicon-Macs:

- [Ethernet USB-C adapter doesn't wake up after sleep](https://forums.macrumors.com/threads/ethernet-usb-c-adapter-doesnt-wake-up-after-sleep.2220969/) — MacRumors
- [Ethernet adapter doesn't want to wake up after sleep](https://discussions.apple.com/thread/8272273) — offizielle Apple-Community
- [MacBook Air 2020 USB LAN issue after sleep](https://discussions.apple.com/thread/255925525) — offizielle Apple-Community
- [Usb ethernet adapter is not working after sleep](https://discussions.apple.com/thread/7686532) · [Ethernet not waking after sleep](https://discussions.apple.com/thread/250166501) · [Ethernet reset/disconnect on wake-up](https://discussions.apple.com/thread/251074085) · [Ethernet disconnected after sleep](https://discussions.apple.com/thread/8425667)
- [Devices are not detected after waking from sleep on macOS](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos) — offizielle Plugable-Wissensdatenbank

### Warum die üblichen „offiziellen Lösungen“ nicht helfen

| Häufig empfohlene Maßnahme | Warum sie in diesem Fall nichts bringt |
|---|---|
| SMC / NVRAM zurücksetzen | Bei Apple-Silicon-Modellen **gibt es das Zurücksetzen des SMC überhaupt nicht**; und selbst auf Intel-Macs tritt das Problem beim nächsten Zuklappen wieder auf – es kuriert schlicht die falsche Krankheit |
| „Für Netzwerkzugriff aktivieren“ (Wake for network access) deaktivieren | Dieser Schalter steuert, ob das Gerät im Ruhezustand über das Netzwerk geweckt wird – mit der nach dem Aufwachen ungültigen USB-Sitzung hat das nichts zu tun |
| Vollständig herunterfahren und neu starten / System aktualisieren | Wirksam, aber absurd – soll man nach jedem Zuklappen den Rechner neu starten? |
| Das Netzwerkkabel abziehen statt des Adapters | Wird in Foren immer wieder empfohlen, hilft in der Praxis aber nicht (der ursprüngliche Verfasser wörtlich: „habe ich auch probiert, bringt nichts“) |
| **Den USB-Adapter abziehen und wieder einstecken** | Die einzige zuverlässig wirksame Methode – **und genau das erledigt dieses Werkzeug automatisch per Software** |

## Die Lösung

LTE Guard ist ein Wächter, der dauerhaft in der Menüleiste sitzt, die Aufwach-Ereignisse des Systems überwacht und den ausgewählten Netzwerkadapter nach dem Aufwachen automatisch prüft: Antwortet das Gateway nicht auf ping, führt das Programm über IOKit ein **softwareseitiges Aus- und Einstecken (USBDeviceReEnumerate)** des USB-Geräts durch. Das entspricht dem manuellen Umstecken und stellt die Verbindung **in der Regel in rund 8 Sekunden** wieder her.

- 🎯 **Herstellerunabhängig** – VID/PID werden nach der Auswahl des Adapters automatisch ermittelt, es gibt keine eingebaute Geräteliste
- 🔌 **Auch für Nicht-USB-Adapter** – greift automatisch auf den Neustart des Netzwerkdienstes zurück
- 🛠 **Nachgelagerte Befehle möglich** – nach der Wiederherstellung wird automatisch ein eigener Befehl ausgeführt (Proxy neu verbinden, neu einwählen usw.)
- 🌍 **62 Sprachen** – folgt automatisch der Systemsprache, lässt sich im Menü auch manuell umstellen
- 🪶 **Ohne Abhängigkeiten** – eine einzige App, kein Daemon, kein Homebrew

## Installation

**Variante 1: Installationspaket herunterladen** ([Releases](../../releases))

- `LTEGuard-x.y.z.dmg` – in den Ordner „Programme“ ziehen
- `LTEGuard-x.y.z.pkg` – doppelklicken zum Installieren, der Autostart wird automatisch eingerichtet

Falls beim ersten Öffnen „Entwickler kann nicht verifiziert werden“ erscheint (bei unsignierten Apps ganz normal): **Rechtsklick auf die App → Öffnen → erneut Öffnen**, oder im Terminal

```bash
xattr -dr com.apple.quarantine /Applications/LTEGuard.app
```

**Variante 2: selbst kompilieren** (Xcode Command Line Tools erforderlich)

```bash
git clone https://github.com/oceantangqoit/Mac-lte-guard.git
cd Mac-lte-guard && ./build.sh
```

Das Ergebnis liegt in `dist/`. Für das Rendern des Symbols wird `brew install librsvg` benötigt; ohne die Bibliothek lässt sich trotzdem bauen (die App verwendet dann das Standardsymbol).

## Erste Schritte

Beim ersten Öffnen nach der Installation führt Sie ein Assistent durch: **Erläuterung → zu überwachenden Netzwerkadapter auswählen → Nachfrage zum Autostart**. Einfach durchklicken.

Bei Problemen rufen Sie zuerst **Diagnose ausführen** im Menü auf. Sie prüft Punkt für Punkt und sagt Ihnen direkt, was zu tun ist:

| Prüfpunkt | Bedeutung und Abhilfe im Fehlerfall |
|---|---|
| Installationsort | Steht dort `/Volumes/…`, starten Sie die App direkt aus dem DMG – ziehen Sie sie zuerst in den Ordner „Programme“ |
| Quarantäne-Attribut (Gatekeeper) | Bei unsignierten Apps ganz normal. Lässt sich die App nicht öffnen: **Rechtsklick auf die App → Öffnen → Öffnen**, oder `xattr -dr com.apple.quarantine /Applications/LTEGuard.app` |
| Reparaturwerkzeug | Ob usbreset verfügbar ist; normalerweise wird es zusammen mit der App installiert, eine separate Installation ist nicht nötig |
| Überwachungsziel | Ob ein Adapter ausgewählt wurde und die Schnittstelle tatsächlich existiert (bei einem Adapterwechsel erscheint ein Hinweis) |
| Bei der Anmeldung starten | Ist die Option ausgeschaltet, läuft die App nach einem Neustart nicht automatisch; im Menü mit einem Klick aktivierbar |

**Zu den Berechtigungen**: Dieses Werkzeug benötigt **überhaupt keine erhöhten Rechte** – keine Bedienungshilfen, keinen Festplattenvollzugriff, kein root und keinen installierten Hintergrund-Daemon.

## Verwendung

1. Nach dem Start erscheint ein Signalsymbol in der Menüleiste
2. Menü öffnen → **Zu heilendes Gerät auswählen …** → Ihren Netzwerkadapter wählen (Einträge mit der Kennzeichnung `· USB` unterstützen das softwareseitige Aus- und Einstecken)
3. Fertig. Ab jetzt wird nach dem Zuklappen und Aufklappen eine unterbrochene Verbindung von selbst repariert

Die übrigen Menüpunkte:

| Punkt | Funktion |
|---|---|
| Jetzt prüfen und reparieren | Löst den Vorgang einmalig manuell aus |
| Protokoll anzeigen | Öffnet `~/.lte-wake.log` |
| Bei der Anmeldung starten | Schalter, jederzeit änderbar (auch bei Installation per DMG verfügbar) |
| Diagnose ausführen | Prüft alle Punkte und nennt die passende Abhilfe |
| Befehl nach der Wiederherstellung … | Optionaler Hook: Nach der Wiederherstellung des Adapters wird automatisch ein Shell-Befehl ausgeführt (leer lassen = keine Aktion) |
| USB-Gerät zurücksetzen | Listet alle USB-Geräte auf, softwareseitiges Aus- und Einstecken per Klick – ebenso geeignet für Audio-Interfaces, Webcams, Festplatten und Docks |
| Menüleistensymbol | Immer anzeigen / nur bei Störungen anzeigen / ausblenden (**nach dem Ausblenden holen Sie es zurück, indem Sie die App aus dem Ordner „Programme“ erneut öffnen**) |
| Konfigurationsordner öffnen | Öffnet Konfiguration, Protokoll und Sprachordner mit einem Klick im Finder |
| Sprache | Umschalten zwischen 62 Sprachen; im Untermenü lässt sich die aktuelle Sprache bearbeiten oder der Sprachordner öffnen |

## Von rechts nach links geschriebene Sprachen (RTL)

Vier von rechts nach links geschriebene Sprachen sind enthalten: **العربية** (Arabisch), **עברית** (Hebräisch), **فارسی** (Persisch) und **اردو** (Urdu).

Da die Sprachumschaltung dieses Werkzeugs innerhalb der App selbst umgesetzt ist (Einlesen von `lang/*.ini`) und nicht über den `.lproj`-Lokalisierungsmechanismus von macOS läuft, spiegelt das System die Oberfläche nicht automatisch. Deshalb greifen zwei Ebenen:

1. **Spiegelung der Oberfläche** – beim Wechsel zu einer RTL-Sprache werden Menü und Untermenüs auf `.rightToLeft` gesetzt: Text rechtsbündig, Symbole nach rechts, Untermenü-Pfeile gespiegelt;
2. **Isolierung bidirektionalen Texts** – die in die Texte eingesetzten Werte (Schnittstellenname `en2`, `2c7c:0125`, Dienstnamen usw.) bestehen aus lateinischen Buchstaben und Ziffern. Direkt in einen arabischen Satz eingebettet, werden sie vom Unicode-BiDi-Algorithmus umsortiert, **Doppelpunkte und Klammern landen auf der falschen Seite**. Deshalb werden alle Platzhalter beim Ersetzen mit `U+2068 FSI` / `U+2069 PDI` umschlossen (die vom W3C empfohlene i18n-Praxis), sodass jeder eingesetzte Wert eine eigenständige Richtungseinheit bildet.
3. Das Eingabefeld für „Befehl nach der Wiederherstellung“ wird zwingend linksbündig ausgerichtet – Shell-Befehle sind immer lateinisch, rechtsbündig wären sie schlechter lesbar.

## Mehrsprachigkeit

**62 Sprachen** sind enthalten; beim Start wird automatisch die Systemsprache gewählt, im Menü „Sprache“ lässt sich manuell umschalten (die Auswahl wird gespeichert).

Die später hinzugekommenen Sprachen wurden KI-gestützt übersetzt und sind noch nicht von Muttersprachlern geprüft; ein entsprechender Hinweis steht im Kopf der jeweiligen Datei. **Wenn Ihnen eine Formulierung unnatürlich vorkommt, ändern Sie gern einfach eine Zeile und schicken einen Pull Request** – das ist der einfachste Weg, etwas beizutragen.

**Formulierungen einer vorhandenen Sprache ändern**: Über „Sprache → Aktuelle Sprache bearbeiten …“ wird die INI-Datei der aktuellen Sprache **aus der App in Ihren Sprachordner kopiert und direkt geöffnet**. Nach dem Bearbeiten die App neu starten. Diese Kopie hat Vorrang vor der eingebauten Fassung und **wird auch bei einem Update der App nicht überschrieben**.

Beim Export erscheint zunächst ein Hinweis, und es passiert eine Sache: **Der Name und die Kontaktdaten des ursprünglichen Autors werden entfernt und durch Ihren Namen ersetzt.** Diese Kopie ist ab dem Moment des Exports also Ihre eigene Datei; für den Inhalt sind Sie verantwortlich, der ursprüngliche Autor hat damit nichts zu tun – schreiben Sie bitte nichts Rechtswidriges, Beleidigendes oder die Rechte Dritter Verletzendes hinein. Die Datei bleibt ausschließlich auf Ihrem eigenen Rechner und wird nicht automatisch hochgeladen.

**Eine neue Sprache hinzufügen**: Menü „Sprache → Sprachordner öffnen …“ (dort werden automatisch die beiden Vorlagen `zhs.template.ini` für vereinfachtes Chinesisch und `en.template.ini` für Englisch abgelegt). Kopieren Sie eine davon, benennen Sie sie nach dem Sprachcode der Zielsprache (z. B. `nl.ini`) und übersetzen Sie jeweils den Teil rechts vom Gleichheitszeichen.

Die Suchreihenfolge für Sprachdateien lautet: **Ihr Sprachordner → in der App enthaltene Dateien**; bei gleichem Dateinamen gilt Ihre Fassung. Fertige Dateien gern per Pull Request einreichen, damit alle Nutzer derselben Sprache davon profitieren.

**Format der Sprachdateien**: eine INI-Datei je Sprache im Verzeichnis `lang/`, mit Zahlencodes als Schlüsseln:

```ini
[meta]
name=Deutsch
author=……

[strings]
1=LTE Guard
2=Überwacht: {0}  {1}
3=● Normal
```

`{0}` und `{1}` sind Platzhalter, die vom Programm gefüllt werden.

## Konfigurationsdatei

`~/.lte-guard.conf` (wird von der App automatisch gepflegt, kann aber auch von Hand bearbeitet werden):

```sh
DEV="en2"              # Netzwerkschnittstelle
SERVICE="My LTE"       # Name des Netzwerkdienstes (für den Dienstneustart bei Nicht-USB-Geräten)
USB_VID="2c7c"         # USB-Hersteller-ID; leer lassen, um auf den Dienstneustart umzuschalten
USB_PID="0125"         # USB-Produkt-ID
POST_CMD=''            # Befehl nach der Wiederherstellung, z. B. Neustart des Proxy-Prozesses
```

Beispiel für `POST_CMD` – nach der Wiederherstellung einen an diesen Adapter gebundenen gost-Proxy neu starten:

```sh
POST_CMD='launchctl kickstart -k gui/$(id -u)/com.user.gost-lte'
```

## Funktionsweise

```
Aufwachen des Systems (IORegisterForSystemPower)
      ↓  5 Sekunden warten, bis die Schnittstelle stabil ist
ping zum Gateway, zweifach bestätigt  → erreichbar → Ende
      ↓ nicht erreichbar
USBDeviceReEnumerate      → falls kein USB: Dienstneustart per networksetup
      ↓  im Polling auf eine IP warten (max. 60 s)
POST_CMD ausführen → Protokoll schreiben → Menüleistensymbol aktualisieren
```

Mit 90 Sekunden Abkühlzeit, um wiederholtes Flattern zu vermeiden.

## Kompatibilität und Teststand

### In der Praxis verifiziert

| Punkt | Umgebung |
|---|---|
| Modell | MacBook (Apple Silicon, arm64) |
| System | macOS 26 (Darwin 25.x) |
| Netzwerkadapter | Quectel EC25 (VID `2c7c` / PID `0125`), erscheint im ECM/NCM-Modus als `enX` |
| Szenario | Zugeklappt in den Ruhezustand → nach dem Aufwachen ist die Schnittstelle vorhanden, das Gateway aber nicht erreichbar → nach dem softwareseitigen Aus- und Einstecken **nach etwa 8 Sekunden wiederhergestellt**, mehrfach hintereinander reproduzierbar |
| Zusätzlich | Nach der Wiederherstellung wird der an diesen Adapter gebundene Proxy-Prozess automatisch neu gestartet (`POST_CMD`) |

### Sollte prinzipbedingt funktionieren, es fehlen aber Praxisrückmeldungen

| Szenario | Einschätzung und mögliche Anpassungen |
|---|---|
| **Intel-Macs** | Auf manchen Intel-Modellen benötigt `USBDeviceReEnumerate` root-Rechte; im Protokoll erscheint dann `open failed … try sudo`. Abhilfe: einmal mit `sudo` ausführen und prüfen, oder auf „Netzwerkdienst neu starten“ umstellen (dafür einfach `USB_VID` in der Konfiguration leer lassen) |
| **macOS 13 / 14 / 15** | Die verwendeten APIs (IOKit-Energiebenachrichtigungen, `USBDeviceReEnumerate`, `NSStatusItem.isVisible`) sind alle seit 13 stabile Schnittstellen, es sollte also funktionieren. Unterhalb von 13 startet die App nicht (in der Info.plist begrenzt) |
| **USB-auf-Ethernet-Adapter** (AX88179, RTL8153, CM3xx usw.) | Gleiches Prinzip, sollte funktionieren. Beachten Sie: Bei manchen Adaptern ändert sich nach der Neuenumeration der Schnittstellenname (`en5`→`en6`); wählen Sie in diesem Fall im Menü einmal erneut „Zu heilendes Gerät auswählen“ |
| **Einwahl-4G-Module** (kein ECM/NCM, sondern PPP-/AT-Einwahl) | Nach der Neuenumeration ist eine erneute Einwahl nötig, sonst wird nach 60 Sekunden Wartezeit ein Fehlschlag gemeldet. Abhilfe: Tragen Sie unter „Befehl nach der Wiederherstellung“ Ihren Einwahl- bzw. Wiederverbindungsbefehl ein |
| **Netzwerkadapter in Docks** | Wird das USB-Gerät des gesamten Docks neu enumeriert, werden auch die übrigen Geräte am Dock zurückgesetzt (externe Festplatten, Webcams). Hängt eine gerade beschriebene Festplatte am Dock, empfiehlt sich der Weg über „Netzwerkdienst neu starten“ |
| **Verbundgeräte** (Netzwerkadapter + Kartenleser + serielle Schnittstelle in einem) | Wie oben: Das Zurücksetzen betrifft auch die anderen Funktionen desselben USB-Geräts |
| **iPhone-USB-Tethering** | Es handelt sich um ein Apple-eigenes NCM-Gerät, das sich in der Regel selbst erholt; tritt dasselbe Problem auf, ist dieses Werkzeug prinzipbedingt ebenfalls geeignet |
| **Nicht-USB-Schnittstellen wie WLAN oder Thunderbolt-Ethernet** | Es wird automatisch auf „Netzwerkdienst neu starten“ zurückgegriffen. Das behebt Hänger auf Softwareebene, nicht aber Blockaden auf Treiberebene |

Steht Ihr Gerät nicht in der Tabelle, **freue ich mich über ein Issue mit Ihrem Ergebnis** (Modell, `USB VID:PID`, Ausschnitt aus `~/.lte-wake.log`) – ganz gleich, ob es geklappt hat oder nicht. Das ist derzeit die wertvollste Rückmeldung.

## Warum es kein „Verbindung im Ruhezustand halten“ gibt

Frühere Versionen hatten diesen Schalter; nachdem sich in der Praxis zeigte, dass er nichts bringt, wurde er entfernt. Die Gründe sind es wert, festgehalten zu werden, damit andere nicht dieselben Umwege gehen:

- **`caffeinate -i -s` hält den Ruhezustand beim Zuklappen nicht auf.** In `man caffeinate` steht ausdrücklich, dass die Assertion `-s` *„is valid only when system is running on AC power“* – und außerdem verhindert sie den **Leerlauf-Ruhezustand**. Der **Ruhezustand beim Zuklappen (Clamshell Sleep) ist ein eigener, unabhängiger Auslösepfad**, der sich auch am Netzteil nicht abfangen lässt (außer der Mac läuft mit externem Display im Clamshell-Betrieb). In den Testprotokollen lief caffeinate durchgehend, und das System vermerkte trotzdem `Entering Sleep state due to 'Clamshell Sleep'`.
- **Das Einzige, was ihn wirklich verhindert, ist `sudo pmset -a disablesleep 1`** (der Weg von Werkzeugen wie Amphetamine oder InsomniaX), was aber root-Rechte erfordert. Außerdem bedeutet „zugeklappt und trotzdem wach“, dass die CPU weiterläuft – **ein zugeklapptes Notebook, das in der Tasche nicht schläft, überhitzt tatsächlich**.
- Nach Abwägung: Dieses Werkzeug konzentriert sich darauf, genau eine Sache gut zu machen – „nach dem Aufwachen in 8 Sekunden selbst heilen“ – und vergrößert die Angriffsfläche nicht für ein Nischenszenario, das erhöhte Rechte verlangt und ein Hardwarerisiko birgt.

**Sie brauchen wirklich eine durchgehende Verbindung bei zugeklapptem Deckel** (laufende Downloads, unbeaufsichtigtes Streaming, dauerhafte Fernverbindungen)? Dann empfiehlt sich die Kombination mit [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) (kostenlos, im App Store) – das hält den Rechner wach, dieses Werkzeug repariert automatisch, falls die Verbindung doch abreißt. Jeder macht, was er am besten kann.

## Bekannte Einschränkungen

- **Die USB-Stromversorgung wirklich zu trennen, ist nicht möglich** – VBUS wird bei Apple Silicon von der SMC-Firmware gesteuert, eine öffentliche API gibt es nicht. Für eine echte physische Trennung bleibt nur ein externer USB-Hub mit PPPS-Unterstützung in Verbindung mit [uhubctl](https://github.com/mvp/uhubctl).
- Auf **Intel-Macs** benötigt `USBDeviceReEnumerate` gelegentlich root-Rechte; im Protokoll erscheint dann der Hinweis `try sudo`.
- **Einwahl-Modems** (kein ECM/NCM) müssen sich nach der Neuenumeration eventuell erneut einwählen; ergänzen Sie das über `POST_CMD`.
- Die App ist nicht von Apple notarisiert; beim ersten Öffnen ist Rechtsklick → Öffnen nötig.

## Deinstallation

```bash
launchctl bootout gui/$(id -u)/com.oceantang.lteguard
rm -f ~/Library/LaunchAgents/com.oceantang.lteguard.plist ~/.lte-guard.conf ~/.lte-wake.log
rm -rf /Applications/LTEGuard.app
```

## Das Projekt unterstützen

Wenn Ihnen dieses kleine Werkzeug das ständige Aus- und Einstecken von USB-Geräten erspart:

- ⭐ Geben Sie dem Repository einen Stern oder empfehlen Sie es Menschen, die dasselbe Problem plagt
- 🐛 Melden Sie in einem Issue Ihr Gerätemodell und Ihre Protokolle, damit mehr Adapter abgedeckt werden
- 🌍 Steuern Sie eine Übersetzung bei ([CONTRIBUTING.md](CONTRIBUTING.md), es genügen ein paar Zeilen in einer INI-Datei)
- ☕ Spendieren Sie dem Autor einen Kaffee

Mehr dazu unter [Das Projekt unterstützen](SPONSOR.md).

## Austausch und Kontakt

- 💬 Fragen zur Nutzung und Ideen: [Discussions](../../discussions)
- 🐛 Fehler und Funktionswünsche: [Issues](../../issues)

### Über den Autor

**Tang Haiyang (Ocean Tang)**, zugelassener Rechtsanwalt bei Beijing Dongyuan (Shenzhen) Law Firm, seit 2011 in der Branche und seit 2012 als Anwalt tätig.

- **Tätigkeitsfelder**: Handelsstreitigkeiten und Schiedsverfahren, Strafverteidigung und Vertretung von Opfern in Strafsachen, Arbeitsrechtsstreitigkeiten, ständige Rechtsberatung für Unternehmen, Due Diligence
- **Berufserfahrung**: über 500 vertretene streitige und nichtstreitige Mandate, ständiger Rechtsberater mehrerer Organisationen

**Warum ein Anwalt eine App schreibt**: Ich habe bereits 2002 den CCNA und 2003 den CIW Security Analyst gemacht und 2005 mein Studium an der Wuhan University of Technology abgeschlossen. Seither schreibe ich mir mit VBA + Excel meine eigenen Werkzeuge für die Fallverwaltung (Fallverfolgung, Erzeugung von Standardschriftsätzen, OCR-Extraktion, automatische E-Mails). Auch der Anlass für diese App war sehr konkret: Ich hatte zum Vergnügen die DJI-Videoübertragung der ersten Generation auf einen LTE-Rückkanal umgebaut und als 4G-Stick benutzt – und musste danach nach jedem Zuklappen und Aufklappen erst einmal alles aus- und wieder einstecken, um weiter online zu sein. Das nervte so sehr, dass ich diese App kurzerhand gemeinsam mit Claude geschrieben habe.

Ob es um juristische oder um technische Themen geht – schauen Sie gern in den [Discussions](../../discussions) vorbei oder eröffnen Sie ein Issue.

## Lizenz

MIT License
