# GYMIES Security Remediation Guide

**Purpose:** Step-by-step instructions to fix critical security issues before production  
**Timeline:** Must complete BEFORE any Play Store release  
**Risk Level:** CRITICAL - Production-blocking issues

---

## Issue #1: Exposed Signing Credentials

### Current Problem
- File: `android/key.properties` contains plaintext keystore credentials
- Credentials: `storePassword` and `keyPassword` visible in plaintext
- Storage: File exists in backups, archives, and local filesystem
- Risk: Anyone can sign APKs with your production key

### Step-by-Step Remediation

#### Step 1: Invalidate Current Key (TODAY)
```bash
# 1. Go to Google Play Console
# https://play.google.com/console → Select GYMIES → Settings → App Signing
#
# 2. Note your current upload key certificate:
# - SHA-1 fingerprint (you'll need this for API restrictions)
# - Certificate fingerprint
#
# Note: You cannot delete the upload key once published
# But you can rotate it by signing new APK with different key
```

#### Step 2: Generate New Signing Keystore (TODAY)
```bash
# Generate new keystore with strong password
# DO NOT use: 17d3d2ccbb9949145605a2503bfeab41 (exposed)

keytool -genkey -v \
  -keystore "gymies-upload-v2.jks" \
  -keyalias "gymies-release-v2" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10950 \
  -storepass "YourVeryStrongPasswordHere_MinimumRandomPassword!" \
  -keypass "YourVeryStrongPasswordHere_MinimumRandomPassword!" \
  -dname "CN=Gymies Development, OU=Engineering, O=Gymies, L=Amsterdam, ST=North Holland, C=NL"

# Output: gymies-upload-v2.jks (keep in secure location)
```

**Password Requirements:**
- Minimum 24 characters
- Mix of uppercase, lowercase, numbers, special characters
- NOT dictionary words
- NOT related to company name
- Example: `4mK9$pL2@vX8wQ3nR&jT5hY7%gF!dB6c`

#### Step 3: Update Project Configuration (TODAY)
```bash
# 1. Delete old key.properties (it's exposed)
rm android/key.properties

# 2. Create new key.properties (TEMPORARY - for local testing only)
cat > android/key.properties << 'EOF'
storePassword=YourVeryStrongPasswordHere_MinimumRandomPassword!
keyPassword=YourVeryStrongPasswordHere_MinimumRandomPassword!
keyAlias=gymies-release-v2
storeFile=../gymies-upload-v2.jks
EOF

# 3. Verify file permissions (only you can read)
chmod 600 android/key.properties

# 4. DO NOT commit this file
git status  # Verify key.properties is NOT shown (should be in .gitignore)
```

#### Step 4: Store Credentials Securely (TODAY)
```bash
# NEVER store credentials in plain text files
# Use one of these options:

# Option A: 1Password/LastPass (RECOMMENDED)
# 1. Create new vault entry "GYMIES - Android Signing Key"
# 2. Enter keystore password
# 3. Enter keyalias
# 4. Attach gymies-upload-v2.jks file
# 5. Share with team via secure vault

# Option B: macOS Keychain
security add-generic-password -a "gymies_android_keystore" \
  -s "GYMIES_KEYSTORE_PASSWORD" \
  -p "YourVeryStrongPasswordHere_MinimumRandomPassword!"

# Option C: GitHub/GitLab Secrets (for CI/CD)
# See "Configure CI/CD" section below
```

#### Step 5: Update Build Configuration (THIS WEEK)
```gradle
// File: android/app/build.gradle.kts

// Update keystore file reference
val keystoreFile = rootProject.file("../gymies-upload-v2.jks")

// Update keyAlias
val keyAlias = "gymies-release-v2"

// Load password from environment (for CI/CD)
val storePassword = System.getenv("GYMIES_KEYSTORE_PASSWORD")?.let {
    it
} ?: run {
    if (keyPropertiesFile.exists()) {
        keyProperties["storePassword"] as String
    } else {
        throw GradleException(
            "❌ GYMIES_KEYSTORE_PASSWORD env var not set " +
            "and android/key.properties not found!\n" +
            "Build cannot proceed without signing credentials."
        )
    }
}

signingConfigs {
    if (keystoreFile.exists() && storePassword != null) {
        create("release") {
            storeFile = keystoreFile
            storePass = storePassword
            keyAlias = "gymies-release-v2"
            keyPassword = System.getenv("GYMIES_KEYPASS") ?: storePassword
        }
    }
}

buildTypes {
    release {
        // ❌ REMOVE THIS FALLBACK (it was security risk)
        // signingConfig = if (...) release else debug
        
        // ✅ REQUIRE release signing (fail loudly if missing)
        signingConfig = signingConfigs.getByName("release")  // Will throw if not found
        
        isMinifyEnabled = true
        isShrinkResources = true
    }
}
```

#### Step 6: Delete from Backups (THIS WEEK)
```bash
# Search for exposed credentials in all backups
find ~/ -name "key.properties" 2>/dev/null
# Output: /Users/sara/Desktop/GYMIES - APP/android/key.properties
#         ... (any other locations)

# Delete all found copies
rm "/Users/sara/Desktop/GYMIES - APP/android/key.properties"
rm ~/Dropbox/GYMIES\ backup/key.properties  # if exists
rm ~/Downloads/GYMIES_backup.zip  # if contains key.properties
rm ~/Desktop/GYMIES_backup.zip    # if contains key.properties

# Check git history (if file ever committed)
git log --all --full-history -- android/key.properties
# If output shows commits, use BFG to remove from history (dangerous)
```

#### Step 7: Verify Build Works (THIS WEEK)
```bash
# Test building with new keystore
export GYMIES_KEYSTORE_PASSWORD="YourVeryStrongPasswordHere_MinimumRandomPassword!"

flutter build apk --release --split-per-abi

# Expected output:
# ✅ Built build/app/outputs/apk/release/*.apk
# 
# If error: "Cannot find keystore"
# Check: keystoreFile path is correct
#        GYMIES_KEYSTORE_PASSWORD is set
#        gymies-upload-v2.jks exists

# Verify APK is signed with new key
jarsigner -verify -verbose build/app/outputs/apk/release/app-release.apk
# Should show Certificate Owner: CN=Gymies Development
```

#### Step 8: Document for Team (THIS WEEK)
```markdown
# GYMIES Android Signing Key - Update Document

## Old Key (REVOKED)
- Alias: gymies-upload (INVALID - DO NOT USE)
- Password: (REVOKED)
- Status: COMPROMISED - exposed in plaintext

## New Key (ACTIVE)
- Alias: gymies-release-v2
- Keystore: gymies-upload-v2.jks (keep in secure location)
- Password: Stored in 1Password vault "GYMIES - Android Signing Key"
- Certificate: SHA-1 fingerprint = [from Play Console]
- Valid Until: [date + 10 years]

## Build Instructions
1. Extract keystore password from 1Password
2. Export: export GYMIES_KEYSTORE_PASSWORD="..."
3. Build: flutter build apk --release
```

---

## Issue #2: Exposed Firebase API Key

### Current Problem
- File: `android/app/google-services.json`
- API Key: `AIzaSyDlXNIfpwuB2FVrNVQFgbXTZpzTHqWWjO0`
- Risk: Direct access to Firebase database, storage, functions

### Step-by-Step Remediation

#### Step 1: Regenerate API Key (TODAY)
```
1. Go to Firebase Console
   https://console.firebase.google.com/project/gymiesapp-d1424

2. Select Project Settings → Service Accounts

3. Find Android API Key section:
   - Current Key: AIzaSyDlXNIfpwuB2FVrNVQFgbXTZpzTHqWWjO0
   - Status: EXPOSED

4. Click "..." → Delete or Disable

5. Generate new API key:
   - Click "Create API Key" → Browser Key
   - Copy new key (example: AIzaSyDlX... different value)
   - Add to password manager
```

#### Step 2: Add API Key Restrictions (CRITICAL)
```
1. In Firebase Console → API Keys → [Your New Key]

2. Click "Application restrictions"
   - Select "Android apps"
   - Add package name: com.Gymies.nl
   - Add SHA-1 certificate fingerprint:
     (Get from Play Console or run:)
     $ keytool -exportcert -alias gymies-release-v2 \
       -keystore gymies-upload-v2.jks | keytool -importcert

3. Click "API restrictions"
   - Unrestricted (for now)
   - Later: limit to Cloud Firestore, Storage only

4. Save
```

**Why restrictions matter:**
- Old key: Anyone with key can access any Firebase API
- Restricted key: Only Android app with matching certificate can use it
- Limits damage if key is exposed again

#### Step 3: Update google-services.json (NEXT WEEK)
```bash
# DO NOT COMMIT THIS FILE
# Instead, download from Firebase each build

# 1. Download current google-services.json from Firebase
#    Project Settings → General → Google Services JSON
#    Save as: google-services.json (temporary)

# 2. Update your project:
cp google-services.json android/app/

# 3. Verify NOT committed:
git status android/app/google-services.json
# Should show: "nothing to commit" (because .gitignore excludes it)

# 4. Delete temporary copy:
rm google-services.json
```

#### Step 4: Move to CI/CD Secrets (THIS WEEK)
```bash
# Store JSON as GitHub/GitLab secret (don't commit)

# GitHub Actions method:
# 1. Go to Repository → Settings → Secrets and variables → Actions
# 2. New repository secret:
#    Name: GOOGLE_SERVICES_JSON
#    Value: (paste entire contents of google-services.json)

# 3. In .github/workflows/build.yml:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Create google-services.json
        run: |
          echo '${{ secrets.GOOGLE_SERVICES_JSON }}' > android/app/google-services.json
      
      - name: Build
        run: flutter build apk --release
```

**GitLab CI method:**
```yaml
# .gitlab-ci.yml
before_script:
  - echo "$GOOGLE_SERVICES_JSON" > android/app/google-services.json

variables:
  GOOGLE_SERVICES_JSON: $GOOGLE_SERVICES_JSON_SECRET
```

#### Step 5: Delete from Backups (THIS WEEK)
```bash
# Remove all copies of exposed google-services.json
find ~/ -name "google-services.json" -type f 2>/dev/null

# Delete all found:
rm ~/Downloads/google-services.json
rm ~/Desktop/GYMIES\ backup/android/app/google-services.json
# etc.

# Check if in git history:
git log --all --full-history -- android/app/google-services.json
# If commits found, use BFG to clean history (risky operation)
```

#### Step 6: Verify on Next Build (THIS WEEK)
```bash
# Build should work with new key from CI/CD secrets
flutter build apk --release

# Verify new API key in APK:
unzip build/app/outputs/apk/release/app-release.apk -d tmp/
grep "current_key" tmp/assets/google-services.json
# Should show NEW key, not AIzaSyDlXNIfpwuB2FVrNVQFgbXTZpzTHqWWjO0
```

---

## Issue #3: Missing Deep Link Validation

### Current Problem
- Deep links not validated in code
- Malicious app can send: `gymies://payment?status=success&order_id=FAKE`
- No verification that parameters belong to current user

### Step-by-Step Remediation

#### Step 1: Identify All Deep Link Handlers (THIS WEEK)
```dart
// File: lib/services/deep_link_service.dart

// Current deep links from AndroidManifest.xml:
// 1. gymies://payment
// 2. gymies://trainer/{trainerId}
// 3. gymies://client/{clientId}
// 4. gymies://buddy
// 5. gymies://subscription
// 6. gymies://wachtwoord-reset
// 7. gymies://mollie-connect

// Task: Add validation for each
```

#### Step 2: Create Validation Service (THIS WEEK)
```dart
// File: lib/services/deep_link_validator.dart

class DeepLinkValidator {
  /// Validate payment deep link parameters
  static bool validatePaymentDeepLink(Map<String, String> params, String userId) {
    final orderId = params['order_id'];
    final status = params['status'];
    
    // Validate order_id exists and belongs to current user
    if (orderId == null || orderId.isEmpty) {
      debugPrint('[DeepLink] ❌ Missing order_id');
      return false;
    }
    
    if (!RegExp(r'^[0-9a-f-]+$', caseSensitive: false).hasMatch(orderId)) {
      debugPrint('[DeepLink] ❌ Invalid order_id format: $orderId');
      return false;
    }
    
    // Verify order belongs to current user
    // Query database or API to confirm
    if (!isUserOrder(userId: userId, orderId: orderId)) {
      debugPrint('[DeepLink] ❌ Order does not belong to user: $orderId');
      return false;
    }
    
    // Validate status is known value
    const validStatuses = ['success', 'failed', 'pending', 'cancelled'];
    if (status != null && !validStatuses.contains(status)) {
      debugPrint('[DeepLink] ❌ Invalid payment status: $status');
      return false;
    }
    
    return true; // All checks passed
  }
  
  /// Validate trainer profile deep link
  static bool validateTrainerDeepLink(String trainerId, String userId) {
    if (trainerId.isEmpty) return false;
    
    if (!RegExp(r'^[0-9]+$').hasMatch(trainerId)) {
      debugPrint('[DeepLink] ❌ Invalid trainer ID format: $trainerId');
      return false;
    }
    
    // Verify trainer exists (query API)
    if (!trainerExists(id: trainerId)) {
      debugPrint('[DeepLink] ❌ Trainer not found: $trainerId');
      return false;
    }
    
    return true;
  }
  
  /// Validate password reset deep link
  static bool validatePasswordResetDeepLink(Map<String, String> params) {
    final token = params['token'];
    final email = params['email'];
    
    if (token == null || token.isEmpty) {
      debugPrint('[DeepLink] ❌ Missing reset token');
      return false;
    }
    
    // Token should be JWT or similar, validate format
    if (!RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$').hasMatch(token)) {
      debugPrint('[DeepLink] ❌ Invalid token format');
      return false;
    }
    
    // Optional: verify token not expired
    if (isTokenExpired(token)) {
      debugPrint('[DeepLink] ❌ Reset token expired');
      return false;
    }
    
    return true;
  }
}
```

#### Step 3: Update Deep Link Handler (THIS WEEK)
```dart
// File: lib/main.dart or lib/services/app_link_handler.dart

class AppLinkHandler {
  static void handleDeepLink(Uri uri, BuildContext context, String userId) {
    debugPrint('[DeepLink] Received: $uri');
    
    switch (uri.host) {
      case 'payment':
        if (!DeepLinkValidator.validatePaymentDeepLink(
          uri.queryParameters,
          userId,
        )) {
          debugPrint('[DeepLink] ❌ Invalid payment deep link');
          showSecurityAlert(context, 'Invalid payment link');
          return;
        }
        final orderId = uri.queryParameters['order_id']!;
        Navigator.of(context).pushNamed(
          '/payment-confirmation',
          arguments: {'orderId': orderId},
        );
        break;
      
      case 'trainer':
        final trainerId = uri.pathSegments.isNotEmpty 
          ? uri.pathSegments.first 
          : null;
        if (trainerId == null || !DeepLinkValidator.validateTrainerDeepLink(
          trainerId,
          userId,
        )) {
          debugPrint('[DeepLink] ❌ Invalid trainer deep link');
          showSecurityAlert(context, 'Invalid trainer link');
          return;
        }
        Navigator.of(context).pushNamed(
          '/trainer-profile',
          arguments: {'trainerId': trainerId},
        );
        break;
      
      case 'wachtwoord-reset':
        if (!DeepLinkValidator.validatePasswordResetDeepLink(uri.queryParameters)) {
          debugPrint('[DeepLink] ❌ Invalid password reset link');
          showSecurityAlert(context, 'Password reset link invalid or expired');
          return;
        }
        final token = uri.queryParameters['token']!;
        Navigator.of(context).pushNamed(
          '/reset-password',
          arguments: {'token': token},
        );
        break;
      
      default:
        debugPrint('[DeepLink] ⚠️ Unknown host: ${uri.host}');
    }
  }
}
```

#### Step 4: Add Security Logging (THIS WEEK)
```dart
// Track suspicious deep link attempts
class DeepLinkSecurityLogger {
  static Future<void> logSuspiciousDeepLink(Uri uri, String reason) async {
    final logEntry = {
      'timestamp': DateTime.now().toIso8601String(),
      'uri': uri.toString(),
      'host': uri.host,
      'parameters': uri.queryParameters,
      'reason': reason,
    };
    
    // Log locally (never upload PII)
    debugPrint('[Security] Suspicious deep link: $logEntry');
    
    // Optional: send to Sentry (without sensitive data)
    // Only log the reason, not full URI if it contains secrets
    if (reason.contains('tampering') || reason.contains('unauthorized')) {
      await Sentry.captureException(
        Exception('Suspicious deep link detected'),
        stackTrace: StackTrace.current,
        hint: Hint.withContexts({
          'deep_link_reason': reason,
        }),
      );
    }
  }
}
```

#### Step 5: Test Deep Link Validation (NEXT WEEK)
```bash
# Test with valid deep link
adb shell am start -W -a android.intent.action.VIEW \
  -d "gymies://payment?order_id=12345&status=success" \
  com.Gymies.nl

# Expected: App opens payment confirmation screen

# Test with invalid deep link (should be rejected)
adb shell am start -W -a android.intent.action.VIEW \
  -d "gymies://payment?order_id=INVALID&status=FAKE" \
  com.Gymies.nl

# Expected: Security alert shown, user NOT taken to sensitive screen

# Test with missing parameters
adb shell am start -W -a android.intent.action.VIEW \
  -d "gymies://payment?status=success" \
  com.Gymies.nl

# Expected: Security alert (missing order_id)

# Test with another user's ID
adb shell am start -W -a android.intent.action.VIEW \
  -d "gymies://payment?order_id=OTHER_USER_ORDER&status=success" \
  com.Gymies.nl

# Expected: Security alert (order doesn't belong to you)
```

---

## Configure CI/CD for Secure Builds

### GitHub Actions Setup

```yaml
# File: .github/workflows/build-release.yml

name: Build Release APK

on:
  workflow_dispatch:  # Manual trigger only
  
jobs:
  build:
    runs-on: ubuntu-latest
    environment:
      name: production
    
    steps:
      - uses: actions/checkout@v3
      
      # Create keystore from secret
      - name: Create Keystore
        run: |
          echo "${{ secrets.KEYSTORE_B64 }}" | base64 -d > android/gymies-upload-v2.jks
          chmod 600 android/gymies-upload-v2.jks
      
      # Create google-services.json from secret
      - name: Create google-services.json
        run: |
          echo '${{ secrets.GOOGLE_SERVICES_JSON }}' > android/app/google-services.json
      
      # Install Flutter
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      
      # Build APK with signing
      - name: Build APK
        env:
          GYMIES_KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          GYMIES_HMAC_SECRET: ${{ secrets.HMAC_SECRET }}
        run: |
          flutter build apk --release --dart-define=GYMIES_HMAC_SECRET=${{ secrets.HMAC_SECRET }}
      
      # Verify APK signature
      - name: Verify APK Signature
        run: |
          jarsigner -verify -verbose \
            build/app/outputs/apk/release/app-release.apk
      
      # Upload to Play Store (internal testing track)
      - name: Upload to Play Store
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_STORE_SERVICE_ACCOUNT }}
          packageName: com.Gymies.nl
          releaseFiles: 'build/app/outputs/apk/release/*.apk'
          track: internal
          inAppUpdatePriority: 5
      
      # Cleanup sensitive files
      - name: Cleanup
        if: always()
        run: |
          rm -f android/gymies-upload-v2.jks
          rm -f android/app/google-services.json
```

### GitHub Actions Secrets Setup

```bash
# Go to: Repository → Settings → Secrets and variables → Actions

# Add these secrets:

# 1. KEYSTORE_B64: Base64 encoded keystore
KEYSTORE_B64=$(base64 < android/gymies-upload-v2.jks)
# Copy output to GitHub secret

# 2. KEYSTORE_PASSWORD: Keystore password
KEYSTORE_PASSWORD=YourVeryStrongPasswordHere_MinimumRandomPassword!

# 3. GOOGLE_SERVICES_JSON: Full JSON file content
GOOGLE_SERVICES_JSON=$(cat android/app/google-services.json)

# 4. HMAC_SECRET: For request signing
HMAC_SECRET=$(openssl rand -hex 32)

# 5. PLAY_STORE_SERVICE_ACCOUNT: Service account JSON
# Download from Google Play Console
```

---

## Verification Checklist

After implementing all fixes, verify:

- [ ] Old signing credentials deleted from all backups
- [ ] New keystore generated and stored securely
- [ ] Firebase API key regenerated with restrictions
- [ ] google-services.json removed from git history
- [ ] CI/CD pipeline configured for secret injection
- [ ] Deep link validation code deployed
- [ ] All 7 deep link paths validated
- [ ] Build succeeds with new keystore
- [ ] APK verified as properly signed
- [ ] Deep link security tests passed
- [ ] No credentials in git history
- [ ] .gitignore properly excludes secrets
- [ ] Team trained on new security procedures

---

## Timeline

| Week | Task | Owner |
|------|------|-------|
| **This Week** | Rotate signing credentials, regenerate Firebase key | Security |
| **This Week** | Update CI/CD pipeline, remove key.properties | DevOps |
| **Next Week** | Add deep link validation, test thoroughly | Engineering |
| **Week 3** | Security audit of changes, pentest if possible | Security |
| **Week 4** | Internal release, beta, then production | Release Team |

---

## Questions?

**For Android signing:**
- Android Developer Docs: https://developer.android.com/studio/publish/app-signing
- Keystore Troubleshooting: https://developer.android.com/studio/publish/app-signing#troubleshoot

**For Firebase security:**
- Firebase Security: https://firebase.google.com/support/guides/security-checklist
- API Key Restrictions: https://cloud.google.com/docs/authentication/api-keys#api_key_restrictions

**For deep link security:**
- Android Deep Links: https://developer.android.com/training/app-links
- Deep Link Security: https://developer.android.com/training/app-links/deep-linking

---

**Document Version:** 1.0  
**Last Updated:** May 6, 2026  
**Next Review:** After critical fixes implemented
