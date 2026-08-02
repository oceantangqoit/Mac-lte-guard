# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>Votre adaptateur réseau USB ne répond plus après la veille du Mac ? Il se répare tout seul au réveil.</b><br>
  <sub>Gardien d'adaptateur réseau USB dans la barre des menus · Swift natif · sans dépendances · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.ru.md">Русский</a> · <a href="README.rw.md">Ikinyarwanda</a>
</p>

---

## Le problème

Beaucoup de clés LTE USB et d'adaptateurs Ethernet USB se « figent » après une mise en veille écran fermé : la LED reste allumée, l'interface est toujours présente dans le système, mais plus rien ne passe. **Seul un débranchement/rebranchement physique rétablit la connexion.**

En cause : macOS ne coupe pas l'alimentation USB pendant la veille (le VBUS est géré directement par le firmware SMC, sans API publique), alors que la session USB côté périphérique est déjà morte. Redémarrer le service réseau ne sert à rien — c'est la couche USB qu'il faut réinitialiser.

## Vous arrivez d'un moteur de recherche ?

Ces formulations désignent toutes le même problème :

> adaptateur ethernet USB ne fonctionne plus après veille Mac · MacBook perte réseau après mise en veille · adaptateur USB-C ethernet ne se réveille pas · port réseau du dock non détecté après veille · clé 4G déconnectée après veille macOS

Les forums officiels d'Apple et MacRumors accumulent depuis des années des signalements identiques, sur Mac Intel comme Apple Silicon. Les conseils habituels (réinitialisation SMC/NVRAM) n'existent même plus sur Apple Silicon et ne traitent pas la cause. **Seul le débranchement fonctionne — c'est exactement ce que cet outil automatise.**

## La solution

LTE Guard réside dans la barre des menus et écoute les événements de réveil. Au réveil, il teste l'adaptateur choisi : si la passerelle ne répond pas, il effectue via IOKit un **débranchement logiciel (USBDeviceReEnumerate)**, équivalent au geste physique. La connexion revient **en 8 secondes environ**.

- 🎯 **Indépendant de la marque** — VID/PID détectés automatiquement, aucune liste de périphériques
- 🔌 **Fonctionne aussi hors USB** — bascule automatiquement sur le redémarrage du service réseau
- 🛠 **Commande après récupération** — redémarrer un proxy, relancer une connexion…
- 🌍 **62 langues** — suit la langue du système, modifiable depuis le menu
- 🪶 **Zéro dépendance** — une seule app, aucun démon, pas de Homebrew

## Installation

Téléchargez le `.dmg` depuis les [Releases](../../releases) et glissez-le dans Applications.

Si macOS indique que le développeur ne peut pas être vérifié (normal pour une app non signée) : **clic droit sur l'app → Ouvrir → Ouvrir**, ou dans le Terminal :

```bash
xattr -dr com.apple.quarantine /Applications/LTEGuard.app
```

## Utilisation

1. Une icône apparaît dans la barre des menus
2. Menu → **Choisir la cible…** → sélectionnez votre adaptateur (ceux marqués `· USB` acceptent le replug logiciel)
3. C'est tout : après chaque fermeture d'écran, la réparation est automatique

En cas de souci, utilisez **Lancer le diagnostic** dans le menu.

---

## À propos de l'auteur

**Ocean Tang (唐海洋)** — avocat à Shenzhen, en Chine (dans la profession depuis 2011, inscrit depuis 2012). Contentieux commercial et arbitrage, défense pénale, droit du travail, conseil juridique permanent ; plus de 500 dossiers traités.

CCNA en 2002, CIW Security Analyst en 2003, et des années à écrire ses propres outils de gestion de dossiers en VBA + Excel. Cette application a une origine tout aussi concrète : il a converti un émetteur vidéo DJI de première génération en liaison LTE pour s'en servir comme modem 4G — et devait débrancher puis rebrancher la clé après chaque fermeture d'écran avant que le réseau ne revienne. Excédé, il l'a écrite avec Claude.

Documentation complète (matrice de compatibilité, fichier de configuration, contribuer une traduction) : [English README](README.en.md).

## License

MIT License
