# Runner.xcworkspace gebruiken (iOS + CocoaPods)

Flutter met **CocoaPods** moet altijd via **`Runner.xcworkspace`** gebouwd worden, niet via `Runner.xcodeproj`. Alleen dan laadt Xcode de Pods en klopt `PODS_ROOT`.

---

## Lokaal (Xcode op je Mac)

1. Sluit een eventueel geopend `Runner.xcodeproj`.
2. Open de workspace:
   ```bash
   open ios/Runner.xcworkspace
   ```
   Of in Finder: `ios/` → dubbelklik **`Runner.xcworkspace`** (wit icoon met twee rechthoeken).
3. Bovenin: scheme **Runner** → bestemming **Any iOS Device** (of een echte iPhone).
4. **Product → Archive**.

**Tip:** Voeg `Runner.xcworkspace` toe aan je Xcode **Window → Welcome to Xcode → Open Recent**; open nooit per ongeluk alleen het `.xcodeproj`.

---

## Xcode Cloud (aanpassen in de workflow)

Je stelt dit in bij de **workflow** die je app bouwt, niet in de Flutter-code.

### Optie A – via Xcode (meest gebruikelijk)

1. Open lokaal **`ios/Runner.xcworkspace`** in Xcode.
2. **Product** → **Xcode Cloud** → **Manage Workflows…**  
   *(Of: navigator links het wolk-icoon / Report navigator → Xcode Cloud.)*
3. Kies je workflow (bijv. “Default”) → **Edit Workflow**.
4. Zoek het veld voor het **project / workspace** (vaak **“Project”** of **“Xcode Project”**).
5. Kies **`Runner.xcworkspace`** onder de map **`ios`**, **niet** `Runner.xcodeproj`.
6. Controleer dat het **scheme** **Runner** is (Archive-actie).
7. Sla op.

### Optie B – via App Store Connect

1. Ga naar [App Store Connect](https://appstoreconnect.apple.com) → je app → **Xcode Cloud**.
2. Open **Workflows** → selecteer de workflow → **Edit** / bewerkingspictogram.
3. Stel het **Xcode-project** in op **`ios/Runner.xcworkspace`** (niet `.xcodeproj`).
4. Scheme: **Runner**.

*(Exacte menunamen kunnen iets verschillen per Xcode-versie; het gaat altijd om: workspace = `.xcworkspace`, pad meestal `ios/Runner.xcworkspace`.)*

---

## Controleren

- In de workflow staat iets als: **`ios/Runner.xcworkspace`** + scheme **`Runner`**.
- Na wijziging: nieuwe build starten; fouten over **`/Target Support Files/Pods-Runner/...`** horen dan weg te zijn **als** `ci_post_clone.sh` / `ci_pre_xcodebuild.sh` ook `pod install` uitvoeren.

---

## Command line (ter referentie)

Archive bouwen via Flutter (gebruikt intern de juiste workspace):

```bash
flutter build ipa
```

Handmatig met `xcodebuild` moet je **`Runner.xcworkspace`** meegeven:

```bash
cd ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release archive ...
```

Niet: `-project Runner.xcodeproj` voor een gepodde Flutter-app.
