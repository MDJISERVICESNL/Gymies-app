# Xcode Cloud-scripts (Flutter + CocoaPods)

## Scripts

| Bestand | Wanneer |
|--------|---------|
| `ci_post_clone.sh` | Na `git clone`: Flutter (stable) + `pub get` + `pod install` |
| `ci_pre_xcodebuild.sh` | Direct vóór `xcodebuild`: opnieuw `pub get` + `pod install` + controle op `.xcfilelist` |

Beide moeten **uitvoerbaar** zijn: `chmod +x ci_scripts/*.sh`

## App Store Connect / Xcode Cloud

1. **Workspace:** de workflow moet **`ios/Runner.xcworkspace`** bouwen, niet `Runner.xcodeproj`. **Stap-voor-stap:** zie **[XCODE_CLOUD_WORKSPACE_NL.md](./XCODE_CLOUD_WORKSPACE_NL.md)**.
2. **Branch:** commits met `ci_scripts/` moeten op de branch staan die Xcode Cloud bouwt.
3. **Fout `/Target Support Files/...`:** betekent meestal dat `PODS_ROOT` leeg was (geen geldige Pods-xcconfig). Oorzaak: geen `pod install` vóór Archive, of alleen `.xcodeproj` i.p.v. workspace. De scripts hierboven lossen dat op.

## Lokaal testen

```bash
export CI_PRIMARY_REPOSITORY_PATH="$(pwd)"
./ci_scripts/ci_post_clone.sh
./ci_scripts/ci_pre_xcodebuild.sh
```

Daarna in `ios/`: Archive met **Runner.xcworkspace**.

## Eerste keer na clone

```bash
flutter pub get && cd ios && pod install
```

Als `Debug.xcconfig` / `Release.xcconfig` een **verplichte** `#include` voor Pods hebben, faalt Xcode duidelijk tot `pod install` is gedraaid — dat is bewust.

## App Store: dSYM voor `objective_c.framework` / Flutter.framework

Zie **[IOS_DSYM_APP_STORE_NL.md](./IOS_DSYM_APP_STORE_NL.md)** als Apple meldt dat het archive geen dSYM heeft voor een ingebed framework.
