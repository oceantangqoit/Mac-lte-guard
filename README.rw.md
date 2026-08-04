# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>Igikoresho cy'urusobe cya USB gicika iyo Mac isinziriye ifunze? Kirisana ubwacyo iyo ikanguye — ntukeneye kongera kugikuramo no kugishyiramo.</b><br>
  <sub>Umurinzi w'ibikoresho by'urusobe bya USB uguma ku murongo w'ibikubiyemo · Swift · nta bindi bikenewe · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <b>Ikinyarwanda</b>
</p>

---

## Ikibazo

Ibikoresho byinshi bya USB LTE n'ibikoresho bya Ethernet bya USB «bihagarara» nyuma y'uko Mac isinziriye ifunze: itara riracyaka, n'igikoresho kiracyagaragara muri sisitemu, ariko nta murongo ukora — **ugomba kugikuramo ukongera kukishyiramo** kugira ngo bigaruke.

Impamvu: mu gihe cyo gusinzira, macOS ntihagarika amashanyarazi ya USB (VBUS iyoborwa na firmware ya SMC ubwayo, nta buryo bwa porogaramu bwo kuyizimya), nyamara umubano wa USB ku ruhande rw'igikoresho waba warangiye. Kongera gutangiza serivisi y'urusobe ntibikemura, kuko igomba gusubizwamo bushya ni urwego rwa USB.

## Ninde ubikeneye

Umuntu wese uhuza Mac n'urusobe akoresheje **igikoresho cy'urusobe cya USB cyo hanze** ashobora guhura n'iki kibazo:

- 🚁 **Kohereza amashusho ya drone ukoresheje LTE** — nka DJI y'igisekuru cya mbere yahinduwe ngo ikoreshe umurongo wa telefone, Mac ifite modem ya 4G/5G ishinzwe amasaha menshi
- 📡 **Modem za USB LTE / 4G / 5G, WiFi zitwarwa, n'ibice bya cellular bya USB** — akazi ko hanze, mu modoka, ku mato, mu imurikagurisha, mu biro by'agateganyo
- 🔌 **Ibikoresho bihindura USB-C / Thunderbolt bikagira Ethernet** — Mac ntifite umwenge w'urusobe, ugomba guhuza insinga mu cyumba cy'inama, mu cyumba cya serveri, cyangwa kwa kiriya usanzwe ukorera
- 🧩 **Umwenge w'urusobe uri muri dock** — Belkin, Plugable, Anker, UGREEN, CalDigit n'ibindi
- 🎥 **Kunyuza amashusho ku buryo butaziguye, RTMP streaming, no gucunga sisitemu kure**, ibisaba umurongo wo kohereza uhamye
- 🖥 **Router za porogaramu / Raspberry Pi / ibikoresho by'inganda** bihujwe na Mac binyuze ku gikoresho cya USB kugira ngo bisuzumwe

Icyo bihuriyeho: ufunga rimwe gusa, iyo ugarutse umurongo waracitse, itara riracyaka, **kandi icyonyine gikora ni ugukuramo no kongera gushyiramo**.

### Si ibikoresho by'urusobe gusa

Iki kibazo cyo «guhagarara nyuma yo gukanguka, bigakemurwa gusa no gukuramo intoki» kigaragara no ku bindi bikoresho bya USB — [urubuga rwa Apple](https://discussions.apple.com/thread/7745583), [MacRumors](https://forums.macrumors.com/threads/mac-mini-m1-usb-ports-not-working-after-wake-from-sleep.2326616/), na [Plugable knowledge base](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos) byanditse ibyabaye byinshi: ibikoresho by'amajwi, kamera, disiki zo hanze, abasoma amakarita, n'ibice byose biri kuri dock.

Kubera ko uburyo bw'imikorere ari bumwe, ibikubiyemo by'iyi porogaramu bifite **«Gusubiza mu buryo bushya igikoresho cya USB»**: bigaragaza ibikoresho bya USB byose bihari, uhitamo kimwe maze ukagikoraho gukuramo no gushyiramo bya porogaramu, utagombye kugera ku nsinga. Ibikoresho bitari iby'urusobe kugeza ubu bisaba gutangizwa n'intoki (kwimenyekanisha ubwabyo bireba urusobe gusa, kuko «uraho cyangwa ntuhari» bifite ikigereranyo gisobanutse, mu gihe bigoye kumenya ku buryo bwikora ko kamera cyangwa igikoresho cy'amajwi cyahagaze).

> ⚠️ Mbere yo kubikoresha ku bikoresho bibika amakuru nka disiki zo hanze, banza uhagarike gusoma no kwandika hanyuma ubisohore neza, bitaba ibyo wakwangiza amakuru.

## Niba waje uvuye mu bushakashatsi

Aya magambo yose asobanura ikintu kimwe, kandi iyi porogaramu yanditswe kubera cyo:

> Mac imaze gusinzira insinga ya Ethernet ntikora · umurongo ucika iyo ufunze MacBook · igikoresho cya USB kigomba gukurwamo kikongera kugishyirwamo · adaptateur USB-C vers Ethernet ne marche plus après la veille · umwenge wa Ethernet uri kuri dock ntumenyekana nyuma yo gukanguka · modem ya LTE icika iyo Mac isinziriye · itara riracyaka ariko nta internet · igikoresho kiragaragara ariko ping ntinyura

Amagambo asanzwe ashakishwa mu Cyongereza (iyi porogaramu na yo irabikemura):

> `usb ethernet adapter not working after sleep mac` · `macbook ethernet doesn't wake up after sleep` · `usb-c ethernet adapter stops working after lid close` · `mac dock ethernet not detected after wake` · `lte modem disconnects after macbook sleeps` · `have to unplug and replug ethernet adapter macos`

### Imitwe nyayo y'ibibazo ku mbuga

Tubivuge tutiziganya: gushakisha iki kibazo mu Kinyarwanda ntibitanga ibisubizo — impaka za tekiniki mu Rwanda zikorwa cyane cyane mu Cyongereza cyangwa mu Gifaransa. Imitwe ikurikira yakuwe uko iri kuri Apple Support Communities na MacRumors, ni yo ifite akamaro mu gushakisha:

> `Ethernet USB-C adapter doesn't wake up after sleep` · `Usb ethernet adapter is not working after sleep` · `USB devices aren't working after waking from sleep` · `USB A ports no power after wake up` · `Mac Mini M1 — USB Ports not working after wake from sleep` · `Devices are not detected after waking from sleep or after rebooting on macOS` · `After updating to macOS Tahoe external USB devices disconnect after sleep` · `AX 88179a Ethernet Adapter not recognized`

Mu Gifaransa (gikoreshwa kenshi mu karere):

> `adaptateur USB-C vers Ethernet ne marche plus après la veille` · `disque dur externe non reconnu après veille Mac` · `dock USB-C non reconnu après veille`

### Ukurikije ubwoko bw'igikoresho

| Igikoresho cyawe | Uko abantu bakibisobanura |
|---|---|
| Igikoresho cya USB / umugozi w'urusobe | Itara riraka ariko nta murongo, byerekana «ntibihujwe», `en5` iracyahari ariko ping ntinyura |
| Modem ya LTE / 4G / 5G, cyangwa mudasobwa ya WiFi | Icika iyo ufunze ikanuye, nta murongo nyuma yo gukanguka, isaba gukurwamo no gushyirwamo |
| Dock (Belkin, Plugable, Anker, CalDigit, OWC) | Nta na kimwe cyometse kuri dock cyemerwa nyuma yo gukanguka |
| Disiki yo hanze / SSD | Ntiyihagararaho nyuma yo gusinzira, hagaragara «Disiki ntiyakuwemo neza» |
| Kamera / ikarita yo gufata amashusho / igikoresho cy'amajwi | Bibura ku rutonde rw'ibikoresho nyuma yo gukanguka |
| Isomero rya karita / dongle / klavier n'imbeba | Ntibisubiza nyuma yo gukanguka, gukuramo no gushyiramo rimwe birabikemura |

### Ibyuma bivugwa cyane muri izo mpaka

> ASIX `AX88179` / `AX88179A` · Realtek `RTL8153` · `RTL8156` 2.5G · Quectel `EC25` · urukurikirane `CM3xx` · Intel `I225-V` (inyuma ya dock za Thunderbolt)

### Iki kibazo gikunze kugaragara kangahe

Ku rubuga rwa Apple, kuri MacRumors, no muri knowledge base ya Plugable, ibibazo nk'ibi bimaze imyaka myinshi kandi bireba ibikoresho bya Intel n'ibya Apple Silicon:

- [Ethernet USB-C adapter doesn't wake up after sleep](https://forums.macrumors.com/threads/ethernet-usb-c-adapter-doesnt-wake-up-after-sleep.2220969/) — MacRumors
- [Ethernet adapter doesn't want to wake up after sleep](https://discussions.apple.com/thread/8272273) — urubuga rwemewe rwa Apple
- [MacBook Air 2020 USB LAN issue after sleep](https://discussions.apple.com/thread/255925525) — urubuga rwemewe rwa Apple
- [Usb ethernet adapter is not working after sleep](https://discussions.apple.com/thread/7686532) · [Ethernet not waking after sleep](https://discussions.apple.com/thread/250166501) · [Ethernet reset/disconnect on wake-up](https://discussions.apple.com/thread/251074085) · [Ethernet disconnected after sleep](https://discussions.apple.com/thread/8425667)
- [Devices are not detected after waking from sleep on macOS](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos) — knowledge base yemewe ya Plugable

### Impamvu inama «zemewe» zisanzwe zidakemura

| Icyo abantu bakunze kugusaba | Impamvu kidakora muri iki kibazo |
|---|---|
| Gusubiza SMC / NVRAM | Ku bikoresho bya Apple Silicon **nta gusubiza SMC na busa kubaho**; ndetse n'iyo ubikoze kuri Intel, ubutaha ufunze igifuniko ikibazo kirongera — si cyo kirwara |
| Guhagarika «Wake for network access» | Iyo switch igenga «gukangurwa n'urusobe mu gihe cyo gusinzira», bitandukanye rwose no gucika kw'umubano wa USB nyuma yo gukanguka |
| Kuzimya burundu no kongera gufungura / kuvugurura sisitemu | Birakora ariko ntibyumvikana — ese buri gihe ufunze igifuniko wongere utangize mudasobwa? |
| Gukuramo insinga ya Ethernet aho gukuramo igikoresho | Ku mbuga bitangwa kenshi nk'inama, ariko mu bugeragezwa ntibikora (nyir'ubutumwa bwa mbere yaravuze: «nabigerageje na byo, ntibikora») |
| **Gukuramo igikoresho cya USB no kongera kukishyiramo** | Ni cyo cyonyine gikora buri gihe — **kandi ni cyo iyi porogaramu ikora yonyine mu buryo bwa porogaramu** |

## Igisubizo

LTE Guard ni umurinzi uguma ku murongo w'ibikubiyemo, utega amatwi ibyabaye byo gukanguka kwa sisitemu. Iyo sisitemu ikangutse, **ako kanya** ukoresha IOKit ugakorera igikoresho cya USB cyagenwe **gukuramo no gushyiramo bya porogaramu** (`USBDeviceReEnumerate`) — bingana no kugikuramo ukongera ukagishyiramo n'intoki. Nta suzuma ribanza ryo kubaza ngo «ese hakenewe gusana?»: uwashyizeho iyi porogaramu aba ari umuhohotewe w'igikoresho cyapfuye gihagaze, kandi gusuzuma ni ukwononera igihe gusa. Gusanwa kubarwa gusa iyo **ping igeze kuri gateway koko**, ubusanzwe **mu masegonda 8 hafi** — hafi y'urugero ntarengwa rwo gukuramo no gushyiramo n'intoki.

- 🎯 **Ntibireba ubwoko** — iyo uhisemo igikoresho, VID/PID bimenyekana byonyine, nta rutonde rw'ibikoresho rwabitswe imbere
- 🖇 **Irinda ibikoresho byinshi icyarimwe** — hitamo ibyo ushaka byose; buri kimwe gisuzumwa kandi gisanwa ukwacyo, byose icyarimwe
- 🔌 **Bikora no ku bikoresho bitari USB** — bihita bikoresha kongera gutangiza serivisi y'urusobe
- 🛠 **Amategeko y'ibyiciro bibiri** — amwe akorwa **ako kanya umurongo ucitse** (urugero gufungura urupapuro rw'urusobe ukareba uko gusana bigenda), andi **nyuma yo gusanwa** (kongera guhuza proxy, kongera guhamagara, n'ibindi)
- 🔔 **Ubutumwa buza gusa iyo byagenze neza** — ubona ubutumwa bumwe gusa, iyo igikoresho cyagarutse **kandi** byemejwe ko interineti ikora koko (hamwe n'igihe byatwaye); gusana bikirimo, kutagira interineti no kunanirwa bigaragazwa gusa ku kimenyetso cyo ku murongo w'ibikubiyemo (akaziga kazenguruka / `✓8s` / `⚠︎` / `✕`)
- 🌍 **Indimi nyinshi** — kuva ku mvugo z'Abashinwa kugeza ku ndimi z'imiryango mito; imigaragarire na log byahinduwe; bikurikira ururimi rwa sisitemu ku buryo bwikora, ushobora no guhitamo mu bikubiyemo
- 🪶 **Nta bindi bikenewe** — porogaramu imwe gusa: nta serivisi z'inyuma zishyirwaho, nta Homebrew, kandi nta burenganzira bwisumbuye na buke bukenewe

## Kwinjiza

**Birasabwa — shyiraho rimwe ukoresheje umurongo w'amabwiriza, hanyuma ureke yivugurure ubwayo**

```bash
curl -L -o /tmp/LTEGuard.pkg https://github.com/oceantangqoit/Mac-lte-guard/releases/latest/download/LTEGuard.pkg && open /tmp/LTEGuard.pkg
```

Iyi aderesi buri gihe yerekeza kuri verisiyo nshya (buri isohorwa rifite kopi idafite nomero ya verisiyo).

**Kuki tutayikuye muri mushakisha?** Uyu mushinga ntabwo washyizweho umukono cyangwa ngo wemezwe na Apple (byasaba konti y'umuhanzi ya $99 ku mwaka). Amadosiye akuwe na mushakisha aherekezwa n'ikimenyetso `com.apple.quarantine`, bityo iyo ukanze kabiri macOS ikavuga ko «idashobora kugenzura niba irimo porogaramu mbi», ugasabwa kuyifungura ukoresheje kanda iburyo cyangwa kuyemerera mu igenamiterere. `curl` we ntashyiraho icyo kimenyetso — **ibi si ugusimbuka igenzura ry'umutekano, ni ukudatuma mushakisha yomeka ako kamenyetso gusa.** Niba ushaka kwitonda, banza ugenzure SHA-256, cyangwa uyubake wenyine nk'uko bivugwa hepfo.

**Nyuma yo gushyiraho kariya karundi kamwe, ntukibyibuke.** Fungura **Ivugurura…** mu bikubiyemo, ushyire akamenyetso kuri **Ivugurura ryihishe** hanyuma uhitemo igihe; guhera ubwo porogaramu izagenzura, ikure, kandi ishyireho yonyine, hanyuma yongere itangire, itakubangamiye. Ikuramo na yo ikoresha `curl`, bityo iburira ntirizongera kugaragara.

**Niba uhitamo gukanda**: fata `LTEGuard-x.y.z.pkg` (kanda kabiri; ishyiraho gutangira ku ifungura) cyangwa `.dmg` (uyikurure ujye muri «Porogaramu») kuri [Releases](../../releases). Ku itangira rya mbere, iyo macOS ivuze ko idashobora kugenzura uwayikoze: **kanda iburyo kuri porogaramu → Fungura → Fungura**, cyangwa:

```bash
xattr -dr com.apple.quarantine /Applications/LTEGuard.app
```

**Uburyo bwa 3 — kuyubaka wenyine** (bisaba ibikoresho by'umurongo w'amabwiriza bya Xcode)

```bash
git clone https://github.com/oceantangqoit/Mac-lte-guard.git
cd Mac-lte-guard && ./build.sh
```

Ibisohoka biba muri `dist/`. Gukora ikimenyetso bisaba `brew install librsvg`, ariko no mu gihe kitashyizweho kubaka birakora (porogaramu igakoresha ikimenyetso gisanzwe).

## Ikoreshwa rya mbere

Nyuma yo kwinjiza, igihe ufunguye bwa mbere hazaza ubuyobozi: **ibisobanuro → guhitamo igikoresho cyo kurindwa → kubaza niba ushaka gutangira igihe mudasobwa itangiye**; ukurikira gusa ukanda.

Iyo hari ikibazo, banza ukande **Koresha isuzuma** mu bikubiyemo; risuzuma buri kintu kimwe kimwe kandi rikakubwira icyo ukora:

| Icyo isuzuma rireba | Icyo bivuze n'icyo ukora iyo hari ikibazo |
|---|---|
| Aho porogaramu yashyizwe | Niba yerekana `/Volumes/…`, bivuze ko uyikoresha uyikuye muri DMG — banza ukurure porogaramu uyishyire muri «Applications» |
| Ikimenyetso cy'ubwigunge (Gatekeeper) | Ni ibisanzwe ku maporogaramu adafite umukono. Niba itafunguka: **kanda iburyo → Fungura → Fungura**, cyangwa `xattr -dr com.apple.quarantine /Applications/LTEGuard.app` |
| Igikoresho cyo gusana | Niba usbreset ihari; ubusanzwe ishyirwaho hamwe na porogaramu, ntugomba kuyishyiraho ukwayo |
| Icyo urinda | Niba warahisemo igikoresho, kandi niba icyo gikoresho kiriho koko (iyo uhinduye igikoresho urabimenyeshwa) |
| Gutangira igihe mudasobwa itangiye | Iyo bidakora, nyuma yo kongera gutangiza mudasobwa porogaramu ntizitangira; ushobora kubifungura mu bikubiyemo |

**Ku bijyanye n'uburenganzira**: iyi porogaramu **ntikeneye uburenganzira bwisumbuye na buke** — nta Accessibility, nta Full Disk Access, nta root, kandi nta serivisi y'inyuma ishyirwaho.

## Uko bikoreshwa

1. Iyo yatangiye, ikimenyetso cy'ikimenyetso cy'urusobe kigaragara ku murongo w'ibikubiyemo
2. Fungura ibikubiyemo → **Hitamo igikoresho cyo gusanwa…** → hitamo igikoresho cyawe — **ushobora guhitamo byinshi** (ibifite ikimenyetso `· USB` bishobora gukurwamo no gushyirwamo mu buryo bwa porogaramu)
3. Byarangiye. Ubutaha ufunze igifuniko, isinziriye, ukongera ugafungura, niba umurongo waciye ugarurwa wenyine

Ibindi biri mu bikubiyemo:

| Ikintu | Icyo gikora |
|---|---|
| Suzuma usane ubu | Gutangiza rimwe n'intoki |
| Reba log | Ifungura `~/Library/Application Support/LTE Guard/lte-guard.log` |
| Gutangira igihe mudasobwa itangiye | Switch, ushobora kuyihindura igihe icyo ari cyo cyose (n'abinjije bakoresheje DMG barabikoresha) |
| Koresha isuzuma | Kwisuzuma buri kintu kimwe kimwe no gutanga igisubizo |
| Itegeko rikorwa nyuma yo gusanwa… | Amategeko y'ibyiciro bibiri: «iyo umurongo ucitse» (urugero gufungura urupapuro rw'urusobe ukareba uko gusana bigenda) na «nyuma yo gusanwa» (urugero kongera guhuza proxy) — itegeko rimwe kuri buri murongo, akorwa akurikirana; hari n'akunze gukoreshwa wihitiramo ukanda gusa |
| Gusubiza mu buryo bushya igikoresho cya USB | Bigaragaza ibikoresho bya USB byose, ugakuramo ugashyiramo mu buryo bwa porogaramu ukanda rimwe — birakora no ku bikoresho by'amajwi, kamera, disiki, na dock |
| Ikimenyetso ku murongo w'ibikubiyemo | Kigaragara buri gihe / kigaragara gusa iyo hari ikibazo / gihishwe (**iyo wagihishe, ongera ufungure porogaramu uyikuye muri «Applications» kugira ngo ugarure**) |
| Fungura ububiko bw'igenamiterere | Gufungura muri Finder ubu bwose: igenamiterere, log, n'indimi |
| Ururimi | Guhindura ururimi; muri sous-menu ushobora guhindura ururimi rukoreshwa cyangwa gufungura ububiko bw'indimi |

## Indimi zandikwa uhereye iburyo (RTL)

Muri porogaramu harimo indimi 4 zandikwa uhereye iburyo ujya ibumoso: **العربية** (Icyarabu), **עברית** (Igiheburayo), **فارسی** (Igiperesi), **اردو** (Urdu).

Kubera ko guhindura ururimi muri iyi porogaramu byakozwe imbere muri yo ubwayo (isoma `lang/*.ini`), aho kunyura mu buryo bwa macOS bwa `.lproj`, sisitemu ntihindura icyerekezo cy'imigaragarire yonyine. Ni yo mpamvu hakozwe ibi bikurikira:

1. **Guhindura icyerekezo cy'imigaragarire** — iyo uhinduye ukajya mu rurimi rwa RTL, ibikubiyemo na sous-menus bishyirwa kuri `.rightToLeft`: inyandiko igana iburyo, ibimenyetso bikajya iburyo, n'utumenyetso twa sous-menu tukahinduka.
2. **Gutandukanya inyandiko z'icyerekezo kibiri** — ibyinjizwa mu magambo (izina ry'igikoresho `en2`, `2c7c:0125`, izina rya serivisi, n'ibindi) byose ni inyuguti z'ikilatini n'imibare; iyo bishyizwe mu nteruro y'Icyarabu bitagenzuwe, algorithm ya Unicode BiDi irabisubiramo, **maze utudomo n'udukubo tukajya ku ruhande rutari rwo**. Ni yo mpamvu ibyinjizwa byose bipfundikirwa muri `U+2068 FSI` / `U+2069 PDI` (uburyo bwemejwe na W3C i18n), kugira ngo buri kintu cyinjijwe kibe igice cy'icyerekezo cyigenga.
3. Ahandikirwa «Itegeko rikorwa nyuma yo gusanwa» hahatirwa kugana ibumoso — amategeko ya Shell buri gihe ni ay'ikilatini, kuyagana iburyo byabigora gusomeka.

## Indimi nyinshi

Muri porogaramu harimo indimi nyinshi; igihe itangiye ihitamo ubwayo ikurikije ururimi rwa sisitemu, kandi ushobora no guhindura mu bikubiyemo muri «Ururimi» (ihitamo ryawe ryibukwa).

Indimi zongeweho nyuma zahinduwe hifashishijwe AI kandi ntizirasuzumwa n'abazivukanamo; ibyo byanditse ku ntangiriro ya buri dosiye. **Niba ubonye imvugo idahwitse, ushobora guhindura umurongo umwe ugatanga PR** — ni bwo buryo bworoshye bwo gutanga umusanzu.

**Guhindura imvugo y'ururimi rusanzwe ruhari**: mu bikubiyemo «Ururimi → Hindura ururimi rukoreshwa…» **byimura dosiye ini y'urwo rurimi ivuye muri porogaramu ikayishyira mu bubiko bwawe bw'indimi hanyuma ikayifungura**; nyuma yo guhindura, ongera utangize porogaramu. Iyi kopi ifite agaciro karuta iyo mu porogaramu, kandi **no mu gihe uvuguruye porogaramu ntisimburwa**.

Igihe cyo kuyisohora hazabanza kugaragara ubutumwa, hanyuma hakorwe ikintu kimwe: **gukuraho izina ry'uwabikoze wa mbere n'aho kumugeraho, hakashyirwaho izina ryawe**. Bisobanuye ko uhereye igihe wayisohoreye iyi kopi iba ari dosiye yawe bwite, ibirimo bikaba ari wowe ubibazwa, kandi bitagifitanye isano n'uwabikoze wa mbere — ntukandike ibinyuranyije n'amategeko, ibitutsi, cyangwa ibihonyora uburenganzira bw'abandi. Dosiye ibikwa gusa kuri mudasobwa yawe, kandi ntiyoherezwa ahandi ku buryo bwikora.

**Kongeraho ururimi rushya**: mu bikubiyemo «Ururimi → Fungura ububiko bw'indimi…» (hashyirwamo byonyine `zhs.template.ini` y'Igishinwa cyoroshye na `en.template.ini` y'Icyongereza nk'ingero). Kopa imwe uyihindure izina ukurikije kode y'ururimi ugamije (urugero `nl.ini`), hanyuma uhindure ibiri iburyo bw'ikimenyetso cyo kungana gusa.

Uko dosiye z'indimi zishakishwa ni: **ububiko bwawe bw'indimi → ibiri muri porogaramu**; iyo hari izisa izina, iyawe ni yo ifite ijambo rya nyuma. Dosiye wanoze zohereze muri PR, kugira ngo abavuga urwo rurimi bose babyungukiremo.

**Imiterere ya dosiye y'ururimi**: ururimi rumwe rugira dosiye INI imwe, ishyirwa mu bubiko `lang/`, ikoresha imibare nk'urufunguzo:

```ini
[meta]
name=Ikinyarwanda
author=……

[strings]
1=LTE Guard
2=Kurinda: {0}  {1}
3=● Bisanzwe
```

`{0}` na `{1}` ni ibyimburo, byuzuzwa na porogaramu.

## Dosiye y'igenamiterere

`~/Library/Application Support/LTE Guard/lte-guard.conf` (porogaramu irayicunga yonyine, ariko ushobora no kuyihindura n'intoki; igenamiterere rya kera ry'igikoresho kimwe rivugururwa ryonyine):

```sh
# igikoresho kimwe cyo gusanwa kuri buri murongo, ibice bitandukanyijwe na tab: igikoresho, izina rya serivisi, USB_VID, USB_PID
TARGETS='en2	My LTE	2c7c	0125'
PRE_CMD=''             # rikorwa ako kanya umurongo ucitse (icyo gihe urusobe ntirukora — ntukarwishingikirizeho)
POST_CMD=''            # rikorwa nyuma yo gusanwa, urugero kongera gutangiza proxy
```

**Ibyo byiciro byombi byakira amategeko menshi** — itegeko rimwe kuri buri murongo, akorwa akurikirana. `PRE_CMD` ikorwa **ako kanya** umurongo ucitse: ushyizemo gufungura urupapuro rw'urusobe, rufunguka ku gihe nyacyo maze ukareba uko gusana byose bigenda kuva ku ntangiriro kugeza ku iherezo.

Akadirishya kakwereka uduce two gukandaho dusanzwe: iyo utoranyije kamwe, itegeko ryako rihita ryandikwa mu kazu k'inyandiko kabigenewe; iyo ukuyeho, rirasibwa:

**Ibikunze gukoreshwa** (bihari buri gihe)

- Gufungura Igenamiterere rya sisitemu → Urusobe (rijya mu kazu k'«iyo umurongo ucitse») — ukirebera n'amaso yawe uko umurongo waciye ugaruka
- Gucuranga ijwi
- Kohereza ubutumwa bwa Webhook (simbuza URL y'agateganyo iyawe; ni byiza kuri mudasobwa zidacungwa)

Ubutumwa bwo gusanwa n'isuzuma ry'interineti **byubatswe imbere** — nta na kimwe ugomba gutoranya: nyuma yo gusana, porogaramu igerageza interineti inyuze kuri icyo gikoresho nyacyo, ikakumenyesha gusa iyo ikora koko (hamwe n'amasegonda byatwaye). Iyo igikoresho cyagarutse ariko interineti idahari hagaragara `⚠︎`, iyo byananiranye hakagaragara `✕` — ku kimenyetso gusa, nta kubangamira.

Urugero: iyo umurongo ucitse hagafunguka urupapuro rw'urusobe, nyuma yo gusanwa hakongera gutangizwa proxy hagacurangwa ijwi:

```sh
PRE_CMD='open "x-apple.systempreferences:com.apple.Network-Settings.extension"'
POST_CMD='launchctl kickstart -k gui/$(id -u)/com.user.gost-lte\nafplay /System/Library/Sounds/Glass.aiff'
```

Muri dosiye y'igenamiterere, gucamo imirongo byandikwa nka `\n`, utwuguruzo tumwe tukandikwa nka `\'` (porogaramu ibikora yonyine; nawe ukurikize ubwo buryo iyo uhindura n'intoki).

## Uko bikora

```
Sisitemu irakanguka (IORegisterForSystemPower + NSWorkspace — inzira ebyiri z'umutekano)
      ↓  gukora PRE_CMD ako kanya (urugero gufungura urupapuro rw'urusobe); gutegereza isegonda 1 kugira ngo USB ibone umuriro
USBDeviceReEnumerate      → bitari USB: networksetup yongera gutangiza serivisi
      ↓  nta suzuma ribanza — uwashyizeho iyi porogaramu aba ari umuhohotewe w'igikoresho cyapfuye gihagaze
gusuzuma buri segonda: gusanwa kubarwa gusa iyo gateway isubije ping (IP y'ikinyoma ntishobora kubihimba)
      ↓  byasanwe
gukora POST_CMD → kugerageza interineti kuri icyo gikoresho → kumenyesha gusa iyo ikora koko (hamwe n'igihe byatwaye)
      ↓
ikimenyetso kivuga inkuru yose: akaziga kazenguruka = birimo gusanwa, ✓8s = byarangiye, ⚠︎ = nta interineti, ✕ = byananiranye
```

Ibikoresho byinshi bisanwa buri kimwe ukwacyo, byose icyarimwe. Ikiruhuko cy'amasegonda 15 kigamije gusa kumira ibimenyetso byo gukanguka bisubiranya biva ku bumva bubiri.

## Guhuza n'ibikoresho n'ibyagerageje

**Ibisabwa: macOS 10.15 Catalina cyangwa nshya kuyirusha, binary rusange (universal binary) ikorera kuri Intel na Apple Silicon** — Mac yose ishobora gukoresha Catalina (amoko yo kuva mu 2012) ishobora gukoresha iki gikoresho. Kuri macOS 11 n'iziyibanjirije, umurongo w'ibikubiyemo werekana inyandiko (LTE) mu mwanya w'ikimenyetso, kandi urupapuro rw'urusobe rufungurwa binyuze mu nzira ya kera ya System Preferences; ibindi byose ni kimwe.

### Byagerageje kandi birakora

| Ikintu | Aho byagerageje |
|---|---|
| Ubwoko bwa mudasobwa | MacBook (Apple Silicon, arm64) |
| Sisitemu | macOS 26 (Darwin 25.x) |
| Igikoresho cy'urusobe | Quectel EC25 (VID `2c7c` / PID `0125`), kigaragara nka `enX` mu buryo bwa ECM/NCM |
| Uko byagenze | Gufunga igifuniko isinzira → nyuma yo gukanguka igikoresho kirahari ariko gateway ntigerwaho → nyuma yo gukuramo no gushyiramo bya porogaramu **bigaruka mu masegonda 8 hafi**, kandi byisubiriyemo kenshi |
| Ikindi | Nyuma yo gusanwa, proxy ihujwe n'icyo gikoresho yongera gutangira yonyine (`POST_CMD`) |

### Bigomba gukora ukurikije uko bikora, ariko ntibirageragezwa

| Aho byakoreshwa | Icyo dutekereza n'ibyo wahindura |
|---|---|
| **Mac za Intel** | Kuri zimwe muri Intel, `USBDeviceReEnumerate` isaba root, muri log hakagaragara `open failed … try sudo`. Icyo ukora: gerageza rimwe ukoresheje `sudo`, cyangwa uhindukirire uburyo bwo «kongera gutangiza serivisi y'urusobe» (usige `USB_VID` ari ubusa mu igenamiterere) |
| **macOS 13 / 14 / 15** | API zikoreshwa (IOKit power notifications, `USBDeviceReEnumerate`, `NSStatusItem.isVisible`) zose zihamye guhera kuri 13, biteganyijwe ko bikora neza. Munsi ya 13 ntibikora (Info.plist irabibuza) |
| **Ibikoresho bihindura USB bikagira Ethernet** (AX88179, RTL8153, CM3xx n'ibindi) | Uburyo ni bumwe, bigomba gukora. Menya ko ku bikoresho bimwe izina ry'igikoresho rihinduka nyuma yo kongera kubarurwa (`en5`→`en6`); icyo gihe ongera «Hitamo igikoresho cyo gusanwa» mu bikubiyemo |
| **Module za 4G zihamagara** (zitari ECM/NCM, zikoresha PPP/AT) | Nyuma yo kongera kubarurwa hakenewe kongera guhamagara kugira ngo hazane IP, bitaba ibyo nyuma y'amasegonda 60 bifatwa nk'ibyanze. Icyo ukora: shyira itegeko ryo guhamagara/kongera guhuza muri «Itegeko rikorwa nyuma yo gusanwa» |
| **Igikoresho cy'urusobe kiri muri dock** | Iyo icyongera kubarurwa ari igikoresho cya USB cya dock yose, n'ibindi bikoresho biri kuri dock birasubizwamo bushya (disiki zo hanze, kamera). Niba kuri dock hari disiki iri gusomwa cyangwa kwandikwaho, ni byiza gukoresha uburyo bwo «kongera gutangiza serivisi y'urusobe» |
| **Ibikoresho bivanze** (igikoresho cy'urusobe + usoma amakarita + serial mu gikoresho kimwe) | Nk'uko byavuzwe haruguru: gusubizamo bushya bigira ingaruka ku bindi bikorwa by'icyo gikoresho cya USB kimwe |
| **Guhuza na internet ya iPhone binyuze kuri USB** | Ni igikoresho cya NCM cya Apple ubwayo, kandi ubusanzwe sisitemu ikigarura yonyine; niba wahuye n'ikibazo nk'iki, iyi porogaramu na yo yagifasha |
| **Wi-Fi, umwenge wa Thunderbolt, n'ibindi bitari USB** | Bihita bikoresha «kongera gutangiza serivisi y'urusobe». Bikemura guhagarara ku rwego rwa porogaramu, ariko ntibikemura guhagarara ku rwego rwa driver |

Niba igikoresho cyawe kitari muri uru rutonde, **fungura Issue umbwire ibyakubayeho** (ubwoko, `USB VID:PID`, agace ka `~/Library/Application Support/LTE Guard/lte-guard.log`), byaba byaragenze neza cyangwa nabi — ni ryo suzuma rikenewe cyane muri iki gihe.

## Impamvu tutakoze «kuguma ku murongo mu gihe cyo gusinzira»

Muri verisiyo za mbere iyi switch yarahari, ariko ubugeragezwa bwerekanye ko idakora none yaravanyweho. Impamvu zikwiye kwandikwa, kugira ngo abandi batazongera kubigwamo:

- **`caffeinate -i -s` ntibuza gusinzira biturutse ku gufunga igifuniko**. `man caffeinate` yandika neza ko `-s` *"is valid only when system is running on AC power"*, kandi ikaba ibuza **gusinzira bitewe no kudakora**; mu gihe **gusinzira biturutse ku gufunga igifuniko (Clamshell Sleep) ari inzira yigenga**, itabuzwa n'uko wacomeka amashanyarazi cyangwa utabikoze (keretse hari ecran yo hanze ituma mudasobwa ijya mu buryo bwa clamshell). Muri log z'ubugeragezwa, caffeinate yakoraga igihe cyose, nyamara sisitemu ikandika `Entering Sleep state due to 'Clamshell Sleep'`.
- **Icyonyine kibibuza ni `sudo pmset -a disablesleep 1`** (ni bwo buryo Amphetamine, InsomniaX n'izindi zikoresha), ariko bisaba uburenganzira bwa root; ikindi ni uko kudasinzira ufunze bivuze ko CPU ikomeza gukora — **mudasobwa igendanwa ufunze ukayishyira mu isakoshi itasinziriye irashyuha koko**.
- Nyuma yo gupima: iyi porogaramu yibanda ku kintu kimwe, ari cyo «kwisana mu masegonda 8 nyuma yo gukanguka», kandi ntitwifuza kwagura ahashobora guteranwa kubera ikintu gikenewe na bake gisaba uburenganzira bwisumbuye kandi gishobora kwangiza ibikoresho.

**Niba koko ukeneye ko ufunze umurongo ukomeza** (kuramo ibintu, gukurikirana streaming, kubungabunga umubano wa kure)? Nagira inama yo gukoresha [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) (ni ubuntu, iri kuri App Store) — yo yita ku kubuza mudasobwa gusinzira, iyi porogaramu yo yite ku kugarura umurongo niwaciika; buri yose ifite akazi kayo.

## Aho bigarukira bizwi

- **Guhagarika amashanyarazi ya USB by'ukuri ntibishoboka** — VBUS ya Apple Silicon iyoborwa na firmware ya SMC, nta API rusange ihari. Kugira ngo uhagarike amashanyarazi mu buryo bufatika, ugomba gukoresha hub ya USB yo hanze ishyigikiye PPPS ihujwe na [uhubctl](https://github.com/mvp/uhubctl).
- Kuri **Mac za Intel**, `USBDeviceReEnumerate` rimwe na rimwe isaba uburenganzira bwa root, muri log hakagaragara `try sudo`.
- **Modem zihamagara** (zitari ECM/NCM) zishobora gukenera kongera guhamagara nyuma yo kongera kubarurwa; koresha `POST_CMD` kugira ngo wuzuze icyo cyuho.
- Porogaramu ntiyanyujijwe muri Apple notarization, ku ncuro ya mbere ugomba gukanda iburyo → Fungura.

## Gukuraho

```bash
launchctl bootout gui/$(id -u)/com.oceantang.lteguard
rm -f ~/Library/LaunchAgents/com.oceantang.lteguard.plist
rm -rf /Applications/LTEGuard.app ~/Library/"Application Support"/"LTE Guard"
```

## Gushyigikira umushinga

Niba aka gakoresho kagabanyije umuruho wo gukuramo no gushyiramo USB buri gihe:

- ⭐ Shyira Star kuri repo, cyangwa ukayimenyesha abandi bafite iki kibazo
- 🐛 Fungura Issue utubwire ubwoko bw'igikoresho cyawe na log, bidufashe gukemura ibikoresho byinshi
- 🌍 Tanga ubusemuzi bw'ururimi rumwe ([CONTRIBUTING.md](CONTRIBUTING.md), guhindura imirongo mike muri INI birahagije)
- ☕ Gura uwabikoze ikawa

Reba byinshi kuri [Gushyigikira umushinga](SPONSOR.md).

## Kuganira no kutuvugisha

- 💬 Kuganira ku ikoreshwa no gusangira ibitekerezo: [Discussions](../../discussions)
- 🐛 Amakosa n'ibyifuzo ku bikorwa bishya: [Issues](../../issues)

### Ku birebana n'uwabikoze

**Tang Haiyang (Ocean Tang / 唐海洋)**, umunyamategeko ukorera muri Beijing Dongyuan (Shenzhen) Law Firm, yatangiye uyu mwuga mu 2011 kandi awukora ku mugaragaro guhera mu 2012 kugeza ubu.

- **Ibyo akora**: imanza n'ubukemurampaka mu bucuruzi, kwiregura mu manza nshinjabyaha no guhagararira abakorewe ibyaha, amakimbirane y'akazi, kuba umujyanama w'amategeko uhoraho w'ibigo, no gukora due diligence
- **Uburambe**: yakoze imanza n'imirimo itari iy'urukiko irenga 500, kandi ni umujyanama w'amategeko uhoraho w'ibigo bitandukanye

**Kuki umunyamategeko yandika porogaramu**: nabonye CCNA mu 2002 na CIW Security Analyst mu 2003, kandi narangije muri Wuhan University of Technology mu 2005. Mfite igihe kinini nyandika ibikoresho byanjye bwite byo gucunga imanza nkoresheje VBA + Excel (gukurikirana imanza, gukora inyandiko zisanzwe, gukuramo inyandiko na OCR, kohereza imeyili byonyine). Inkomoko y'iyi porogaramu na yo irasobanutse: nahinduye DJI y'igisekuru cya mbere ngo ikoreshe LTE nk'umukino, nkayikoresha nka modem ya 4G, ariko buri gihe nafunga nkongera gufungura byabaga ngombwa gukuramo no kongera gushyiramo kugira ngo internet igaruke. Byaranshavuje, ndetse mfatanya na Claude nandika iyi porogaramu.

Waba ushaka kuganira ku bijyanye n'amategeko cyangwa ku bya tekiniki, ukaze kuri [Discussions](../../discussions) cyangwa ufungure Issue.

## Uruhushya

MIT License
