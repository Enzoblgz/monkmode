---
created: 2026-07-21
updated: 2026-07-21
---
# _contexte — MonkMode

**Casquette parente** : [[businessman]] (build) · proche de [[LifeOS]] (verrou de focus, mais LifeOS = Android)
**Statut** : v1 fonctionnelle (2026-07-21)
**Type** : app Mac native Swift, menu bar

## Objectif
App de productivité extrême sur Mac : pendant une session, tout est bloqué sauf apps +
sites autorisés. Inspiration Cold Turkey Micromanager.

## État v1
- Blocage apps : **masque** (hide) les apps GUI non whitelistées au lieu de les fermer, + impose la vidéo plein écran (une fois par app) ✓ (2026-07-21)
- Blocage sites (proxy local filtrant HTTPS/HTTP + proxy système) ✓ testé (allow→200, reste→403)
- Sessions minutées 25/50/90 + mode hardcore ✓
- Config JSON dans `~/.monkmode/config.json`
- Build via `bash build.sh` → `MonkMode.app`

## Prochaines étapes possibles
- Interface de config graphique (au lieu du JSON)
- Lancement au démarrage (LaunchAgent)
- Programmation d'horaires de blocage récurrents
- Durcir le mode hardcore (LaunchDaemon root)
- Icône dédiée

## Décisions techniques
- Command Line Tools seul (pas de Xcode) → SwiftPM + bundle .app assemblé à la main
- Enforcer agit seulement sur les apps `.regular` → ne casse pas macOS
- `hide()` (Cmd+H) plutôt que minimiser fenêtres : pas besoin de permission Accessibilité
- Vidéo fermée à la fin de session (sinon overlay `.screenSaver` reste bloqué → redémarrage)
- Fenêtre vidéo = `KeyableWindow` (borderless key-able) pour que l'Échap ferme
- build via `--scratch-path` local : `.build` sur Google Drive plante sqlite (build.db disk I/O)
- Proxy filtre sur la 1re ligne (absolute-form) → pas de MITM, pas de certif à installer
- Restauration proxy garantie via atexit + signaux + backup fichier
