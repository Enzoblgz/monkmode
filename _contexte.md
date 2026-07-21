---
created: 2026-07-21
updated: 2026-07-21
---
# _contexte — FocusLock

**Casquette parente** : [[businessman]] (build) · proche de [[LifeOS]] (verrou de focus, mais LifeOS = Android)
**Statut** : v1 fonctionnelle (2026-07-21)
**Type** : app Mac native Swift, menu bar

## Objectif
App de productivité extrême sur Mac : pendant une session, tout est bloqué sauf apps +
sites autorisés. Inspiration Cold Turkey Micromanager.

## État v1
- Blocage apps (ferme les apps GUI non whitelistées) ✓
- Blocage sites (proxy local filtrant HTTPS/HTTP + proxy système) ✓ testé (allow→200, reste→403)
- Sessions minutées 25/50/90 + mode hardcore ✓
- Config JSON dans `~/.focuslock/config.json`
- Build via `bash build.sh` → `FocusLock.app`

## Prochaines étapes possibles
- Interface de config graphique (au lieu du JSON)
- Lancement au démarrage (LaunchAgent)
- Programmation d'horaires de blocage récurrents
- Durcir le mode hardcore (LaunchDaemon root)
- Icône dédiée

## Décisions techniques
- Command Line Tools seul (pas de Xcode) → SwiftPM + bundle .app assemblé à la main
- Enforcer ne tue que les apps `.regular` → ne casse pas macOS
- Proxy filtre sur la 1re ligne (absolute-form) → pas de MITM, pas de certif à installer
- Restauration proxy garantie via atexit + signaux + backup fichier
