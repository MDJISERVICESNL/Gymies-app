import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'biometric_auth_service.dart';

// Gevoelige sleutel – opgeslagen in iOS Keychain / Android Keystore via flutter_secure_storage.
const _kTokenKey = 'gymies_auth_token';
// Niet-gevoelige sleutels – opgeslagen in SharedPreferences (NSUserDefaults).
const _kApiBaseKey = 'gymies_api_base_url';
const _kUserKey = 'gymies_user';
const _kRememberMeKey = 'gymies_remember_me';

/// Beveiligde opslag voor het auth-token (iOS Keychain, Android Keystore).
const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

/// Wordt gegooid wanneer registratie succesvol is maar e-mailverificatie vereist.
class EmailVerificationRequiredException implements Exception {
  EmailVerificationRequiredException(this.email);
  final String email;
}

class AuthService extends ChangeNotifier {
  AuthService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;
  String? _token;
  Map<String, dynamic>? _user;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  /// True terwijl loadStoredAuth() loopt – voorkomt redirect naar login voor token geladen is.
  bool get loadingStored => _loadingStored;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  bool _loadingStored = false;
  bool get isTrainer => _isTrainerMap(_user);
  bool get isAdmin => _isAdminMap(_user);

  bool isTrainerUser([Map<String, dynamic>? userOverride]) {
    return _isTrainerMap(userOverride ?? _user);
  }

  bool isAdminUser([Map<String, dynamic>? userOverride]) {
    return _isAdminMap(userOverride ?? _user);
  }

  Future<void> loadStoredAuth() async {
    _loadingStored = true;
    if (kDebugMode) debugPrint('[AUTH_DEBUG] loadStoredAuth start');
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool(_kRememberMeKey) ?? true;
      if (!rememberMe) {
        if (kDebugMode) debugPrint('[AUTH_DEBUG] rememberMe=false → token gewist');
        _token = null;
        _user = null;
        _api.setAuthToken(null);
        await prefs.remove(_kTokenKey);
        await prefs.remove(_kUserKey);
        return;
      }

      // Controleer of de API-URL drastisch gewijzigd is (ander domein).
      // Normaliseert voor vergelijking: lowercase, trailing slash strippen, www-prefix negeren.
      final storedBase = prefs.getString(_kApiBaseKey);
      final currentBase = gymiesApiBaseUrl;
      if (kDebugMode) debugPrint('[AUTH_DEBUG] storedBase=$storedBase currentBase=$currentBase');
      if (storedBase != null && !_apiBaseUrlsMatch(storedBase, currentBase)) {
        if (kDebugMode) debugPrint('[AuthService] API domein gewijzigd → token gewist');
        _token = null;
        _user = null;
        _api.setAuthToken(null);
        await prefs.remove(_kTokenKey);
        await prefs.remove(_kUserKey);
        await prefs.remove(_kApiBaseKey);
        return;
      }

      // Token lezen uit beveiligde opslag (iOS Keychain / Android Keystore).
      // Migratie: als er nog een token in SharedPreferences staat, verplaats het naar secure storage.
      final legacyToken = prefs.getString(_kTokenKey);
      if (legacyToken != null && legacyToken.isNotEmpty) {
        await _secureStorage.write(key: _kTokenKey, value: legacyToken);
        await prefs.remove(_kTokenKey);
        if (kDebugMode) debugPrint('[AUTH_DEBUG] Token gemigreerd van SharedPreferences naar SecureStorage');
      }
      _token = await _secureStorage.read(key: _kTokenKey);
      final userJson = prefs.getString(_kUserKey);
      if (userJson != null) {
        try {
          _user = _decodeUser(userJson);
        } catch (_) {
          _user = null;
        }
      }
      if (_token != null) {
        _api.setAuthToken(_token);
        // Sentry user context herstellen bij app restart
        if (_user != null) {
          final userId = _user!['id']?.toString() ?? '';
          final role = _user!['role']?.toString() ?? _user!['user_role']?.toString() ?? 'unknown';
          Sentry.configureScope((scope) {
            scope.setUser(SentryUser(
              id: userId,
              username: _user!['display_name']?.toString(),
              data: {'role': role},
            ));
            scope.setTag('user.role', role);
          });
        }
        if (kDebugMode) debugPrint('[AUTH_DEBUG] Token geladen uit SecureStorage: ${_token!.length} chars, hexOnly=${_isHex64(_token!)}');
      } else {
        if (kDebugMode) debugPrint('[AUTH_DEBUG] Geen token opgeslagen');
      }
      if (kDebugMode) debugPrint('[AUTH_DEBUG] loadStoredAuth done – isLoggedIn=$isLoggedIn');
    } catch (e, st) {
      // SharedPreferences, SecureStorage of andere native calls kunnen falen.
      // Cruciaal: _loadingStored MOET altijd op false gezet worden via finally.
      if (kDebugMode) debugPrint('[AUTH_DEBUG] loadStoredAuth error: $e\n$st');
      _token = null;
      _user = null;
      _api.setAuthToken(null);
    } finally {
      _loadingStored = false;
      notifyListeners();
    }
  }

  Map<String, dynamic>? _decodeUser(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  bool _isHex64(String s) =>
      s.length == 64 && RegExp(r'^[a-fA-F0-9]+$').hasMatch(s);

  bool _isTrainerMap(Map<String, dynamic>? userMap) {
    if (userMap == null) return false;

    String? normalizeRole(dynamic value) {
      final v = value?.toString().trim().toLowerCase();
      return (v == null || v.isEmpty) ? null : v;
    }

    final directRole =
        normalizeRole(userMap['role']) ??
        normalizeRole(userMap['user_role']) ??
        normalizeRole(userMap['userType']) ??
        normalizeRole(userMap['user_type']) ??
        normalizeRole(userMap['accountType']) ??
        normalizeRole(userMap['account_type']) ??
        normalizeRole(userMap['type']);
    if (directRole == 'trainer') return true;

    final roleObject = userMap['role'];
    if (roleObject is Map<String, dynamic>) {
      final roleName =
          normalizeRole(roleObject['name']) ??
          normalizeRole(roleObject['slug']) ??
          normalizeRole(roleObject['type']);
      if (roleName == 'trainer') return true;
    }

    final roles = userMap['roles'];
    if (roles is List) {
      for (final entry in roles) {
        if (entry is Map<String, dynamic>) {
          final roleName =
              normalizeRole(entry['name']) ??
              normalizeRole(entry['slug']) ??
              normalizeRole(entry['type']);
          if (roleName == 'trainer') return true;
        } else {
          if (normalizeRole(entry) == 'trainer') return true;
        }
      }
    }

    return false;
  }

  bool _isAdminMap(Map<String, dynamic>? userMap) {
    if (userMap == null) return false;

    String? normalizeRole(dynamic value) {
      final v = value?.toString().trim().toLowerCase();
      return (v == null || v.isEmpty) ? null : v;
    }

    if (userMap['is_admin'] == true) return true;
    if (userMap['is_admin_user'] == true) return true;

    final directRole =
        normalizeRole(userMap['role']) ??
        normalizeRole(userMap['user_role']) ??
        normalizeRole(userMap['userType']) ??
        normalizeRole(userMap['user_type']) ??
        normalizeRole(userMap['account_type']) ??
        normalizeRole(userMap['type']);
    if (directRole == 'admin' || directRole == 'staff') return true;

    final roleObject = userMap['role'];
    if (roleObject is Map<String, dynamic>) {
      final roleName =
          normalizeRole(roleObject['name']) ??
          normalizeRole(roleObject['slug']) ??
          normalizeRole(roleObject['type']);
      if (roleName == 'admin' || roleName == 'staff') return true;
    }

    final roles = userMap['roles'];
    if (roles is List) {
      for (final entry in roles) {
        if (entry is Map<String, dynamic>) {
          final roleName =
              normalizeRole(entry['name']) ??
              normalizeRole(entry['slug']) ??
              normalizeRole(entry['type']);
          if (roleName == 'admin' || roleName == 'staff') return true;
        } else {
          final n = normalizeRole(entry);
          if (n == 'admin' || n == 'staff') return true;
        }
      }
    }

    final caps = userMap['capabilities'];
    if (caps is List) {
      for (final c in caps) {
        final s = c?.toString().toLowerCase() ?? '';
        if (s.contains('admin.access') || s.contains('admin')) return true;
      }
    }

    return false;
  }

  Future<void> _persist(
    String token,
    Map<String, dynamic>? user, {
    bool rememberMe = true,
  }) async {
    _token = token;
    _user = user;
    _api.setAuthToken(token);

    // ── Sentry user context ──────────────────────────────────────
    // Koppel crashes/errors aan deze user. Geen PII behalve user ID en rol.
    if (user != null) {
      final userId = user['id']?.toString() ?? '';
      final role = user['role']?.toString() ?? user['user_role']?.toString() ?? 'unknown';
      Sentry.configureScope((scope) {
        scope.setUser(SentryUser(
          id: userId,
          username: user['display_name']?.toString(),
          data: {'role': role},
        ));
        scope.setTag('user.role', role);
      });
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberMeKey, rememberMe);
    if (rememberMe) {
      // Token altijd in beveiligde opslag (Keychain/Keystore) – nooit in NSUserDefaults.
      await _secureStorage.write(key: _kTokenKey, value: token);
      await prefs.remove(_kTokenKey); // verwijder eventuele legacy plaintext kopie
      await prefs.setString(_kApiBaseKey, gymiesApiBaseUrl);
      if (user != null) {
        await prefs.setString(_kUserKey, jsonEncode(user));
      } else {
        await prefs.remove(_kUserKey);
      }
    } else {
      await _secureStorage.delete(key: _kTokenKey);
      await prefs.remove(_kTokenKey);
      await prefs.remove(_kUserKey);
      await prefs.remove(_kApiBaseKey);
    }
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _api.setAuthToken(null);
    // Sentry user context wissen — voorkom dat errors van volgende sessie aan oude user gekoppeld worden.
    Sentry.configureScope((scope) => scope.setUser(null));
    // Verwijder token uit beveiligde opslag én SharedPreferences (migratie-restanten).
    await _secureStorage.delete(key: _kTokenKey);
    final prefs = await SharedPreferences.getInstance();
    // Auth keys
    await prefs.remove(_kTokenKey);
    await prefs.remove(_kUserKey);
    await prefs.remove(_kApiBaseKey);
    await prefs.remove(_kRememberMeKey);
    // User-specifieke data: voorkom dat volgende inlogger data van vorige ziet
    await prefs.remove('gymies_favorite_trainer_ids');
    await prefs.remove('gymies_removed_from_my_trainers_ids');
    await prefs.remove('gymies_client_city');
    await prefs.remove('gymies_client_onboarding_done');
    await prefs.remove('gymies_client_goal');
    // Biometric voorkeuren wissen — voorkomt dat volgende gebruiker Face ID erft.
    await BiometricAuthService.instance.clearOnLogout();
    notifyListeners();
  }

  Future<void> setUser(Map<String, dynamic> user) async {
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(_kRememberMeKey) ?? true;
    if (rememberMe) {
      await prefs.setString(_kUserKey, jsonEncode(user));
    }
    notifyListeners();
  }

  /// Login: retourneert user map, gooit bij fout.
  Future<Map<String, dynamic>> login(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    if (kDebugMode) debugPrint('[AUTH_DEBUG] ========== LOGIN START ==========');
    if (kDebugMode) debugPrint('[AUTH_DEBUG] email=${email.trim()}, rememberMe=$rememberMe');
    // Wis oude token vóór login – voorkomt dat getMe() oude token gebruikt
    _token = null;
    _api.setAuthToken(null);
    if (kDebugMode) debugPrint('[AUTH_DEBUG] Oude token gewist');

    final body = {'email': email.trim(), 'password': password};
    if (kDebugMode) debugPrint('[AUTH_DEBUG] POST login naar $gymiesApiBaseUrl/login');
    try {
      final res = await _api.post('login', body);
      if (kDebugMode) debugPrint('[AUTH_DEBUG] Response keys: ${res.keys.join(", ")}');

      final tokenRaw = res['token'] ?? res['access_token'] ?? res['data']?['token'] ?? res['data']?['access_token'];
      final token = tokenRaw is String ? tokenRaw.trim() : tokenRaw?.toString().trim();
      final userRaw = res['user'] ?? res['data']?['user'];
      final user = userRaw is Map<String, dynamic> ? userRaw : null;

      if (kDebugMode) debugPrint('[AUTH_DEBUG] tokenRaw type=${tokenRaw.runtimeType}');
      if (kDebugMode) debugPrint('[AUTH_DEBUG] token length=${token?.length ?? 0} (verwacht: 64 voor sessietoken)');
      if (token != null && token.isNotEmpty) {
        final hexOnly = token.replaceAll(RegExp(r'[^a-fA-F0-9]'), '');
        if (kDebugMode) debugPrint('[AUTH_DEBUG] token hex-only length=${hexOnly.length}, is64hex=${hexOnly.length == 64}');
        if (kDebugMode) debugPrint('[AUTH_DEBUG] token preview: ${token.length > 12 ? "${token.substring(0, 8)}...${token.substring(token.length - 4)}" : "***"}');
      }
      if (kDebugMode && user != null) debugPrint('[AUTH_DEBUG] user keys: ${user.keys.join(", ")}');

      if (token == null || token.isEmpty) {
        if (kDebugMode) debugPrint('[AUTH_DEBUG] FOUT: Geen token in response – server geeft geen token terug');
        throw ApiException(500, 'Geen token ontvangen van de server.');
      }
      await _persist(token, user, rememberMe: rememberMe);
      if (kDebugMode) debugPrint('[AUTH_DEBUG] Token opgeslagen in SharedPreferences, ApiClient.setAuthToken gedaan');
      if (kDebugMode) debugPrint('[AUTH_DEBUG] ========== LOGIN SUCCESS ==========');
      return user ?? {};
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[AUTH_DEBUG] ApiException: status=${e.statusCode} message=${e.message}');
      if (kDebugMode && e.body != null) debugPrint('[AUTH_DEBUG] body: ${e.body}');
      if (kDebugMode) debugPrint('[AUTH_DEBUG] ========== LOGIN FAILED ==========');
      rethrow;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AUTH_DEBUG] Error: $e');
      if (kDebugMode) debugPrint('[AUTH_DEBUG] StackTrace: $st');
      if (kDebugMode) debugPrint('[AUTH_DEBUG] ========== LOGIN FAILED ==========');
      rethrow;
    }
  }

  /// Register: retourneert user map bij direct succes.
  /// Gooit EmailVerificationRequiredException(email) als e-mailverificatie nodig is.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String role,
    String? displayName,
    String? phone,
    /// `male` of `female` — vooral voor klantregistratie.
    String? gender,
    bool newsletterSubscribe = false,
    String? referralCode,
  }) async {
    final body = <String, dynamic>{
      'email': email.trim(),
      'password': password,
      'role': role,
      'newsletter_subscribe': newsletterSubscribe,
    };
    if (displayName != null && displayName.trim().isNotEmpty) {
      body['display_name'] = displayName.trim();
    }
    if (phone != null && phone.trim().isNotEmpty) {
      body['phone'] = phone.trim();
    }
    if (gender != null && gender.trim().isNotEmpty) {
      body['gender'] = gender.trim();
    }
    if (referralCode != null && referralCode.trim().isNotEmpty) {
      body['referral_code'] = referralCode.trim();
    }
    try {
      final res = await _api.post('register', body);
      final tokenRaw = res['token'] ?? res['access_token'] ?? res['data']?['token'] ?? res['data']?['access_token'];
      final token = tokenRaw is String ? tokenRaw.trim() : tokenRaw?.toString().trim();
      final userRaw = res['user'] ?? res['data']?['user'];
      final user = userRaw is Map<String, dynamic> ? userRaw : null;
      if (token != null && token.isNotEmpty) {
        await _persist(token, user);
        return user ?? {};
      }
      throw ApiException(500, 'Registratie niet voltooid. Probeer opnieuw.');
    } on ApiException catch (e) {
      if (e.statusCode == 503) {
        final emailFromBody = e.body?['email'] as String?;
        throw EmailVerificationRequiredException(emailFromBody ?? email.trim());
      }
      if (e.statusCode == 422) {
        final reqVerify = e.body?['requires_email_verification'] == true;
        final emailFromBody = e.body?['email'] as String?;
        if (reqVerify) {
          throw EmailVerificationRequiredException(
            emailFromBody ?? email.trim(),
          );
        }
      }
      rethrow;
    }
  }

  /// Verifieer e-mail met code. Retourneert user bij succes.
  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    final res = await _api.post('auth/verify-email', {
      'email': email.trim(),
      'code': code.trim(),
    });
    final token = res['token'] as String?;
    final user = res['user'] as Map<String, dynamic>?;
    if (token == null || token.isEmpty) {
      throw ApiException(500, 'Verificatie mislukt. Controleer de code.');
    }
    await _persist(token, user);
    return user ?? {};
  }

  /// Verstuur verificatiecode opnieuw.
  Future<void> resendVerificationCode(String email) async {
    await _api.post('auth/resend-verification-code', {'email': email.trim()});
  }

  /// Vergelijkt twee API base URLs op domeinniveau (negeert www-prefix, trailing slash, pad).
  /// Zo worden tokens niet gewist bij kleine URL-variaties (www vs non-www, slash, http→https).
  bool _apiBaseUrlsMatch(String a, String b) {
    String normHost(String url) {
      try {
        final uri = Uri.tryParse(url.toLowerCase().replaceAll(RegExp(r'/+$'), ''));
        if (uri == null || uri.host.isEmpty) return url.toLowerCase();
        final host = uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
        return host;
      } catch (_) {
        return url.toLowerCase();
      }
    }
    return normHost(a) == normHost(b);
  }
}
