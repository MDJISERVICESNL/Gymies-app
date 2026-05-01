# iOS Build Errors - Oplossingen

Dit document beschrijft de oplossingen voor de iOS build errors in het GYMIES project.

## ✅ Opgelost in het project

### 1. iOS Deployment Target (Pods)
**Probleem:** `IPHONEOS_DEPLOYMENT_TARGET is set to 9.0, but the range of supported deployment target versions is 12.0 to 26.1.99`

**Huidige app-vereiste:** minimum **iOS 16.0** (Runner + alle pods via `Podfile`).

**Oplossing:** De `ios/Podfile` gebruikt `platform :ios, '16.0'` en een `post_install` script dat pods met een lager deployment target naar **16.0** zet. Dit geldt o.a. voor:
- permission_handler_apple
- DKImagePickerController
- DKPhotoGallery
- SDWebImage
- SwiftyGif

**Actie:** Na wijzigingen aan dependencies, voer uit:
```bash
cd ios
LANG=en_US.UTF-8 pod install
```

### 2. Xcode Recommended Settings
**Probleem:** "Update to recommended settings" waarschuwing voor Runner en Pods projecten.

**Oplossing (handmatig in Xcode):**
1. Open `ios/Runner.xcworkspace` in Xcode
2. Selecteer het **Runner** project in de navigator
3. Klik op de geel/oranje waarschuwing "Update to recommended settings"
4. Klik op **Perform Changes**
5. Herhaal voor het **Pods** project als dat ook wordt getoond

### 3. mobile_scanner objc_ownership
**Probleem:** `'objc_ownership' only applies to Objective-C object or block pointer types; type here is 'CVPixelBufferRef _Nullable'`

**Oplossing:** Er is een workaround toegevoegd aan de Podfile die `GCC_TREAT_WARNINGS_AS_ERRORS = NO` en `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` zet voor het mobile_scanner target.

**Als de fout blijft:** Dit is een bekend issue in de mobile_scanner package (Swift/ObjC interop). De app zou nog steeds moeten builden als het als "warning" wordt behandeld. Als het een harde error blijft:
- Controleer in Xcode: **Build Settings** → zoek "Treat Warnings as Errors" → zet op **No** voor het Runner target
- Of wacht op een fix in een toekomstige mobile_scanner versie

---

## ⚠️ Third-party package issues (geen directe fix)

Deze fouten zitten in Flutter packages in `~/.pub-cache/`. Wijzigingen daar worden overschreven bij `flutter pub get`.

### file_picker
- `UIActivityIndicatorViewStyleWhite` deprecated → Gebruik nieuwere file_picker (10.x) als mogelijk
- `Incompatible pointer types` / `Unused variable` → Worden in nieuwere versies mogelijk opgelost

### mobile_scanner (buiten objc_ownership)
- `'catch' block is unreachable`
- `'devices(for:)' was deprecated`
- `Immutable value 'device' was never used`

### permission_handler_apple
- `'subscriberCellularProvider' is deprecated`

### DKImagePickerController / DKPhotoGallery
- `'class' keyword deprecated` → gebruik `AnyObject`
- `UnsafeMutableRawPointer` / `FileManager` Sendable issues
- Deployment target → **opgelost via Podfile**

**Aanbeveling:** Houd packages up-to-date met `flutter pub upgrade`. Nieuwere versies lossen vaak deprecated API's op.

---

## Build uitvoeren

```bash
# 1. Flutter dependencies
flutter pub get

# 2. iOS Pods (met UTF-8 encoding voor CocoaPods)
cd ios
LANG=en_US.UTF-8 pod install
cd ..

# 3. Clean build
flutter clean
flutter build ios
```

## CocoaPods encoding fix (permanent)

Als je steeds `LANG=en_US.UTF-8` moet gebruiken, voeg toe aan `~/.zshrc`:
```bash
export LANG=en_US.UTF-8
```
