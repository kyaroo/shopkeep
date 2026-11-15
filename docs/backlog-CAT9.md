# myhanout — Backlog & prochains pas (CAT9)

Réconcilié 2026-11-15 (session de reprise). Vérifications réelles exécutées,
pas reprises du handoff.

## 0. Vérifié sur la mainline (sorties réelles)

- **shopkeeper** : HEAD `4768487` (CAT7b). Arbre propre sauf
  `M test/poc/inventory_refresh_poc_test.dart` (+1 ligne, `library …;`).
  49 commits d'avance sur `origin/main`, 0 derrière — **jamais poussé**.
  - `flutter test` → **75/75 pass**.
  - `flutter analyze` → **0 erreur** (63 infos/warnings cosmétiques).
  - Les 2 « échecs préexistants » (`catalog_home_smoke_test`, `widget_test`)
    **passent**. FIX-TESTS est un faux reste → passer en B4.
- **catalog-server** : HEAD `07a0b23` (CAT6), `app.py` syntaxe OK.
  - **BUG A (bloquant CAT9)** : `GET /v1/shops` sélectionne `catalog_version`
    dans le SELECT mais ne le met pas dans le dict de réponse → `KeyError`
    → **HTTP 500 à chaque appel**. (`GET /v1/shops/{key}`, lui, le retourne.)
  - **BUG B** : conteneur prod `barcode-mapper-catalog` = image du 23 oct
    (bind-mount `app.py` → code à jour) mais **volume `server_catalog-data`
    d'avant CAT6** : table `shops` sans `catalog_version`, et
    `POST /v1/shops/{key}/catalog-version` → `{"detail":"Not Found"}`
    (route absente du process). L'`ALTER` de migration ne tourne qu'au
    démarrage du conteneur → il faut **recreate**.
  - **BUG C (silencieux)** : le delta ne borne pas la taille des photos.
    `processPhoto` plafonne à 50 Ko, mais `CatalogDeltaBuilder` prend des
    octets bruts et `CatalogDelta.apply` écrit tel quel ; le serveur accepte
    jusqu'à 64 Ko. À 14 669 produits le fichier peut dépasser le budget
    49,5 Mo. Non bloquant pour l'UI.

## 1. Décisions verrouillées (2026-11-15)

| # | Décision |
|---|---|
| 1 | **Version = compteur monotone 1, 2, 3…** (seed = 1). Lisible dans l'UI et dans le nom du fichier. L'epoch-ms du plan 2026-11-14 est abandonné. |
| 2 | **Livraison = fichier `.myhanout` manuel** (WhatsApp / partage Android). Le shopkeeper reste **100 % hors ligne** — pas d'upload HTTP. |
| 3 | **Une boutique par poussée.** Pas de « pousser à toutes ». |
| 4 | **`PushTracker` en mémoire en v1** (placeholder, prod → SQLite plus tard). |
| 5 | Écran admin nommé **« Distribution du catalogue »** (pas « Push » : il n'y a pas de réseau). |

## 2. Prochains pas — CAT9 (ordonné, portes de validation)

### Phase 0 — Prérequis serveur (30 min, S) · porte : `GET /v1/shops` = 200
- A1. `GET /v1/shops` : ajouter `"catalog_version": r[5]` dans le dict de
  réponse (corrige le 500).
- A2. Recréer le conteneur prod pour appliquer la migration du schéma
  (`docker compose -f docker-compose.prod.yml up -d`).
- A3. Test round-trip live sur `:8020` : `POST /v1/shops/{key}/catalog-version`
  puis `GET /v1/shops/{key}` → la version remonte.
- **Porte** : les 3 sorties curl OK, sinon on ne touche pas à l'app.

### Phase 1 — Distribution du catalogue (3 h, M) · porte : `flutter test` 75/75+
- B1. `CatalogSyncClient.listShops()` + `getShop()` étendu (nom **et**
  version). Nouveau modèle `ShopRow {shopKey, businessName, catalogVersion}`.
- B2. `lib/screens/catalog_push_screen.dart` :
  - liste des boutiques (serveur, version cible affichée) ;
  - source du delta : **tout le catalogue local** (par défaut) ou **depuis une
    base** (`updatedAt > base`) ;
  - garde de version : `base` = version du shop ; refus explicite si la base ne
    correspond pas au catalogue local ;
  - « Générer le delta » → `.myhanout` (temp) + `Share.shareXFiles` ;
  - `PushTracker.record(shopKey, target, …)` + `CatalogVersionService.report()`
    **seulement après confirmation** de la livraison par l'utilisateur.
- B3. Entrée dans `AdminSetupScreen` (dans le bloc `kIsAdmin`) + clés i18n
  fr/en/ar (3 fichiers, 98 clés aujourd'hui).
- **Porte** : `flutter test` + `flutter analyze` 0 erreur, build APK admin.

### Phase 2 — Affichage côté shopkeeper (1 h, S) · porte : visible au réglage
- C1. Réglage « Catalogue » : version installée via `Config.getCatalogVersion()`,
  libellé + i18n. Aucune réseau.
- C2. Le snackbar de `MyhanoutFile.applyJson` annonce déjà « catalog → N » :
  vérifier le libellé en 3 langues.

### Vérification finale
`flutter test` (75/75 + nouveaux), `flutter analyze` 0 erreur, curls serveur,
build `flutter build apk --target-platform android-arm64 --flavor admin --debug`.

## 3. Backlog mis à jour

| ID | Item | Est. | Statut |
|---|---|---|---|
| **CAT9** | Distribution du catalogue (admin) + version côté shopkeeper | **4 h (M)** | ✅ `cbc70f3` → poussé |
| A1–A3 | Correctifs serveur (500 liste + recreate + test) | 30 min (S) | ✅ `abb29c6` (local, pas de remote) |
| — | Pousser les commits sur `origin/main` | — | ✅ `e0da8d8` (historique purgé des APK) |
| **BUG C** | Borner la taille des photos dans le delta (≤ 50 Ko, refus explicite) | 1 h (S) | ✅ `d34a22a` → poussé |
| B4 | QR v2 : TTL par shop (`ttl_seconds` dans le token) | 4 h (M) | ← prochain |
| CAT3b | Flag produits ajoutés localement (récupération facile) | 3 h (M) | après B4 |
| FIX-TESTS | ~~2 échecs préexistants~~ — **invalide, 83/83 passent** | — | ❌ retiré |

Note push : les 4 APK de 207 Mo ont été purgés de l'historique
(`git filter-branch`, backup `backup/pre-apk-purge` = `704ddc9`).
`releases/shopkeeper-latest.apk` et `public/latest.apk` restent trackés :
ce sont des symlinks. `assets/catalog_seed.db` (60 Mo) passe sous la
limite dure de 100 Mo mais dépasse le seuil recommandé (50 Mo).

## 4. Dépendances
CAT9 Phase 1 → Phase 0 (serveur). Phase 2 → Phase 1 (clés i18n).
B4 et CAT3b sont indépendants de CAT9 mais partagent `Provisioning` (B4) et
`products`/`photo_source` (CAT3b) — les faire **après** CAT9 pour éviter les
conflits de fichiers.

## 5. Watch-outs
- Ne pas écrire `const Text('…'.tr())` ; `intl` masque `TextDirection` →
  `import 'dart:ui' as ui` + `ui.TextDirection.rtl`.
- `businessName` ne se traduit pas.
- Le delta est **universel** : ne jamais le lier à un shop (décision eaced20).
- Le shopkeeper ne doit rien avoir de réseau : garder `kIsAdmin` devant tout
  client de sync.
