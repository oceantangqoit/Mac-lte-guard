# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>Igikoresho cya USB kireka gukora nyuma y'uko Mac isinziriye? Kirisana ubwacyo iyo ikanguye — ntukeneye kongera gukuramo USB.</b><br>
  <sub>Umurinzi w'ibikoresho by'urusobe bya USB ku murongo w'ibikubiyemo · Swift · nta bindi bikenewe · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.ru.md">Русский</a> · <a href="README.rw.md">Ikinyarwanda</a>
</p>

---

## Ikibazo

Ibikoresho byinshi bya USB LTE n'ibya Ethernet bya USB «bihagarara» nyuma y'uko Mac isinziriye ifunze: itara riracyaka, igikoresho kiracyagaragara muri sisitemu, ariko nta murongo ukora. **Gukuramo no kongera gushyiramo ni cyo cyonyine kigikora.**

Impamvu: mu gihe cyo gusinzira, macOS ntabwo ihagarika amashanyarazi ya USB (VBUS iyoborwa na SMC, nta buryo bwo kuyihindura), ariko umubano wa USB ku ruhande rw'igikoresho waba wapfuye. Kongera gutangiza serivisi y'urusobe ntibikemura — igomba gusubizwa mu buryo bushya ni urwego rwa USB.

## Waje uvuye mu bushakashatsi?

Ibi byose bivuga ikintu kimwe:

> igikoresho cya USB Ethernet ntigikora nyuma yo gusinzira kuri Mac · MacBook itakaza urusobe nyuma yo gusinzira · igikoresho cya USB-C ntigikanguka · modemu ya LTE ihagarara nyuma yo gusinzira

Kuri fora za Apple na MacRumors, raporo nk'izi zimaze imyaka myinshi — ku bikoresho bya Intel n'ibya Apple Silicon. Inama zisanzwe (gusubiza SMC/NVRAM) ntaho ziri kuri Apple Silicon kandi ntizikemura impamvu. **Icyonyine gikora ni ugukuramo no kongera gushyiramo igikoresho — ni cyo iyi porogaramu ikora yonyine.**

## Igisubizo

LTE Guard iba ku murongo w'ibikubiyemo kandi itega amatwi igihe sisitemu ikanguka. Nyuma yo gukanguka isuzuma igikoresho: niba gateway itasubiza, ikoresha IOKit gukora **gukuramo no gushyiramo bya porogaramu (USBDeviceReEnumerate)** — bingana no gukuramo intoki. Umurongo usanzwe ugaruka **mu masegonda 8**.

- 🎯 **Ntibireba ubwoko** — VID/PID bimenyekana igihe uhitamo, nta rutonde rw'ibikoresho rwabitswe
- 🔌 **Bikora no ku bitari USB** — bihita bikoresha kongera gutangiza serivisi y'urusobe
- 🛠 **Itegeko nyuma yo gusana** — urugero, kongera gutangiza proxy
- 🌍 **Indimi 53** — bikurikira ururimi rwa sisitemu, ushobora no guhindura mu bikubiyemo
- 🪶 **Nta bindi bikenewe** — porogaramu imwe gusa, nta serivisi z'inyuma, nta Homebrew

## Kwinjiza

Kuramo `.dmg` uhereye kuri [Releases](../../releases) hanyuma uyishyire muri Applications.

Niba macOS ivuga ko idashobora kugenzura uwayikoze (bisanzwe ku maporogaramu adafite umukono): **kanda iburyo kuri porogaramu → Fungura → Fungura**, cyangwa muri Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/LTEGuard.app
```

## Uko bikoreshwa

1. Ikimenyetso kigaragara ku murongo w'ibikubiyemo
2. Ibikubiyemo → **Hitamo igikoresho…** → hitamo igikoresho cyawe (ibifite `· USB` bishyigikira gukuramo bya porogaramu)
3. Byarangiye. Ubutaha iyo ufunze ugafungura, bisanwa byonyine

Igihe hari ikibazo, hitamo **Koresha isuzuma** mu bikubiyemo.

---

Inyandiko zuzuye (urutonde rw'ibikoresho bishyigikiwe, dosiye y'igenamiterere, uko watanga ubusemuzi): [English README](README.en.md).

## License

MIT License
