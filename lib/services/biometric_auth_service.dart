import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Biometrische authenticatie service.
/// Ondersteunt vingerafdruk (Touch ID), gezichtsherkenning (Face ID), en iris scan.
///
/// Gebruik:
/// - Bij app-open: optioneel biometrisch ontgrendelen (als ingeschakeld)
/// - Bij betalingen: verplicht biometrisch bevestigen
/// - Bij profiel wijzigingen: extra verificatie
class BiometricAuthService {
  BiometricAuthService._();
  static final instance = BiometricAuthService._();

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// SharedPreferences keys
  static const _prefEnabled = 'gymies_biometric_enabled';
  static const _prefAsked = 'gymies_biometric_asked';

  // ─── Beschikbaarheid ────────────────────────────────────────────────

  /// Controleert of het apparaat biometrie ondersteunt.
  Future<bool> get isAvailable async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Lijst van beschikbare biometrische methodes.
  Future<List<BiometricType>> get availableBiometrics async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Geeft een gebruiksvriendelijke naam terug: "Face ID", "Touch ID", of "Biometrie".
  Future<String> get biometricLabel async {
    if (!Platform.isIOS) return 'Biometrie';
    final types = await availableBiometrics;
    if (types.contains(BiometricType.face)) return 'Face ID';
    if (types.contains(BiometricType.fingerprint)) return 'Touch ID';
    return 'Biometrie';
  }

  // ─── Voorkeur opslag ───────────────────────────────────────────────

  /// Is biometrische auth ingeschakeld door de gebruiker?
  Future<bool> get isEnabled async {
    try {
      // BUG FIX: Add try-catch for SharedPreferences.getInstance()
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefEnabled) ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Biometric] isEnabled error: $e');
      return false;
    }
  }

  /// Schakel biometrische auth in/uit.
  Future<void> setEnabled(bool enabled) async {
    try {
      // BUG FIX: Add try-catch for SharedPreferences operations
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabled, enabled);
      if (kDebugMode) debugPrint('[Biometric] enabled=$enabled');
    } catch (e) {
      if (kDebugMode) debugPrint('[Biometric] setEnabled error: $e');
    }
  }

  /// Is de gebruiker al gevraagd of hij biometrie wil inschakelen?
  Future<bool> get hasBeenAsked async {
    try {
      // BUG FIX: Add try-catch for SharedPreferences.getInstance()
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefAsked) ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Biometric] hasBeenAsked error: $e');
      return false;
    }
  }

  /// Markeer dat de gebruiker de opt-in vraag heeft gezien.
  Future<void> markAsked() async {
    try {
      // BUG FIX: Add try-catch for SharedPreferences operations
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefAsked, true);
    } catch (e) {
      if (kDebugMode) debugPrint('[Biometric] markAsked error: $e');
    }
  }

  /// Reset alles bij logout — voorkomt dat volgende gebruiker biometric erft.
  Future<void> clearOnLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefEnabled);
    await prefs.remove(_prefAsked);
    if (kDebugMode) debugPrint('[Biometric] Prefs gewist bij logout');
  }

  // ─── Authenticatie ─────────────────────────────────────────────────

  /// Voer biometrische authenticatie uit.
  /// [reason] wordt getoond aan de gebruiker in de biometrie prompt.
  /// Returns true als succesvol, false bij annulering of fout.
  Future<bool> authenticate({
    String reason = 'Verifieer je identiteit om door te gaan',
  }) async {
    try {
      final available = await isAvailable;
      if (!available) {
        if (kDebugMode) debugPrint('[Biometric] Niet beschikbaar op dit apparaat');
        return false;
      }

      final result = await _localAuth.authenticate(
        localizedReason: reason,
      );
      if (kDebugMode) debugPrint('[Biometric] Resultaat: $result');
      return result;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[Biometric] PlatformException: ${e.code} — ${e.message}');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Biometric] Onverwachte fout: $e');
      return false;
    }
  }

  /// Biometrisch ontgrendelen bij app-open.
  Future<bool> authenticateForAppOpen() async {
    final label = await biometricLabel;
    return authenticate(
      reason: 'Gebruik $label om GYMIES te openen',
    );
  }

  /// Biometrisch bevestigen voor betalingen (strengere check).
  Future<bool> authenticateForPayment() async {
    return authenticate(
      reason: 'Bevestig je identiteit om de betaling te voltooien',
    );
  }

  /// Biometrisch bevestigen voor profiel wijzigingen.
  Future<bool> authenticateForProfile() async {
    return authenticate(
      reason: 'Bevestig je identiteit om je profiel te wijzigen',
    );
  }
}
