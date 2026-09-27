# Pose

Un guide de pose semi-transparent par-dessus la caméra de l'iPhone.
Tu charges une photo de référence, elle s'affiche en calque translucide, tu t'alignes, tu déclenches.

**Tout reste sur le téléphone.** Aucun serveur, aucun compte, aucune requête réseau après l'installation.
Les poses sont stockées dans IndexedDB, les photos partent directement dans Photos via la feuille de partage iOS.

---

## Mettre en ligne (une seule fois, ~5 min)

Il faut un compte GitHub. L'hébergement est gratuit et le HTTPS est obligatoire pour accéder à la caméra.

1. Créer un dépôt vide sur https://github.com/new — nom : `pose`, visibilité au choix.
2. Dans ce dossier :

```bash
git init -b main && git add -A && git commit -m "Pose: PWA guide de pose" && git remote add origin https://github.com/TON_PSEUDO/pose.git && git push -u origin main
```

3. Sur GitHub : **Settings → Pages → Source → GitHub Actions**.
4. L'onglet **Actions** publie le site. L'URL apparaît dans Settings → Pages :
   `https://TON_PSEUDO.github.io/pose/`

Chaque `git push` redéploie automatiquement.

## Installer sur l'iPhone

1. Ouvrir l'URL **dans Safari** (pas Chrome : seul Safari donne la caméra à une app installée).
2. Bouton Partager → **Sur l'écran d'accueil**.
3. Lancer depuis l'icône, autoriser la caméra.

Une fois installée, elle fonctionne **hors-ligne** (service worker). Utile en Chine.
Elle n'expire jamais : pas de certificat, pas de re-signature.

## Utilisation

| Élément | Rôle |
|---|---|
| `+` | ajouter des poses de référence depuis la photothèque |
| vignettes | changer de pose — **appui long** pour supprimer |
| glisser / pincer | déplacer, redimensionner, faire pivoter le guide |
| double-tap | recentrer le guide |
| curseur *Guide* | opacité du calque |
| `#` | grille des tiers |
| `◑` | mode **contours** — ne garde que les lignes de la référence, sans son fond |
| `⇄` | miroir du guide (pose inversée) |
| `👁` | masquer l'interface |
| `0s` | retardateur 0 / 3 / 10 s, avec bip |
| `⟳` | caméra avant / arrière |

La photo enregistrée ne contient **ni le guide ni l'interface**, et est recadrée exactement comme à l'écran.

## Limites (assumées)

- Résolution ≈ 8 Mpx max : le web n'accède pas au capteur 48 Mpx ni au HDR / mode Nuit.
  Largement au-dessus de ce qu'Instagram accepte (1080 px de large), suffisant pour un partage famille.
  Insuffisant pour du tirage grand format ou du recadrage agressif.
- Pas de déclenchement par les boutons de volume (impossible en web).

Pour lever ces deux limites, voir la section **App native** plus bas.

## Développement local

```bash
python -m http.server 5173 --directory web --bind 127.0.0.1
```

Puis http://localhost:5173 (localhost est un contexte sécurisé, la caméra marche).

Régénérer les icônes : `node tools/make-icons.mjs`

---

# App native

`ios/` contient la version native : capteur pleine résolution, HEIC, choix d'objectif,
déclenchement par les boutons de volume.

Elle se compile sur un runner macOS GitHub Actions — **aucun Mac requis** — et se signe
sur le PC avec un Apple ID gratuit. Aucun certificat ne transite par GitHub : le CI
produit une IPA non signée.

Procédure complète : [ios/README.md](ios/README.md).

Les deux versions cohabitent. La PWA n'expire jamais et sert de filet si un
certificat 7 jours arrive à échéance au mauvais moment.
