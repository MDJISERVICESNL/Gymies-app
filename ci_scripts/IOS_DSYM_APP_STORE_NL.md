# App Store: ontbrekende dSYM voor `objective_c.framework` (of Flutter.framework)

## Wat betekent dit?

Sinds **Xcode 16+** controleert Apple bij upload of je **archive** voor **elk ingebed framework** in `Runner.app/Frameworks` een bijpassend **dSYM** bevat (zelfde **UUID** als het binaire bestand).

**`objective_c.framework`** hoort bij de **Dart-runtime / native interop** die Flutter meelevert. Ontbreekt het bijbehorende `.dSYM`, dan krijg je precies deze fout — vergelijkbaar met eerdere meldingen over **Flutter.framework**.

## Oorzaak bij GYMIES (objective_c.framework)

Het framework **`objective_c.framework`** kwam bij jullie **niet** van Flutter zelf, maar als **transitieve dependency** van:

`google_fonts` → `path_provider` → **`path_provider_foundation` 2.6+** → **`objective_c`**

Vanaf **path_provider_foundation 2.6.0** wordt **`package:objective_c`** gebruikt; die native build levert een binary **zonder bruikbare DWARF/dSYM** voor App Store → validatie blijft falen (ook na `dsymutil`: “no debug symbols”).

**Workaround in dit project:** in `pubspec.yaml` staat een **`dependency_override`** naar **`path_provider_foundation: 2.5.1`** (zonder `objective_c`). Daarna:

```bash
flutter pub get
cd ios && pod install && cd ..
flutter build ipa
```

Verwijder de override weer als een nieuwe `path_provider_foundation`/`objective_c` dit structureel oplost.

---

## Aanbevolen oplossingen (in volgorde)

### 1. Flutter updaten (meest effectief)

Nieuwere Flutter-versies bundelen/leveren dSYMs beter en kopiëren ze bij **IPA/archive**-builds.

```bash
flutter upgrade
flutter doctor
```

Daarna opnieuw **Archive** / build op Xcode Cloud.

### 2. Release bouwen met Flutter CLI (IPA)

`flutter build ipa` gebruikt de tooling die bedoeld is voor distributie en symbolen:

```bash
cd /pad/naar/je/flutter-project   # repo met pubspec.yaml
flutter pub get
cd ios && pod install && cd ..
flutter build ipa
```

Upload het gegenereerde **IPA** via Transporter of je CI-pipeline.  
*(Als je nu alleen vanuit Xcode archiveert zonder deze stap, kan een framework-dSYM alsnog ontbreken op oudere of afwijkende setups.)*

### 3. Xcode Cloud: zelfde Flutter als lokaal

Zorg dat op de server **dezelfde (recente) Flutter** draait als waarmee je lokaal ontwikkelt (`ci_post_clone.sh` clone’t `stable`). Na een upgrade lokaal: push en laat de cloud opnieuw bouwen.

### 4. Handmatig dSYM toevoegen (noodoplossing)

Alleen als je meteen moet shippen en 1–2 niet werkt:

1. Maak lokaal een **Archive** (zoals nu).
2. Rechtsklik archive in **Organizer** → **Show in Finder** → rechtsklik **.xcarchive** → **Show Package Contents**.
3. Open `Products/Applications/Runner.app/Frameworks/` en zoek **`objective_c.framework`**.
4. Genereer een dSYM van het binaire bestand (naam meestal `objective_c`):

   ```bash
   cd /pad/naar/objective_c.framework
   dsymutil objective_c -o objective_c.framework.dSYM
   ```

5. Kopieer **`objective_c.framework.dSYM`** naar de map **`dSYMs`** in hetzelfde `.xcarchive`-pakket (naast o.a. `Runner.app.dSYM`).

6. Upload opnieuw vanuit Organizer / Transporter.

**Let op:** de **UUID** in de foutmelding moet overeenkomen met wat `dwarfdump --uuid objective_c.framework/objective_c` toont.

## Controle in Xcode (Release)

- **Build Settings** → **Debug Information Format** → voor **Release**: **DWARF with dSYM File** (bij jullie Runner-project meestal al zo).
- **Strip Linked Product** / agressief strippen van embedded frameworks vermijden voor de store-build als je problemen houdt.

## Meer context

- Flutter: o.a. [issue #116493](https://github.com/flutter/flutter/issues/116493), PR die **Flutter.framework.dSYM** naar archives kopieert.
- Zelfde soort vereiste van Apple voor andere embedded `.framework`-bundels.
