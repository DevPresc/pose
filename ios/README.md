# Pose — app native iOS

Même app que la PWA, mais avec le vrai pipeline photo : capteur pleine résolution,
HEIC, HDR, choix d'objectif, et **déclenchement par les boutons de volume**.

Pas de Mac dans la boucle : le projet Xcode est généré et compilé par un runner
macOS GitHub Actions, la signature se fait sur le PC.

## Le principe

```
 PC Windows            GitHub Actions (macOS)        iPhone
 ───────────           ──────────────────────        ──────
 git push      ──────► xcodegen + xcodebuild
                       IPA NON SIGNÉE
               ◄────── artefact téléchargeable
 Sideloadly/AltStore
 signe avec ton
 Apple ID gratuit ────────────────────────────────►  installée
```

**Aucun certificat, aucun mot de passe Apple n'est envoyé à GitHub.** Le CI ne sait
pas signer et n'a pas à savoir : il produit un `.app` non signé, empaqueté en `.ipa`.
Tout ce qui touche à ton identité Apple reste sur ta machine.

## 1. Récupérer l'IPA

1. Onglet **Actions** du dépôt → workflow *Build IPA (non signée)*.
2. Ouvrir le dernier run vert → section **Artifacts** → télécharger `Pose-ipa`.
3. Dézipper : tu obtiens `Pose.ipa`.

Le build se relance à chaque push touchant `ios/`, ou à la main via *Run workflow*.

## 2. Préparer le PC (une fois)

Il faut les pilotes Apple, que seules les versions **téléchargées sur apple.com**
installent. Les versions du Microsoft Store ne fonctionnent pas.

1. Désinstaller iTunes s'il vient du Microsoft Store.
2. Installer **iTunes** depuis apple.com/itunes (version Windows 64 bits).
3. Installer **iCloud pour Windows** depuis apple.com (pas le Store).

## 3. Signer et installer

### AltStore Classic — recommandé

Son intérêt pour un mois de voyage : **il resigne l'app tout seul** par Wi-Fi tant
que le PC est allumé, sur le même réseau, avec AltServer lancé. Pas de câble à
ressortir tous les 7 jours.

1. Installer AltServer depuis altstore.io (édition **Classic**).
2. iPhone branché en USB, déverrouillé, « Se fier à cet ordinateur ».
3. Dans la barre système Windows : AltServer → *Install AltStore* → choisir l'iPhone → Apple ID.
4. Sur l'iPhone : **Réglages → Général → VPN et gestion de l'appareil** → faire confiance au profil développeur.
5. Ouvrir AltStore sur l'iPhone → onglet *My Apps* → **+** → choisir `Pose.ipa`.

Ensuite, garder AltServer lancé sur le PC et l'iPhone sur le même Wi-Fi :
le rafraîchissement est automatique.

### Sideloadly — plan B

Plus simple à installer, mais il faut rebrancher le câble tous les 7 jours.

1. Installer Sideloadly depuis sideloadly.io.
2. Brancher l'iPhone, glisser `Pose.ipa` dans la fenêtre, entrer l'Apple ID, *Start*.
3. Réglages → Général → VPN et gestion de l'appareil → faire confiance.

Réinstaller par-dessus conserve les poses enregistrées (même bundle ID, même compte).

## Contraintes du compte Apple gratuit

| Contrainte | Conséquence |
|---|---|
| Certificat valable **7 jours** | resigner chaque semaine, sinon l'app refuse de s'ouvrir |
| **3 apps** sideloadées max par appareil | largement suffisant ici |
| **10 App IDs par semaine** | ne pas changer `PRODUCT_BUNDLE_IDENTIFIER` en boucle |
| Pas de push, iCloud, App Groups | Pose n'en utilise aucun |

**Utilise un Apple ID secondaire.** Sideloadly et AltServer ont besoin du mot de
passe du compte : autant que ce ne soit pas celui qui garde tes sauvegardes et tes
paiements. Un Apple ID gratuit suffit, il n'a pas besoin d'être sur l'iPhone.

Si le bundle `com.leorinaldi.pose` entre en conflit, change-le dans `project.yml`
(clé `PRODUCT_BUNDLE_IDENTIFIER`) — ou directement dans Sideloadly au moment d'installer.

## Choix d'implémentation

- **Formats 4:5 / 3:4 / 1:1 / 9:16, aperçu en `resizeAspectFill`.** La photo est recadrée
  au centre avec le même rapport : ce qui est cadré est ce qui est gardé. En 3:4 (capteur
  entier), le fichier d'origine est conservé intact, HDR compris ; les autres formats sont
  ré-encodés en HEIC avec leurs métadonnées. Portrait verrouillé.
- **Pellicule interne** (`Documents/shots`) : les photos survivent à la fermeture de l'app,
  « Tout enregistrer » les écrit directement dans Photos (droit *ajout seulement*).
  Option « Enregistrer direct dans Photos » dans le menu `…`.
- **Pack de 8 poses** dessinées en `Shape` vectoriel, mêmes squelettes que la PWA.
- **Retardateur + rafale** combinables, anneau de décompte, second appui = annuler.
- **Niveau** via CoreMotion, avec un retour haptique quand l'horizon est droit.
- **Caméra virtuelle** (`builtInTripleCamera` si dispo) plutôt que trois objectifs
  séparés : le passage 0,5× / 1× / 2× / 5× se fait par simple facteur de zoom, et iOS
  gère la bascule optique.
- **`maxPhotoDimensions` lu sur le format actif** une fois la session démarrée :
  c'est ce qui débloque la pleine résolution du capteur.
- **Mode contours** en Core Image (`CIEdges` → `CIMaskToAlpha`) : le calque ne garde
  que les lignes de la référence. Une photo opaque à 45 % cache la vue ; des traits, non.
- **Boutons de volume** : observation KVO de `AVAudioSession.outputVolume`, avec
  remise à niveau via le slider interne d'un `MPVolumeView` hors écran. C'est une
  astuce, pas une API. Isolée dans `VolumeShutter.swift` : si Apple la casse, le
  bouton à l'écran continue de marcher et rien d'autre ne tombe.

## Structure

```
ios/
  project.yml                 définition XcodeGen (pas de .xcodeproj versionné)
  Sources/
    PoseApp.swift             point d'entrée
    ContentView.swift         écran principal, gestes sur le calque
    PoseSheet.swift           tiroir des poses
    ViewerView.swift          pellicule plein écran
    Controls.swift            déclencheur, vignette, niveau, grille, cartes
    Theme.swift               couleurs, courbes, haptique, boutons
    CameraModel.swift         session AVFoundation, zoom, retardateur, rafale
    CameraPreview.swift       couche d'aperçu UIKit
    PhotoProcessor.swift      recadrage au format, HEIC, vignettes
    ShotStore.swift           pellicule, export vers Photos
    OverlayStore.swift        bibliothèque de poses, contours, persistance
    PosePack.swift            les 8 poses intégrées
    LevelModel.swift          niveau d'horizon (CoreMotion)
    VolumeShutter.swift       déclenchement par boutons de volume
    Assets.xcassets/          icône
```
