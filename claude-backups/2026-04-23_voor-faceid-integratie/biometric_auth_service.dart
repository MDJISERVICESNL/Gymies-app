import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Biometrische authenticatie service.
/// Ondersteunt vingerafdruk, gezichtsherkenning, en iris scan.
///
/// Gebruik:
/// - Bij app-open: optioneel biometrisch ontgrendelen
/// - Bij betalingen: verplicht biometrisch bevestigen
/// - Bij profiel wijzigingen: extra verificatie
class BiometricAuthService {
  BiometricAuthService._();
  static final instance = BiometricAuthService._();

  final LocalAuthentication _localAuth = LocalAuthentication();
  static const _prefKey = 'gymies_biometric_enabled';

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

  /// Is biometrische auth ingeschakeld door de gebruiker?
  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Schakel biometrische auth in/uit.
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }

  /// Voer biometrische authenticatie uit.
  /// [reason] wordt getoond aan de gebruiker in de biometrie prompt.
  /// Returns true als succesvol, false bij annulering of fout.
  Future<bool> authenticate({
    String reason = 'Verifieer je identiteit om door te gaan',
  }) async {
    try {
      final available = await isAvailable;
      if (!available) return false;

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // Sta ook PIN/patroon toe als fallback
        ),
      );
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[Biometric] Fout: ${e.code} — ${e.message}');
      return false;
    } catch (_) {
      return false;
    }
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
