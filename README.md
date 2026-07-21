---
created: 2026-07-21
updated: 2026-07-21
---
# MonkMode

App Mac de productivité extrême. Pendant une session de focus, **tout est bloqué**
sauf les apps et les sites que tu as autorisés. Inspiré de Cold Turkey Micromanager.

## Ce que ça fait

- **Blocage des apps** : toute application (fenêtre dans le Dock) non autorisée est
  fermée automatiquement, en continu, tant que la session tourne. Les démons système
  ne sont jamais touchés.
- **Blocage des sites** : un proxy local ne laisse passer que les domaines de la
  whitelist. Tout le reste renvoie une page « bloqué ». Fonctionne pour HTTPS et HTTP.
- **Sessions minutées** : 25 / 50 / 90 min par défaut (configurable).
- **Mode hardcore** : si activé, impossible d'arrêter la session ni de quitter l'app
  avant la fin de la minuterie.
- **Menu bar uniquement** : pas d'icône Dock, un cadenas + le temps restant.

## Installation

```bash
bash build.sh      # compile et produit MonkMode.app
open MonkMode.app  # lance (icône cadenas dans la barre de menu)
```

Au premier lancement, la config par défaut est créée dans `~/.monkmode/config.json`.

## Configuration

`~/.monkmode/config.json` :

```json
{
  "allowedApps":    ["com.apple.Safari"],   // bundle IDs autorisés
  "allowedDomains": ["wikipedia.org"],       // domaines autorisés (sous-domaines inclus)
  "presets":        [25, 50, 90],            // durées du menu (minutes)
  "hardcore":       false                     // true = impossible d'arrêter avant la fin
}
```

Trouver le bundle ID d'une app :
```bash
osascript -e 'id of app "Anki"'
```

Menu → **Modifier la configuration…** ouvre ce fichier, puis **Recharger la configuration**.

## Fonctionnement du blocage sites

Pendant une session, le proxy système pointe vers `127.0.0.1:9797`. Le navigateur passe
donc par MonkMode, qui n'autorise que les domaines whitelistés. À la fin (ou à l'arrêt),
l'état réseau initial est restauré — même après un crash (sauvegarde dans
`~/.monkmode/proxy_backup.json`, rejouée au démarrage suivant).

> La bascule du proxy système peut demander le mot de passe admin une fois par session.

## Limites connues (v1)

- Le blocage sites suppose que l'app autorisée respecte le proxy système (les navigateurs
  le font). Combine-le avec le blocage d'apps pour un vrai verrou.
- Le mode hardcore reste contournable par quelqu'un de déterminé (kill du process en root).
  L'objectif est de mettre assez de friction pour casser l'automatisme, pas d'être inviolable.

## Architecture

| Fichier | Rôle |
|---|---|
| `main.swift` | App menu bar + gestion de session |
| `AppEnforcer.swift` | Ferme les apps non autorisées |
| `SiteProxy.swift` | Proxy HTTP/HTTPS filtrant (Network.framework) |
| `ProxySettings.swift` | Active/restaure le proxy système (`networksetup`) |
| `Config.swift` | Lecture de `~/.monkmode/config.json` |
