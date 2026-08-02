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

### So wird es in deutschsprachigen Foren gefragt

> Kein LAN nach Ruhezustand · MacBook verliert Internet-Verbindung nach dem Sleep-Modus · der Adapter muss rausgezogen und wieder eingesteckt werden · USB-Probleme nach Ruhezustand · USB-Gerät nach dem Aufwachen nicht erkannt · Dock nach Standby nicht erkannt · Festplatte nicht korrekt ausgeworfen · externe Platte fliegt beim Ruhezustand raus · Kein Internet nach Aufwachen aus dem Ruhezustand · USB-Maus wird nach Ruhezustand nicht gefunden · Kartenlesegerät wird beim Starten aus Standby nicht erkannt · LED leuchtet, aber kein Internet · Schnittstelle vorhanden, aber ping schlägt fehl

Ein Nutzer in der MacUser.de-Community beschreibt das Problem wörtlich so:

> „sobald ich das MacBook in den Standby Modus schalte und dann wieder einschalte verliert er die Verbindung zum Internet nun muss ich den Adapter wieder hinaus ziehen und wieder einstecken.“
> — [MacBook verliert Internet Verbindung nach dem Sleep Modus (USB Lan Adapter)](https://www.macuser.de/threads/macbook-verliert-internet-verbindung-nach-dem-sleep-modus-usb-lan-adapter.905945/)

**Genau dieses „hinaus ziehen und wieder einstecken“ erledigt dieses Werkzeug automatisch per Software.**

### Echte Thread-Titel (unverändert zitiert)

Alles reale, öffentlich einsehbare Beiträge aus dem deutschsprachigen Raum – Wortlaut unverändert.

**MacUser.de Community**

> „[Kein LAN nach Ruhezustand](https://www.macuser.de/threads/kein-lan-nach-ruhezustand.821097/)“ · „[MacBook verliert Internet Verbindung nach dem Sleep Modus (USB Lan Adapter)](https://www.macuser.de/threads/macbook-verliert-internet-verbindung-nach-dem-sleep-modus-usb-lan-adapter.905945/)“ · „[Mac erkennt Netzwerk nicht mehr (über USB/Ethernet) – macOS Sierra](https://www.macuser.de/threads/mac-erkennt-netzwerk-nicht-mehr-uber-usb-ethernet-macos-sierra.757335/)“ · „[Kein Internet nach Aufwachen aus dem Ruhezustand](https://www.macuser.de/threads/kein-internet-nach-aufwachen-aus-dem-ruhezustand.9298/)“ · „[OS X trennt USB Platte im Ruhezustand](https://www.macuser.de/threads/os-x-trennt-usb-platte-im-ruhezustand.772053/)“ · „[iMac trennt externen Platten im Ruhezustand](https://www.macuser.de/threads/imac-trennt-externen-platten-im-ruhezustand.744455/)“ · „[Seit Tahoe ständig Probleme beim Remounten von ext. Laufwerken nach Ruhezustand](https://www.macuser.de/threads/seit-tahoe-standig-probleme-beim-remounten-von-ext-laufwerken-nach-ruhezustand.963435/)“ · „[USB-Geräte werden nicht erkannt, Apple Support weiß nicht weiter](https://www.macuser.de/threads/usb-gerate-werden-nicht-erkannt-apple-support-weiss-nicht-weiter.878601/)“ · „[USB-Zubehör wird nicht erkannt](https://www.macuser.de/threads/usb-zubehor-wird-nicht-erkannt.932611/)“ · „[Logitech C920 USB Webcam nicht mehr erkannt](https://www.macuser.de/threads/logitech-c920-usb-webcam-nicht-mehr-erkannt.931747/)“

**Apfeltalk**

> „[USB-Probleme nach Ruhezustand](https://www.apfeltalk.de/community/threads/13-mbpr-usb-probleme-nach-ruhezustand.502884/)“ (13" MBPr) · „[USB Probleme im Standby](https://www.apfeltalk.de/community/threads/usb-probleme-im-standby.489003/)“ (10.11 El Capitan) · „[USB C Adapter - Ethernet funktioniert nicht](https://www.apfeltalk.de/community/threads/usb-c-adapter-ethernet-funktioniert-nicht.508901/)“ · „[USB Ethernet Adaptor läuft nicht](https://www.apfeltalk.de/community/threads/usb-ethernet-adaptor-laeuft-nicht.382085/)“ · „[Verbindung eines Lan-Kabels über 8-in-1 USB-C Hub an MacBook nicht möglich](https://www.apfeltalk.de/community/threads/verbindung-eines-lan-kabels-ueber-8-in-1-usb-c-hub-an-macbook-nicht-moeglich.559243/)“ · „[Belkin USB-Hub Probleme](https://www.apfeltalk.de/community/threads/belkin-usb-hub-probleme.77953/)“

**Apple Community (deutsch) und weitere**

> „[USB-Maus wird nach Ruhezustand nicht gefunden](https://communities.apple.com/de/thread/252509070)“ · „[USB-Maus funktioniert nach Standby nicht](https://communities.apple.com/de/thread/255462034)“ · „[Externe Festplatte nach Ruhezustand ‚nicht korrekt ausgeworfen‘](https://communities.apple.com/de/thread/253685545)“ · „[Probleme mit USB-Hub: Nach Ruhezustand kommt die Meldung, dass angeschlossene Festplatten unsachgemäß ausgeworfen wurden.](https://www.macfix.de/entries/mix/669010)“ (MacFix) · „[Kartenlesegerät wird beim Starten aus Standby nicht erkannt](https://homebanking-hilfe.de/forum/topic.php?t=14475)“ (homebanking-hilfe.de)

Zu macOS 26 Tahoe schreibt ein Betroffener auf MacUser.de: „Seit dem Update zu Tahoe werden meine externen Festplatten beim Beenden des Ruhezustands nur in etwa 50% der Fälle wieder korrekt gemountet.“ Die deutsche Fachpresse titelte dazu: „Externe Festplatten und Docks werden zu Geistern“.

### Gängige Suchbegriff-Kombinationen

> `mac usb netzwerkadapter nach ruhezustand ohne verbindung` · `kein lan nach ruhezustand mac` · `macbook verliert internet nach standby usb lan adapter` · `usb gerät nach dem aufwachen nicht erkannt mac` · `mac usb adapter abziehen und wieder einstecken` · `externe festplatte nach ruhezustand nicht korrekt ausgeworfen` · `dock nach standby nicht erkannt macbook` · `usb-c hub ethernet funktioniert nicht mac` · `usb maus nach ruhezustand nicht gefunden` · `macos tahoe usb geräte getrennt` · `rtl8153 mac treiber problem` · `ax88179 mac nicht erkannt`

Gängige englische Suchbegriffe (dieses Werkzeug passt genauso):

> `usb ethernet adapter not working after sleep mac` · `macbook ethernet doesn't wake up after sleep` · `usb-c ethernet adapter stops working after lid close` · `mac dock ethernet not detected after wake` · `lte modem disconnects after macbook sleeps` · `have to unplug and replug ethernet adapter macos`

### Nach Gerätetyp

| Ihr Gerät | Wie deutschsprachige Nutzer es beschreiben |
|---|---|
| USB-Ethernet-Adapter | „Kein LAN nach Ruhezustand“ · „verliert das MBP die LAN-Verbindung und stellt sie auch nicht mehr her“ · „der Adapter muss rausgezogen und wieder eingesteckt werden“ · in den Netzwerkeinstellungen bleibt es bei „Nicht verbunden“ |
| LTE-/4G-Surfstick, Mobilfunk-Modem | „Kein Internet nach Aufwachen aus dem Ruhezustand“ · in Foren empfohlen: „den USB-Stick abziehen und nach 10–15 Sekunden wieder einstecken“ |
| Dock / USB-C-Hub (Belkin, LMP, Plugable, Anker, CalDigit) | „USB-Probleme nach Ruhezustand“ · „Verbindung eines Lan-Kabels über 8-in-1 USB-C Hub an MacBook nicht möglich“ · direkt am Mac läuft alles, über den Hub nicht |
| Externe Festplatte / SSD | „Festplatte nicht korrekt ausgeworfen“ · „OS X trennt USB Platte im Ruhezustand“ · „nur in etwa 50 % der Fälle wieder korrekt gemountet“ |
| Webcam / Audio-Interface | „Logitech C920 USB Webcam nicht mehr erkannt“ – im USB-Manager noch sichtbar, in der Geräteauswahl der App aber nicht mehr auswählbar |
| Kartenleser / Tastatur / Maus | „Kartenlesegerät wird beim Starten aus Standby nicht erkannt“ · „USB-Maus wird nach Ruhezustand nicht gefunden“ · erst ein Neustart oder das Umstecken hilft |

### Häufig genannte Chipsätze

In deutschsprachigen Foren werden als Ursache regelmäßig diese Chips benannt:

> ASIX `AX88179` / `AX88179A` (in Apfeltalk-Threads heißt es, man brauche dafür den ASIX-Treiber) · Realtek `RTL8153` · Realtek `RTL8156` (2,5 GbE) · Quectel `EC25` · Intel `I225-V` (über Thunderbolt-Dock)

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

LTE Guard ist ein Wächter, der dauerhaft in der Menüleiste sitzt und die Aufwach-Ereignisse des Systems überwacht. **Unmittelbar** nach dem Aufwachen führt das Programm über IOKit ein **softwareseitiges Aus- und Einstecken (USBDeviceReEnumerate)** des USB-Geräts durch – das entspricht dem manuellen Umstecken. Auf eine Vorprüfung nach dem Motto „muss überhaupt repariert werden?“ wird bewusst verzichtet: Wer dieses Werkzeug installiert, hat ohnehin einen Adapter, der sich aufhängt – Prüfen wäre reine Zeitverschwendung. Als wiederhergestellt gilt die Verbindung erst, wenn das **Gateway tatsächlich auf ping antwortet** – **in der Regel nach rund 8 Sekunden**, nahe an der physikalischen Grenze des manuellen Umsteckens.

- 🎯 **Herstellerunabhängig** – VID/PID werden nach der Auswahl des Adapters automatisch ermittelt, es gibt keine eingebaute Geräteliste
- 🖇 **Überwacht mehrere Adapter gleichzeitig** – einfach alle gewünschten ankreuzen; jeder wird unabhängig geprüft und parallel repariert
- 🔌 **Auch für Nicht-USB-Adapter** – greift automatisch auf den Neustart des Netzwerkdienstes zurück
- 🛠 **Befehls-Hooks in zwei Phasen** – ein Satz läuft **im Moment der erkannten Unterbrechung** (z. B. die Netzwerkeinstellungen öffnen und der Reparatur live zusehen), ein weiterer **nach der Wiederherstellung** (Proxy neu verbinden, neu einwählen usw.)
- 🔔 **Benachrichtigung nur bei Erfolg** – genau eine Meldung, sobald der Adapter wieder da ist *und* der Internetzugang nachweislich funktioniert (mit Zeitangabe); laufende Reparatur, fehlender Internetzugang und Fehlschlag zeigen sich nur im Menüleistensymbol (Kreisel / `✓8s` / `⚠︎` / `✕`)
- 🌍 **62 Sprachen** – Oberfläche und Protokoll vollständig lokalisiert; folgt automatisch der Systemsprache, lässt sich im Menü auch manuell umstellen
- 🪶 **Ohne Abhängigkeiten** – eine einzige App, kein Daemon, kein Homebrew, keinerlei erhöhte Rechte

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
2. Menü öffnen → **Zu heilendes Gerät auswählen …** → Ihren Netzwerkadapter wählen – **Mehrfachauswahl möglich** (Einträge mit der Kennzeichnung `· USB` unterstützen das softwareseitige Aus- und Einstecken)
3. Fertig. Ab jetzt wird nach dem Zuklappen und Aufklappen eine unterbrochene Verbindung von selbst repariert

Die übrigen Menüpunkte:

| Punkt | Funktion |
|---|---|
| Jetzt prüfen und reparieren | Löst den Vorgang einmalig manuell aus |
| Protokoll anzeigen | Öffnet `~/.lte-wake.log` |
| Bei der Anmeldung starten | Schalter, jederzeit änderbar (auch bei Installation per DMG verfügbar) |
| Diagnose ausführen | Prüft alle Punkte und nennt die passende Abhilfe |
| Befehl nach der Wiederherstellung … | Hooks in zwei Phasen: „bei erkannter Unterbrechung“ (z. B. die Netzwerkeinstellungen öffnen und der Reparatur zusehen) und „nach der Wiederherstellung“ (z. B. Proxy neu verbinden) – ein Befehl pro Zeile, der Reihe nach ausgeführt; häufig gebrauchte Aktionen lassen sich einfach ankreuzen |
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

`~/.lte-guard.conf` (wird von der App automatisch gepflegt, kann aber auch von Hand bearbeitet werden; alte Konfigurationen mit nur einem Überwachungsziel werden automatisch übernommen):

```sh
# ein Heilungsziel pro Zeile, durch Tabulatoren getrennt: Schnittstelle, Dienstname, USB_VID, USB_PID
TARGETS='en2	My LTE	2c7c	0125'
PRE_CMD=''             # läuft im Moment der erkannten Unterbrechung (das Netzwerk ist gerade ausgefallen – nicht darauf verlassen)
POST_CMD=''            # läuft nach der Wiederherstellung, z. B. Neustart eines Proxys
```

**Beide Hooks nehmen mehrere Befehle entgegen** – ein Befehl pro Zeile, ausgeführt der Reihe nach. `PRE_CMD` startet **im selben Augenblick** wie die Erkennung: Wer dort die Netzwerkeinstellungen öffnen lässt, kommt gerade rechtzeitig, um die gesamte Reparatur mitzuverfolgen.

Der Dialog bietet Ankreuzfelder in zwei Gruppen – ein Häkchen trägt den Befehl sofort in das passende Textfeld ein, das Entfernen löscht ihn wieder:

**Häufig verwendet** (immer verfügbar)

- Systemeinstellungen → Netzwerk öffnen (landet im Feld für die Unterbrechung) – sehen Sie mit eigenen Augen zu, wie die abgerissene Verbindung zurückkehrt
- Einen Hinweiston abspielen
- Eine Webhook-Benachrichtigung senden (ersetzen Sie die Platzhalter-URL durch Ihre eigene; praktisch für unbeaufsichtigte Rechner)

Wiederherstellungs-Benachrichtigung und Internetprüfung sind **fest eingebaut** – hier ist nichts anzukreuzen: Nach der Reparatur prüft die App über genau diesen Adapter den tatsächlichen Internetzugang und meldet sich erst, wenn er wirklich funktioniert (mit Angabe der benötigten Sekunden). Ist die Schnittstelle zwar wieder da, aber ohne Internetzugang, erscheint `⚠︎`, bei einem Fehlschlag `✕` – nur im Symbol, ohne aufdringliche Meldungen.

Ein Beispiel – bei der Unterbrechung die Netzwerkeinstellungen öffnen, nach der Wiederherstellung den Proxy neu starten und einen Hinweiston abspielen:

```sh
PRE_CMD='open "x-apple.systempreferences:com.apple.Network-Settings.extension"'
POST_CMD='launchctl kickstart -k gui/$(id -u)/com.user.gost-lte\nafplay /System/Library/Sounds/Glass.aiff'
```

In der Konfigurationsdatei werden Zeilenumbrüche als `\n` und einfache Anführungszeichen als `\'` geschrieben (die App übernimmt das Escaping automatisch; beim Bearbeiten von Hand bitte dieselbe Form verwenden).

## Funktionsweise

```
Aufwachen des Systems (IORegisterForSystemPower + NSWorkspace, doppelt abgesichert)
      ↓  sofort PRE_CMD ausführen (z. B. Netzwerkeinstellungen öffnen); 1 s warten, bis USB Strom hat
USBDeviceReEnumerate      → falls kein USB: Dienstneustart per networksetup
      ↓  keine Vorprüfung – wer dieses Werkzeug installiert, hat ohnehin einen Adapter, der sich aufhängt
jede Sekunde prüfen: wiederhergestellt erst, wenn das Gateway auf ping antwortet (eine bloß vorhandene IP kann ping nicht täuschen)
      ↓  wiederhergestellt
POST_CMD ausführen → Internetzugang über genau diesen Adapter messen → Meldung nur bei echtem Erfolg (mit Zeitangabe)
      ↓
das Symbol erzählt die ganze Geschichte: Kreisel = Reparatur läuft, ✓8s = fertig, ⚠︎ = ohne Internetzugang, ✕ = fehlgeschlagen
```

Mehrere Adapter werden unabhängig voneinander und parallel repariert. Die Abkühlzeit von 15 Sekunden dient allein dazu, die doppelt eintreffenden Aufwachsignale der beiden Beobachter abzufangen.

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
