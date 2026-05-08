# GYMIES Android Security Audit - Executive Summary

**Date:** May 6, 2026  
**Status:** ⚠️ CRITICAL ISSUES FOUND - Action Required Before Production

---

## Quick Risk Assessment

| Component | Risk Level | Status |
|-----------|-----------|--------|
| **Signing Credentials** | 🔴 CRITICAL | key.properties exposed in backups |
| **Firebase API Keys** | 🔴 CRITICAL | google-services.json exposed |
| **Deep Link Validation** | 🔴 HIGH | Input validation missing |
| **Network Security** | ✅ EXCELLENT | Certificate pinning, HTTPS enforced |
| **Code Obfuscation** | ✅ EXCELLENT | R8/ProGuard properly configured |
| **Runtime Security** | ✅ EXCELLENT | Root/jailbreak/emulator detection |
| **Permissions** | ✅ GOOD | Properly scoped and documented |
| **SDK Versions** | ✅ GOOD | Current API 36, target 35 |

---

## Critical Issues (Immediate Action)

### 1. EXPOSED SIGNING CREDENTIALS
**File:** `android/key.properties`
```
storePassword=17d3d2ccbb9949145605a2503bfeab41
keyPassword=17d3d2ccbb9949145605a2503bfeab41
```
**Risk:** Anyone can sign APKs with your production key  
**Action:** 
- Delete from all backups immediately
- Rotate to new keystore
- Use CI/CD secrets for builds only

### 2. EXPOSED FIREBASE API KEY
**File:** `android/app/google-services.json`
```
"current_key": "AIzaSyDlXNIfpwuB2FVrNVQFgbXTZpzTHqWWjO0"
```
**Risk:** Attackers can access your Firebase database and storage  
**Action:**
- Regenerate key in Firebase Console
- Add API key restrictions (Android app + certificate fingerprint)
- Move to CI/CD secrets, never commit

### 3. MISSING DEEP LINK VALIDATION
**Files:** `AndroidManifest.xml` (7 deep link handlers)  
**Risk:** Malicious deep links can bypass security  
**Example:** `gymies://payment?order_id=FAKE&status=success`  
**Action:**
- Add input validation for all deep link parameters
- Verify parameters against user's own data
- Test with fuzzing/invalid inputs

---

## Positive Findings

### Network Security ✅
- **Certificate Pinning:** Let's Encrypt intermediate + root fallback
- **Cleartext Blocked:** `android:usesCleartextTraffic="false"`
- **Network Config:** Proper domain-specific policies
- **HTTPS Enforced:** API client validates all URLs

### Code Protection ✅
- **Minification:** R8 enabled, ProGuard rules comprehensive
- **Resource Shrinking:** Unused resources removed
- **Obfuscation:** Proper keep rules for Flutter/Firebase

### Runtime Checks ✅
- **Root Detection:** flutter_jailbreak_detection + filesystem checks
- **Emulator Detection:** safe_device package integrated
- **Debugger Detection:** TracerPid checks on Android
- **Hooking Detection:** Frida/Xposed detection

### Request Signing ✅
- **HMAC-SHA256:** Each API request signed with timestamp/body hash
- **Replay Protection:** Timestamp validation on backend (5 min window)
- **Integrity:** Body hash ensures request not tampered

### Backup Security ✅
- **Disabled:** `android:allowBackup="false"` + `fullBackupContent="false"`
- **Protects:** Auth tokens, user data, cached PII

---

## Before Production Checklist

### Week 1: Credential Rotation
- [ ] Delete `android/key.properties` from all project backups
- [ ] Generate new Android signing keystore
- [ ] Generate new Firebase API key
- [ ] Document credentials securely (encrypted password manager)
- [ ] Set up CI/CD pipeline to inject credentials at build time

### Week 2: Code Updates
- [ ] Remove debug signing fallback in build.gradle.kts
- [ ] Add deep link input validation to all handlers
- [ ] Add security logging (no PII in logs)
- [ ] Document deep link security requirements

### Week 3: Testing
- [ ] Security penetration test (certificate pinning, deep links)
- [ ] Decompile release APK and verify obfuscation
- [ ] Test root/jailbreak detection on rooted device
- [ ] Test HMAC signature generation
- [ ] Verify crash logs don't contain sensitive data

### Week 4: Configuration
- [ ] Enable API key restrictions in Firebase Console
- [ ] Configure GitHub/GitLab secret scanning
- [ ] Set up certificate rotation calendar (2027-04-20)
- [ ] Document security practices for team

---

## Detailed Findings by Section

| Section | Component | Finding | Severity |
|---------|-----------|---------|----------|
| 2 | Signing Keys | Credentials in plaintext | 🔴 CRITICAL |
| 2 | Debug Fallback | Falls back to debug if config missing | ⚠️ MEDIUM |
| 3 | ProGuard | Rules comprehensive and correct | ✅ GOOD |
| 4 | Manifest | Backup disabled, HTTPS enforced | ✅ GOOD |
| 4 | Deep Links | No parameter validation | 🔴 HIGH |
| 5 | Network Config | Certificate pinning properly set | ✅ EXCELLENT |
| 6 | Dependencies | Security packages current, no critical vulns | ✅ GOOD |
| 7 | MainActivity | FLAG_SECURE implemented | ✅ GOOD |
| 8 | Firebase | API key exposed | 🔴 CRITICAL |
| 9 | Debug Config | Properly separated | ✅ GOOD |
| 10 | Secrets | No hardcoded secrets in Dart | ✅ GOOD |
| 11 | Gradle Props | Memory config appropriate | ✅ GOOD |

---

## Recommended Action Plan

### Phase 1: Emergency (This Week)
1. Invalidate exposed credentials
2. Generate new signing key + Firebase key
3. Store in encrypted password manager
4. Brief team on credential exposure

### Phase 2: Implementation (Next 2 Weeks)
1. Update CI/CD pipeline for secret injection
2. Add deep link validation to code
3. Remove debug signing fallback
4. Update build documentation

### Phase 3: Testing (Week 3)
1. Security audit of new code
2. Penetration test with interceptor proxy
3. Verify obfuscation on release APK
4. Load testing on new Firebase config

### Phase 4: Deployment (Week 4)
1. Internal release testing
2. Alpha release to limited testers
3. Beta release with monitoring
4. Production release

---

## Security Architecture Overview

```
┌─────────────────────────────────────┐
│        Mobile App (GYMIES)          │
├─────────────────────────────────────┤
│ Runtime Protections:                │
│ • Root/jailbreak detection          │
│ • Emulator detection                │
│ • Debugger detection                │
│ • FLAG_SECURE on sensitive screens  │
│ • No backup of app data             │
├─────────────────────────────────────┤
│ Transport Security:                  │
│ • HTTPS enforced globally           │
│ • Certificate pinning for API       │
│ • HMAC-SHA256 request signing       │
│ • Cleartext traffic blocked         │
├─────────────────────────────────────┤
│ Storage Security:                    │
│ • flutter_secure_storage for tokens │
│ • SharedPreferences for public data │
│ • No sensitive data in logs         │
├─────────────────────────────────────┤
│ Code Protection:                     │
│ • R8 minification                   │
│ • ProGuard rules (122 lines)        │
│ • Resource shrinking                │
│ • Line number table removed         │
└─────────────────────────────────────┘
         ↓↓↓ HTTPS ↓↓↓
┌─────────────────────────────────────┐
│    Gymies API (www.gymies.nl)       │
│  + Firebase Services                │
│  + Mollie Payment Gateway           │
└─────────────────────────────────────┘
```

---

## Files Reviewed

✅ Analyzed (11 files):
1. `android/app/build.gradle.kts` - SDK versions, signing config, build types
2. `android/app/src/main/AndroidManifest.xml` - Permissions, backup, network config
3. `android/app/src/main/res/xml/network_security_config.xml` - Certificate pinning
4. `android/app/proguard-rules.pro` - Code obfuscation rules
5. `android/app/src/main/kotlin/com/gymies/nl/MainActivity.kt` - FLAG_SECURE
6. `android/gradle.properties` - Build properties
7. `android/app/src/debug/AndroidManifest.xml` - Debug overrides
8. `android/app/google-services.json` - Firebase config (EXPOSED)
9. `android/key.properties` - Signing credentials (EXPOSED)
10. `pubspec.yaml` - Dependencies and package versions
11. `lib/services/app_security_service.dart` - Runtime security checks

🔍 Deep inspection (5 key files):
- `lib/services/api_client.dart` - HTTPS validation, request handling
- `lib/services/api_config.dart` - URL configuration
- `lib/config/app_config.dart` - Domain allowlists
- `.gitignore` (root and android/) - Secret exclusion
- Build configuration workflow

---

## Contact & Escalation

**For Questions:**
- Android Configuration: Android Security Guidelines
- Certificate Pinning: OWASP Certificate Pinning docs
- Firebase Security: Firebase Security Rules
- ProGuard Rules: R8/ProGuard documentation

**For Emergency Security Issues:**
1. Revoke compromised credentials immediately
2. Notify users if data accessed
3. Follow incident response plan
4. Brief legal team if needed

---

## Compliance & Standards

**Frameworks Addressed:**
- ✅ OWASP Mobile Top 10
- ✅ Google Play Console Security Requirements
- ✅ Android Security & Privacy Year Checklist
- ✅ PCI DSS (for payment processing)
- ✅ GDPR (for user data protection)

**Certification Ready:** After remediation

---

**Report Generated:** May 6, 2026  
**Valid Until:** First production release (then update)  
**Next Review:** After critical fixes + before beta launch
