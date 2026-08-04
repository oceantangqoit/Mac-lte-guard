# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>Votre adaptateur réseau USB ne répond plus après la veille écran fermé ? Il se répare tout seul au réveil — fini le débranchement/rebranchement.</b><br>
  <sub>Gardien d'adaptateur réseau USB dans la barre des menus · Swift natif · sans dépendances · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.de.md">Deutsch</a> · <b>Français</b> · <a href="README.es.md">Español</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.rw.md">Ikinyarwanda</a>
</p>

---

## Le problème

Beaucoup de clés LTE USB et d'adaptateurs Ethernet USB se « figent » après une mise en veille écran fermé : la LED reste allumée, l'interface est toujours présente dans le système, mais plus rien ne passe. **Il faut impérativement débrancher puis rebrancher** pour rétablir la connexion.

En cause : pendant la veille, macOS ne coupe pas l'alimentation USB (le VBUS est géré directement par le firmware SMC et ne peut pas être coupé de façon logicielle), alors que la session USB côté périphérique est déjà perdue. Redémarrer le service réseau ne sert donc à rien : c'est la couche USB qu'il faut réinitialiser.

## À qui cela s'adresse

Dès lors qu'un Mac accède à Internet via un **adaptateur réseau USB externe**, le problème peut survenir :

- 🚁 **Transmission vidéo de drone convertie en LTE** — par exemple la transmission DJI de première génération transformée en liaison cellulaire, avec une clé 4G/5G branchée sur le Mac en veille active pendant des heures
- 📡 **Clés LTE / 4G / 5G USB, routeurs mobiles, modules cellulaires USB** — interventions en extérieur, embarqué en véhicule ou à bord, salons, bureaux temporaires
- 🔌 **Adaptateurs USB-C / Thunderbolt vers Ethernet** — le Mac n'a pas de port réseau, et le câble est branché en salle de réunion, en salle serveur ou chez le client
- 🧩 **Ports réseau intégrés aux stations d'accueil** — Belkin, Plugable, Anker, CalDigit, etc.
- 🎥 **Diffusion en direct, streaming RTMP et exploitation à distance** qui exigent un débit montant stable
- 🖥 **Routeurs logiciels / Raspberry Pi / équipements industriels** reliés directement au Mac par adaptateur réseau USB pour le débogage

Le point commun : on ferme l'écran une fois, et au retour la connexion est perdue. La LED reste allumée, et **seul un débranchement/rebranchement rétablit la situation**.

### Pas seulement les adaptateurs réseau

Ce même phénomène — « figé après le réveil, seul le débranchement physique répare » — est très répandu sur d'autres périphériques USB. La [communauté officielle Apple](https://discussions.apple.com/thread/7745583), [MacRumors](https://forums.macrumors.com/threads/mac-mini-m1-usb-ports-not-working-after-wake-from-sleep.2326616/) et la [base de connaissances Plugable](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos) en recensent d'innombrables cas : interfaces audio, webcams, disques externes, lecteurs de cartes et divers composants des stations d'accueil sont tous concernés.

Le mécanisme sous-jacent étant identique, le menu de cet outil propose l'entrée **« Réinitialiser un périphérique USB »** : il liste tous les périphériques USB connectés ; il suffit d'en choisir un pour lui appliquer un débranchement logiciel, sans avoir à tendre la main vers le câble. En dehors des adaptateurs réseau, le déclenchement reste manuel (la détection automatique ne couvre que le réseau, car « ça passe ou ça ne passe pas » est un critère net, alors qu'il est très difficile de déterminer automatiquement si une webcam ou une interface audio est figée).

> ⚠️ Avant d'utiliser cette fonction sur un périphérique de stockage tel qu'un disque externe, arrêtez les lectures/écritures et éjectez le volume, sous peine de corrompre vos données.

## Vous arrivez d'un moteur de recherche ?

Les formulations ci-dessous sont celles réellement employées sur les forums francophones. Si vous cherchez à cause de l'une d'entre elles, cet outil a été écrit exactement pour cela.

### Comment on en parle sur les forums francophones

> plus de réseau après la veille · l'adaptateur Ethernet USB ne fonctionne plus au réveil · il faut débrancher et rebrancher l'adaptateur · « débrancher/brancher et ça repart » · le voyant est allumé mais pas d'Internet · le lien est vert dans les Réglages Réseau mais plus d'Internet · l'interface est là mais le ping ne passe pas · le voyant ne s'allume pas et l'adaptateur n'apparaît pas dans la liste des préférences réseau · éjection intempestive du disque externe en sortie de veille · disque dur externe éjecté quand le Mac est en veille · le dock USB-C n'est plus reconnu après la fermeture du capot · les ports USB-C ne répondent plus au réveil · clé LTE déconnectée après fermeture de l'écran · adaptateur multiport non reconnu · il faut redémarrer le Mac pour récupérer le réseau

### Titres de discussions réels

Relevés tels quels sur les forums de MacGeneration, la Communauté Apple francophone, MacBidouille et Le Journal du Lapin :

> `Adaptateur USB/Ethernet ne fonctionne plus avec Sierra` · `Problème adaptateur USB-C Ethernet 2.5G` · `Adaptateur USB-C vers Ethernet + recharge (qui pose souci)` · `Problème de connexion USB 10/100/1000 LAN` · `Déconnexion ports USB C intempestive MacBook Pro 2017` · `Les ports USB-C ne fonctionnent plus` · `USB C capricieux sur Mac M1` · `Disque dur externe éjecté quand le Mac est en veille` · `HDDs externes qui s'éjectent lors de leur mise en veille` · `problème de mise en veille DDs externes` · `Problème éjection intempestive disque dur externe` · `Disque externe éjecté après mise en veille du Mac` · `Disque dur externe s'éjecte tout seul du Mac` · `Notification à propos du disque dur en sortie de veille Mac` · `Ejection intempestive de mon disque externe sur mon macbook pro` · `Adaptateur multiports non reconnu sur Mac` · `Mon Mac ne détecte pas mon adaptateur` · `La veille, les adaptateurs USB-C vers Ethernet et macOS`

Trois passages qui résument tout, cités mot pour mot :

> « **La seule solution : Débrancher/brancher ... et ça repart.** »
> — [Problème adaptateur USB-C Ethernet 2.5G](https://forums.macg.co/threads/probleme-adaptateur-usb-c-ethernet-2-5g.1375193/), forums MacGeneration (adaptateur 2,5 Gbit/s à puce Realtek derrière un dock CalDigit TS3)

> « Tout fonctionne durant un certain temps quand tout à coup, plus rien. **J'ai toujours le lien en vert dans la préférence système mais plus internet** »
> — même discussion

> « la mise en veille d'un Mac coupe la connexion », et pour récupérer l'Ethernet il faut « **soit débrancher l'adaptateur, soit redémarrer le Mac** »
> — [La veille, les adaptateurs USB-C vers Ethernet et macOS](https://www.journaldulapin.com/2018/02/17/la-veille-les-adaptateurs-usb-c-vers-ethernet-et-macos/), Le Journal du Lapin (puce Realtek 8153)

### Combinaisons de recherche courantes

En français :

> `adaptateur USB Ethernet ne fonctionne plus après la veille mac` · `macbook plus de réseau après mise en veille` · `débrancher rebrancher adaptateur ethernet mac` · `dock USB-C non reconnu après veille mac` · `disque dur externe éjecté mise en veille mac` · `ports USB ne fonctionnent plus au réveil macbook` · `éjection intempestive disque dur externe mac` · `adaptateur multiport non reconnu mac sortie de veille` · `clé 4G LTE déconnectée après veille mac` · `réinitialiser port USB macOS ligne de commande`

En anglais (l'outil s'applique de la même façon) :

> `usb ethernet adapter not working after sleep mac` · `macbook ethernet doesn't wake up after sleep` · `usb-c ethernet adapter stops working after lid close` · `mac dock ethernet not detected after wake` · `lte modem disconnects after macbook sleeps` · `have to unplug and replug ethernet adapter macos`

### Par type d'appareil

| Votre matériel | Description courante |
|---|---|
| Adaptateur Ethernet USB / USB-C | le voyant est allumé mais pas de réseau, « lien vert » dans les Réglages Réseau mais plus d'Internet, l'interface `en5` est toujours là mais le ping ne passe pas, il faut débrancher/rebrancher |
| Clé LTE / 4G / 5G, modem USB | déconnexion après la fermeture du capot, plus de données au réveil, il faut la retirer et la remettre pour que la connexion reparte |
| Dock / station d'accueil (Belkin, Plugable, Anker, CalDigit, OWC, Satechi) | au réveil, plus aucun périphérique du dock n'est reconnu, il faut débrancher le dock entier puis le rebrancher |
| Disque dur externe / SSD | non monté après la veille, message d'éjection incorrecte, « éjection intempestive », il ne réapparaît qu'après un rebranchement |
| Webcam / carte d'acquisition / interface audio | disparue de la liste des périphériques au réveil, introuvable dans le logiciel |
| Lecteur de cartes / dongle / clavier-souris | plus aucune réaction au réveil, un débranchement-rebranchement suffit à tout remettre en route |

### Puces les plus souvent citées

> ASIX `AX88179` / `AX88179A` · Realtek `RTL8153` (désignée « Realtek 8153 » par Le Journal du Lapin) · Realtek `RTL8156` en 2,5 Gbit/s · Quectel `EC25` · séries `CM3xx` · Intel `I225-V` (derrière un dock Thunderbolt)

### À quel point ce problème est-il répandu ?

Sur la communauté officielle Apple, MacRumors et la base de connaissances Plugable, les demandes d'aide de ce type s'étalent sur plusieurs années et concernent aussi bien les Mac Intel que les Mac Apple Silicon :

- [Ethernet USB-C adapter doesn't wake up after sleep](https://forums.macrumors.com/threads/ethernet-usb-c-adapter-doesnt-wake-up-after-sleep.2220969/) — MacRumors
- [Ethernet adapter doesn't want to wake up after sleep](https://discussions.apple.com/thread/8272273) — communauté officielle Apple
- [MacBook Air 2020 USB LAN issue after sleep](https://discussions.apple.com/thread/255925525) — communauté officielle Apple
- [Usb ethernet adapter is not working after sleep](https://discussions.apple.com/thread/7686532) · [Ethernet not waking after sleep](https://discussions.apple.com/thread/250166501) · [Ethernet reset/disconnect on wake-up](https://discussions.apple.com/thread/251074085) · [Ethernet disconnected after sleep](https://discussions.apple.com/thread/8425667)
- [Devices are not detected after waking from sleep on macOS](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos) — base de connaissances officielle Plugable

### Pourquoi les « solutions officielles » habituelles ne règlent rien

| Conseil fréquemment donné | Pourquoi il est inopérant ici |
|---|---|
| Réinitialiser le SMC / la NVRAM | Sur les modèles Apple Silicon, **la réinitialisation du SMC n'existe tout simplement pas** ; et même effectuée sur un Mac Intel, le problème réapparaît à la fermeture suivante — ce n'est pas de cette maladie-là qu'il s'agit |
| Désactiver « Réactiver pour l'accès au réseau » (Wake for network access) | Ce réglage concerne le réveil par le réseau pendant la veille, ce qui n'a rien à voir avec la perte de la session USB au réveil |
| Éteindre complètement et redémarrer / mettre à jour le système | Efficace mais absurde : faut-il redémarrer l'ordinateur après chaque fermeture d'écran ? |
| Débrancher le câble réseau plutôt que l'adaptateur | Recommandé à répétition sur les forums, sans effet dans les faits (l'auteur du fil d'origine, textuellement : « je l'ai essayé aussi, ça ne marche pas ») |
| **Débrancher l'adaptateur USB puis le rebrancher** | La seule méthode réellement fiable — **et c'est précisément ce que cet outil automatise de façon logicielle** |

## La solution

LTE Guard est un gardien qui réside dans la barre des menus : il écoute les événements de réveil du système et, dès le retour de veille, effectue **immédiatement** via IOKit un **débranchement logiciel (USBDeviceReEnumerate)** sur le périphérique USB ciblé, équivalent au geste manuel. Aucune vérification préalable du genre « faut-il réparer ? » : si vous avez installé cet outil, c'est que vous êtes victime du périphérique zombie, et vérifier ne ferait que perdre du temps. La récupération n'est comptée que lorsque **la passerelle répond réellement au ping**, généralement **en 8 secondes environ** — tout près de la limite physique d'un débranchement à la main.

- 🎯 **Indépendant de la marque** — les VID/PID sont détectés automatiquement une fois l'adaptateur sélectionné, aucune liste de périphériques n'est embarquée
- 🖇 **Protège plusieurs adaptateurs à la fois** — cochez-en autant que vous voulez ; chacun est détecté et réparé indépendamment, en parallèle
- 🔌 **Fonctionne aussi hors USB** — bascule automatiquement sur le redémarrage du service réseau
- 🛠 **Hooks de commandes en deux phases** — un jeu de commandes s'exécute **dès la détection de la coupure** (par exemple ouvrir le panneau Réseau et suivre la réparation en direct), l'autre **après la récupération** (reconnexion d'un proxy, nouvelle numérotation, etc.)
- 🔔 **Notifications uniquement en cas de succès** — vous recevez exactement une notification, quand l'adaptateur est réparé *et* que l'accès à Internet est réellement vérifié (avec la durée) ; réparation en cours, absence d'Internet et échec ne s'expriment que sur l'icône de la barre des menus (rotation / `✓8s` / `⚠︎` / `✕`)
- 🌍 **Multilingue** — des dialectes chinois aux langues minoritaires ; interface et journaux entièrement localisés ; suit automatiquement la langue du système, et se change aussi manuellement depuis le menu
- 🪶 **Zéro dépendance** — une seule application, aucun démon à installer, pas besoin de Homebrew, aucune élévation de privilèges requise

## Installation

**Recommandé — installez une fois en ligne de commande, puis laissez-le se mettre à jour tout seul**

```bash
curl -L -o /tmp/LTEGuard.pkg https://github.com/oceantangqoit/Mac-lte-guard/releases/latest/download/LTEGuard.pkg && open /tmp/LTEGuard.pkg
```

Cette adresse pointe toujours vers la dernière version (chaque publication inclut une copie sans numéro de version).

**Pourquoi éviter le navigateur ?** Ce projet n'est ni signé ni notarié (cela demanderait un compte développeur Apple à 99 $ par an). Les fichiers téléchargés par un navigateur portent l'attribut `com.apple.quarantine` : au double-clic, macOS annonce qu'il « ne peut pas vérifier l'absence de logiciel malveillant » et il faut passer par clic droit → Ouvrir, ou l'autoriser dans les Réglages. `curl` ne pose pas cet attribut — **cela ne contourne aucun contrôle de sécurité, cela évite simplement que le navigateur colle l'étiquette.** Par prudence, vérifiez l'empreinte SHA-256, ou compilez vous-même ci-dessous.

**Après cette installation, vous n'y pensez plus.** Ouvrez **Mise à jour…** dans le menu, cochez **Mise à jour silencieuse** et choisissez un intervalle ; le programme cherchera, téléchargera et installera tout seul, puis redémarrera, sans vous déranger. Il télécharge également avec `curl`, l'avertissement ne revient donc jamais.

**Si vous préférez cliquer** : prenez `LTEGuard-x.y.z.pkg` (double-clic, configure le lancement au démarrage) ou `.dmg` (à glisser dans « Applications ») depuis les [Releases](../../releases). Au premier lancement, si macOS dit ne pas pouvoir vérifier le développeur : **clic droit sur l'app → Ouvrir → Ouvrir**, ou :

```bash
xattr -dr com.apple.quarantine /Applications/LTEGuard.app
```

**Option 3 — compiler soi-même** (nécessite les outils en ligne de commande Xcode)

```bash
git clone https://github.com/oceantangqoit/Mac-lte-guard.git
cd Mac-lte-guard && ./build.sh
```

Le résultat se trouve dans `dist/`. Le rendu de l'icône nécessite `brew install librsvg` ; sans cette bibliothèque la compilation aboutit quand même (l'app utilise alors l'icône par défaut).

## Première utilisation

Au premier lancement après l'installation, un assistant vous guide : **explication → sélection de l'adaptateur à surveiller → question sur le lancement au démarrage**. Il suffit de suivre les étapes.

En cas de souci, commencez par **Lancer le diagnostic** dans le menu : il vérifie chaque point et vous indique directement la marche à suivre.

| Point vérifié | Signification et remède en cas de problème |
|---|---|
| Emplacement d'installation | Si `/Volumes/…` s'affiche, vous exécutez l'app directement depuis le DMG — glissez-la d'abord dans Applications |
| Attribut de quarantaine (Gatekeeper) | Marquage normal pour une app non signée. Si elle ne s'ouvre pas : **clic droit sur l'app → Ouvrir → Ouvrir**, ou `xattr -dr com.apple.quarantine /Applications/LTEGuard.app` |
| Outil de réparation | Indique si usbreset est disponible ; il est normalement installé avec l'app, aucune installation séparée n'est nécessaire |
| Cible surveillée | Un adaptateur a-t-il été sélectionné, et l'interface existe-t-elle réellement (un changement d'adaptateur déclenche un avertissement) |
| Lancement au démarrage | Si l'option est désactivée, l'app ne se lance pas après un redémarrage ; elle s'active en un clic depuis le menu |

**À propos des autorisations** : cet outil **ne demande aucune élévation de privilèges** — ni accessibilité, ni accès au disque, ni root, et il n'installe aucun démon en arrière-plan.

## Utilisation

1. Une icône de signal apparaît dans la barre des menus après le lancement
2. Ouvrez le menu → **Choisir la cible à soigner…** → cochez votre adaptateur — **plusieurs sélections possibles** (les entrées marquées `· USB` acceptent le débranchement logiciel)
3. C'est tout. Ensuite, à chaque fermeture puis réouverture de l'écran, une coupure est réparée automatiquement

Les autres entrées du menu :

| Entrée | Rôle |
|---|---|
| Vérifier et réparer maintenant | Déclenche une exécution manuelle |
| Afficher le journal | Ouvre `~/Library/Application Support/LTE Guard/lte-guard.log` |
| Lancement au démarrage | Interrupteur modifiable à tout moment (disponible aussi après une installation par DMG) |
| Lancer le diagnostic | Auto-vérification point par point avec les remèdes correspondants |
| Commande après récupération… | Hooks en deux phases : « à la détection de la coupure » (par exemple ouvrir le panneau Réseau pour suivre la réparation) et « après la récupération » (par exemple reconnecter un proxy) — une commande par ligne, exécutées dans l'ordre, avec en plus des choix courants à cocher |
| Réinitialiser un périphérique USB | Liste tous les périphériques USB, débranchement logiciel en un clic — également valable pour les interfaces audio, webcams, disques et stations d'accueil |
| Icône de la barre des menus | Toujours afficher / afficher seulement en cas d'anomalie / masquer (**une fois masquée, rouvrez l'app depuis Applications pour la retrouver**) |
| Ouvrir le dossier de configuration | Ouvre en un clic la configuration, le journal et le dossier des langues dans le Finder |
| Langue | Changement de langue ; le sous-menu permet de modifier la langue courante ou d'ouvrir le dossier des langues |

## Langues écrites de droite à gauche (RTL)

Quatre langues écrites de droite à gauche sont incluses : **العربية** (arabe), **עברית** (hébreu), **فارسی** (persan) et **اردو** (ourdou).

Comme le changement de langue de cet outil est implémenté au sein de l'application elle-même (lecture de `lang/*.ini`) et ne passe pas par le mécanisme de localisation `.lproj` de macOS, le système ne met pas l'interface en miroir automatiquement. Deux niveaux de traitement ont donc été prévus :

1. **Mise en miroir de l'interface** — lors du passage à une langue RTL, le menu et les sous-menus sont réglés sur `.rightToLeft` : texte aligné à droite, icônes déplacées à droite, flèches de sous-menu inversées ;
2. **Isolation du texte bidirectionnel** — les valeurs insérées dans les textes (nom d'interface `en2`, `2c7c:0125`, noms de services, etc.) sont composées de lettres latines et de chiffres. Intégrées telles quelles dans une phrase arabe, elles sont réordonnées par l'algorithme bidirectionnel Unicode et **les deux-points et les parenthèses se retrouvent du mauvais côté**. Chaque substitution d'espace réservé est donc encadrée par `U+2068 FSI` / `U+2069 PDI` (pratique recommandée par le W3C en i18n), afin que chaque valeur insérée forme une unité directionnelle indépendante.
3. Le champ de saisie « Commande après récupération » est forcé à l'alignement à gauche : une commande shell est toujours en caractères latins, et l'alignement à droite la rendrait moins lisible.

## Multilingue

De nombreuses langues sont incluses ; la langue du système est choisie automatiquement au démarrage, et le menu « Langue » permet de changer manuellement (le choix est mémorisé).

Les langues ajoutées ultérieurement ont été traduites avec l'aide de l'IA et n'ont pas encore été relues par des locuteurs natifs ; une mention figure en tête de fichier. **Si une formulation vous semble maladroite, n'hésitez pas à corriger une ligne et à proposer une pull request** — c'est la façon la plus simple de contribuer.

**Modifier la formulation d'une langue existante** : le menu « Langue → Modifier la langue actuelle… » **copie le fichier ini de la langue courante depuis l'app vers votre dossier de langues et l'ouvre directement**. Redémarrez l'app pour appliquer vos modifications. Cette copie est prioritaire sur la version intégrée et **ne sera pas écrasée lors d'une mise à jour de l'app**.

À l'export, un message s'affiche et une opération est effectuée : **le nom et les coordonnées de l'auteur d'origine sont supprimés et remplacés par le vôtre**. Autrement dit, dès l'instant de l'export, cette copie devient votre propre fichier : vous en assumez le contenu, qui n'engage en rien l'auteur d'origine — n'y écrivez rien d'illégal, d'offensant ou qui porte atteinte aux droits d'autrui. Le fichier reste uniquement sur votre ordinateur et n'est jamais envoyé automatiquement.

**Ajouter une nouvelle langue** : menu « Langue → Ouvrir le dossier des langues… » (les deux modèles `zhs.template.ini` en chinois simplifié et `en.template.ini` en anglais y sont déposés automatiquement). Copiez l'un d'eux, renommez-le avec le code de la langue cible (par exemple `nl.ini`) et traduisez la partie située à droite du signe égal.

L'ordre de recherche des fichiers de langue est le suivant : **votre dossier de langues → fichiers intégrés à l'app** ; à nom identique, votre version l'emporte. N'hésitez pas à proposer vos fichiers en pull request, afin que tous les utilisateurs de la même langue en profitent.

**Format des fichiers de langue** : un fichier INI par langue, placé dans le répertoire `lang/`, avec des codes numériques comme clés :

```ini
[meta]
name=Français
author=……

[strings]
1=LTE Guard
2=Surveillance : {0}  {1}
3=● Normal
```

`{0}` et `{1}` sont des espaces réservés remplis par le programme.

## Fichier de configuration

`~/Library/Application Support/LTE Guard/lte-guard.conf` (maintenu automatiquement par l'app, modifiable à la main ; les anciennes configurations à cible unique sont mises à niveau automatiquement) :

```sh
# une cible à soigner par ligne, champs séparés par des tabulations : interface, nom du service, USB_VID, USB_PID
TARGETS='en2	My LTE	2c7c	0125'
PRE_CMD=''             # exécuté dès la détection de la coupure (le réseau est alors indisponible — ne pas compter dessus)
POST_CMD=''            # exécuté après la récupération, par exemple pour redémarrer un proxy
```

**Les deux hooks acceptent plusieurs commandes** — une par ligne, exécutées dans l'ordre. `PRE_CMD` part **à l'instant même** de la détection : mettez-y l'ouverture du panneau Réseau et il apparaît juste à temps pour suivre toute la réparation.

La boîte de dialogue propose des cases à cocher en deux groupes — cocher écrit immédiatement dans la zone de texte correspondante, décocher l'en retire :

**Courantes** (toujours proposées)

- Ouvrir Réglages Système → Réseau (va dans la zone « à la coupure ») — regardez de vos propres yeux la connexion tombée revenir
- Jouer un son
- Envoyer une notification webhook (remplacez l'URL d'exemple par la vôtre ; pratique pour les machines sans surveillance)

La notification de récupération et la vérification d'Internet sont **intégrées** — rien à cocher : après la réparation, l'app teste l'accès à Internet à travers cet adaptateur précis, et ne notifie que s'il fonctionne réellement (avec le nombre de secondes écoulées). Interface active mais sans Internet : `⚠︎` ; échec : `✕` — sur l'icône uniquement, sans vous harceler.

Par exemple, ouvrir le panneau Réseau à la coupure, puis redémarrer un proxy et jouer un son après la récupération :

```sh
PRE_CMD='open "x-apple.systempreferences:com.apple.Network-Settings.extension"'
POST_CMD='launchctl kickstart -k gui/$(id -u)/com.user.gost-lte\nafplay /System/Library/Sounds/Glass.aiff'
```

Dans le fichier de configuration, les sauts de ligne s'écrivent `\n` et les apostrophes `\'` (l'app fait l'échappement automatiquement ; suivez la même forme si vous éditez à la main).

## Fonctionnement

```
Réveil du système (IORegisterForSystemPower + NSWorkspace, double sécurité)
      ↓  exécution immédiate de PRE_CMD (par exemple ouvrir le panneau Réseau) ; attente d'1 s que l'USB soit alimenté
USBDeviceReEnumerate      → si ce n'est pas de l'USB : redémarrage du service via networksetup
      ↓  aucune vérification préalable — si vous avez installé cet outil, vous êtes victime du périphérique zombie
scrutation chaque seconde : récupéré seulement quand la passerelle répond au ping (une IP zombie ne trompe pas le ping)
      ↓  récupéré
Exécution de POST_CMD → test d'Internet à travers cet adaptateur → notification seulement si ça marche vraiment (avec la durée)
      ↓
l'icône raconte tout : rotation = réparation en cours, ✓8s = terminé, ⚠︎ = pas d'Internet, ✕ = échec
```

Les adaptateurs multiples sont réparés indépendamment, en parallèle. Un délai de refroidissement de 15 secondes sert uniquement à absorber les signaux de réveil en double émis par les deux écouteurs.

## Compatibilité et état des tests

**Prérequis : macOS 10.15 Catalina ou ultérieur, binaire universel pour Intel et Apple Silicon** — tout Mac capable de faire tourner Catalina (modèles à partir de 2012) peut l'exécuter. Sous macOS 11 et antérieur, la barre de menus affiche une étiquette texte (LTE) au lieu de l'icône symbole, et le panneau réseau s'ouvre par l'ancien chemin des Préférences Système ; tout le reste est identique.

### Vérifié en conditions réelles

| Élément | Environnement |
|---|---|
| Modèle | MacBook (Apple Silicon, arm64) |
| Système | macOS 26 (Darwin 25.x) |
| Adaptateur | Quectel EC25 (VID `2c7c` / PID `0125`), présenté comme `enX` en mode ECM/NCM |
| Scénario | Veille écran fermé → au réveil l'interface est présente mais la passerelle est injoignable → après le débranchement logiciel, **récupération en 8 secondes environ**, reproductible plusieurs fois de suite |
| En complément | Le processus proxy lié à cet adaptateur est redémarré automatiquement après la récupération (`POST_CMD`) |

### Devrait fonctionner sur le principe, mais sans retour de terrain à ce jour

| Cas | Prévision et ajustements éventuels |
|---|---|
| **Mac Intel** | Sur certains modèles Intel, `USBDeviceReEnumerate` exige les droits root et le journal affiche `open failed … try sudo`. Remède : exécuter une fois avec `sudo` pour confirmer, ou basculer sur « redémarrer le service réseau » (il suffit de laisser `USB_VID` vide dans la configuration) |
| **macOS 13 / 14 / 15** | Les API utilisées (notifications d'alimentation IOKit, `USBDeviceReEnumerate`, `NSStatusItem.isVisible`) sont toutes des interfaces stables depuis la version 13 : fonctionnement attendu normal. En dessous de 13, l'app ne se lance pas (limite fixée dans Info.plist) |
| **Adaptateurs USB vers Ethernet** (AX88179, RTL8153, CM3xx, etc.) | Même principe, cela devrait fonctionner. Attention : sur certains adaptateurs, le nom de l'interface change après la réénumération (`en5`→`en6`) ; il suffit alors de refaire une fois « Choisir la cible à soigner » dans le menu |
| **Modules 4G à numérotation** (non ECM/NCM, en PPP/AT) | Après la réénumération, une nouvelle numérotation est nécessaire pour obtenir une IP, faute de quoi un échec est constaté au bout de 60 secondes d'attente. Remède : saisir votre commande de numérotation/reconnexion dans « Commande après récupération » |
| **Port réseau d'une station d'accueil** | Lorsque la réénumération porte sur le périphérique USB de toute la station, les autres appareils qui y sont reliés (disques externes, webcams) sont réinitialisés au passage. Si un disque en cours d'écriture est branché sur la station, préférez la méthode « redémarrer le service réseau » |
| **Périphériques composites** (adaptateur réseau + lecteur de cartes + port série réunis) | Idem : la réinitialisation affecte aussi les autres fonctions du même périphérique USB |
| **Partage de connexion USB d'un iPhone** | Il s'agit d'un périphérique NCM maison d'Apple, généralement rétabli par le système lui-même ; en cas de problème identique, cet outil s'applique tout aussi bien sur le principe |
| **Interfaces non USB : Wi-Fi, port Thunderbolt, etc.** | Bascule automatique sur « redémarrer le service réseau ». Cela résout les blocages logiciels, mais pas un gel au niveau du pilote |

Si votre appareil ne figure pas dans le tableau ci-dessus, **n'hésitez pas à ouvrir une Issue pour m'indiquer votre résultat** (modèle, `USB VID:PID`, extrait de `~/Library/Application Support/LTE Guard/lte-guard.log`), qu'il s'agisse d'un succès ou d'un échec — c'est le retour dont le projet a le plus besoin aujourd'hui.

## Pourquoi il n'y a pas de « maintenir la connexion pendant la veille »

Les premières versions comportaient cet interrupteur ; il a été retiré après avoir été jugé inopérant à l'usage. Les raisons méritent d'être écrites, pour éviter à d'autres de refaire le chemin :

- **`caffeinate -i -s` n'empêche pas la veille écran fermé.** `man caffeinate` indique explicitement que l'assertion `-s` *« is valid only when system is running on AC power »*, et ce qu'elle empêche, c'est la **veille par inactivité** ; **la veille écran fermé (Clamshell Sleep) suit un chemin de déclenchement indépendant**, que l'on soit branché sur secteur ou non (sauf si un écran externe fait passer le Mac en mode clamshell). Dans les journaux de test, caffeinate tournait en permanence et le système enregistrait quand même `Entering Sleep state due to 'Clamshell Sleep'`.
- **La seule chose qui l'empêche vraiment est `sudo pmset -a disablesleep 1`** (l'approche d'outils comme Amphetamine ou InsomniaX), mais cela exige une élévation en root ; et un écran fermé sans veille signifie un processeur qui continue de tourner — **un portable fermé qui ne dort pas au fond d'un sac chauffe réellement**.
- Après arbitrage : cet outil se concentre sur une seule chose, bien faite — « l'auto-réparation en 8 secondes au réveil » — et n'élargit pas la surface d'attaque pour un cas de figure marginal qui réclamerait une élévation de privilèges et comporterait un risque matériel.

**Vous avez réellement besoin de rester connecté écran fermé** (téléchargements en cours, diffusion sans surveillance, maintien de sessions distantes) ? Nous recommandons l'association avec [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) (gratuit, disponible sur l'App Store) : à lui d'empêcher la machine de dormir, à cet outil de réparer automatiquement en cas de coupure. Chacun son rôle.

## Limites connues

- **Couper réellement l'alimentation USB est impossible** — sur Apple Silicon, le VBUS est contrôlé par le firmware SMC et aucune API publique n'existe. Pour une coupure physique, il faut un hub USB externe prenant en charge le PPPS, associé à [uhubctl](https://github.com/mvp/uhubctl).
- Sur **Mac Intel**, `USBDeviceReEnumerate` réclame parfois les droits root ; le journal affiche alors `try sudo`.
- Les **clés à numérotation** (non ECM/NCM) peuvent nécessiter une nouvelle numérotation après la réénumération : complétez avec `POST_CMD`.
- L'app n'est pas notariée par Apple ; au premier lancement, il faut passer par clic droit → Ouvrir.

## Désinstallation

```bash
launchctl bootout gui/$(id -u)/com.oceantang.lteguard
rm -f ~/Library/LaunchAgents/com.oceantang.lteguard.plist
rm -rf /Applications/LTEGuard.app ~/Library/"Application Support"/"LTE Guard"
```

## Soutenir le projet

Si ce petit outil vous épargne les débranchements USB à répétition :

- ⭐ Mettez une étoile au dépôt, ou recommandez-le à ceux que le même problème embête
- 🐛 Ouvrez une Issue avec le modèle de votre appareil et vos journaux, pour aider à couvrir davantage d'adaptateurs
- 🌍 Contribuez une traduction ([CONTRIBUTING.md](CONTRIBUTING.md), quelques lignes d'INI suffisent)
- ☕ Offrez un café à l'auteur

Détails dans [Soutenir le projet](SPONSOR.md).

## Échanges et contact

- 💬 Questions d'utilisation et échanges d'idées : [Discussions](../../discussions)
- 🐛 Bugs et suggestions de fonctionnalités : [Issues](../../issues)

### À propos de l'auteur

**Tang Haiyang (Ocean Tang)**, avocat inscrit au cabinet Beijing Dongyuan (Shenzhen), entré dans la profession en 2011 et en exercice depuis 2012.

- **Domaines d'intervention** : contentieux commercial et arbitrage, défense pénale et représentation des victimes en matière pénale, litiges du travail, conseil juridique permanent aux entreprises, due diligence
- **Expérience** : plus de 500 dossiers contentieux et non contentieux traités, conseil juridique permanent de plusieurs organisations

**Pourquoi un avocat écrit-il une application ?** J'ai passé le CCNA dès 2002 et le CIW Security Analyst en 2003, avant d'être diplômé de l'Université de technologie de Wuhan en 2005. J'ai toujours écrit mes propres outils de gestion de dossiers en VBA + Excel (suivi des affaires, génération de documents types, extraction OCR, envoi automatique d'e-mails). L'origine de cette application est tout aussi concrète : j'avais converti pour le plaisir la transmission vidéo DJI de première génération en liaison LTE afin de m'en servir comme clé 4G, et il me fallait débrancher puis rebrancher le module après chaque fermeture et réouverture de l'écran avant de retrouver Internet. Excédé, j'ai fini par écrire cette application avec Claude.

Que ce soit sur des sujets juridiques ou techniques, n'hésitez pas à passer par les [Discussions](../../discussions) ou à ouvrir une Issue.

## Licence

MIT License
