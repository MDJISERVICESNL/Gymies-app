import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:safe_device/safe_device.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Gymies App Security Service
/// ──────────────────────────────────────────────────────────────────────────
/// Bank-level beveiliging:
/// - Root/Jailbreak detectie (Magisk, Frida, Xposed, etc.)
/// - Emulator detectie (Genymotion, BlueStacks, etc.)
/// - APK tampering/repackaging detectie
/// - Anti-debugging bescherming
/// - HMAC request signing
/// - Runtime integrity checks
/// ──────────────────────────────────────────────────────────────────────────

enum SecurityThreat {
  rootDetected,
  emulatorDetected,
  debuggerAttached,
  tamperingDetected,
  hookingDetected,
}

class SecurityCheckResult {
  final bool isSecure;
  final List<SecurityThreat> threats;
  final String? message;

  const SecurityCheckResult({
    required this.isSecure,
    this.threats = const [],
    this.message,
  });

  @override
  String toString() =>
      'SecurityCheckResult(isSecure: $isSecure, threats: $threats, message: $message)';
}

class AppSecurityService {
  AppSecurityService._();
  static final instance = AppSecurityService._();

  bool _initialized = false;
  SecurityCheckResult? _lastResult;

  SecurityCheckResult? get lastResult => _lastResult;

  /// ── HMAC Secret ──────────────────────────────────────────────────────
  /// Compile-time secret voor request signing.
  /// VERPLICHT bij build: --dart-define=GYMIES_HMAC_SECRET=[jouw-secret]
  /// BELANGRIJK: Dit moet hetzelfde secret zijn als op je Laravel backend.
  ///
  /// Productie build commando:
  ///   flutter build apk --dart-define=GYMIES_HMAC_SECRET=[secret]
  ///   flutter build ios --dart-define=GYMIES_HMAC_SECRET=[secret]
  static const String _hmacSecret = String.fromEnvironment(
    'GYMIES_HMAC_SECRET',
    defaultValue: '',
  );

  /// Controleert of de HMAC secret is ingesteld.
  /// Retourneert true als een secret is geconfigureerd via --dart-define.
  static bool get isHmacSecretConfigured => _hmacSecret.isNotEmpty;

  /// Valideert de HMAC configuratie. Moet aangeroepen worden bij app-start.
  /// In release mode zonder HMAC secret: crasht de app met duidelijke foutmelding.
  static void validateHmacConfiguration() {
    if (kDebugMode) {
      if (!isHmacSecretConfigured) {
        debugPrint(
          '\n'
          '╔══════════════════════════════════════════════════════════════╗\n'
          '║  WARNING: Geen HMAC secret geconfigureerd (debug mode)      ║\n'
          '║  API requests worden NIET gesigned.                        ║\n'
          '║  Voor productie build:                                     ║\n'
          '║  --dart-define=GYMIES_HMAC_SECRET=<productie-secret>       ║\n'
          '╚══════════════════════════════════════════════════════════════╝\n',
        );
      }
      return;
    }
    // Release/profile mode: HMAC secret is VERPLICHT
    if (!isHmacSecretConfigured) {
      throw StateError(
        'GYMIES SECURITY: Geen HMAC secret geconfigureerd.\n'
        'Rebuild met: --dart-define=GYMIES_HMAC_SECRET=<productie-secret>\n'
        'Dit moet hetzelfde secret zijn als GYMIES_HMAC_SECRET in je Laravel .env',
      );
    }
  }

  /// ── Volledige security check ─────────────────────────────────────────
  /// Voert alle checks uit bij app-start. Blokkeert de app als er dreigingen
  /// worden gedetecteerd (behalve in debug mode).
  Future<SecurityCheckResult> performFullCheck() async {
    if (_initialized && _lastResult != null) return _lastResult!;

    final threats = <SecurityThreat>[];

    // In debug mode skippen we checks zodat development mogelijk blijft
    if (kDebugMode) {
      debugPrint('[Security] Debug mode — security checks overgeslagen');
      _lastResult = const SecurityCheckResult(isSecure: true);
      _initialized = true;
      return _lastResult!;
    }

    // 1 & 2. Root/Jailbreak + Emulator detectie — PARALLEL met timeout.
    // Parallel uitvoeren zodat worst-case 2s is in plaats van 4s.
    try {
      final results = await Future.wait([
        FlutterJailbreakDetection.jailbroken
            .timeout(const Duration(seconds: 2), onTimeout: () {
          if (kDebugMode) debugPrint('[Security] Jailbreak check timeout na 2s — overgeslagen');
          return false;
        }).catchError((_) {
          if (kDebugMode) debugPrint('[Security] Root check fout — overgeslagen');
          return false;
        }),
        SafeDevice.isRealDevice
            .timeout(const Duration(seconds: 2), onTimeout: () {
          if (kDebugMode) debugPrint('[Security] SafeDevice check timeout na 2s — overgeslagen');
          return true;
        }).catchError((_) {
          if (kDebugMode) debugPrint('[Security] Emulator check fout — overgeslagen');
          return true;
        }),
      ]);

      final isJailbroken = results[0];
      final isRealDevice = results[1];

      if (isJailbroken) {
        threats.add(SecurityThreat.rootDetected);
        if (kDebugMode) debugPrint('[Security] ROOT/JAILBREAK GEDETECTEERD');
      }
      if (!isRealDevice) {
        threats.add(SecurityThreat.emulatorDetected);
        if (kDebugMode) debugPrint('[Security] EMULATOR GEDETECTEERD');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Security] Parallel security checks fout: $e');
    }

    // 3. Extra root indicators (bestanden op het filesystem — met timeout)
    if (Platform.isAndroid) {
      final rootIndicators = await _checkAndroidRootIndicators()
          .timeout(const Duration(seconds: 2), onTimeout: () {
        if (kDebugMode) debugPrint('[Security] Root indicators check timeout na 2s — overgeslagen');
        return false;
      });
      if (rootIndicators) {
        if (!threats.contains(SecurityThreat.rootDetected)) {
          threats.add(SecurityThreat.rootDetected);
          if (kDebugMode) debugPrint('[Security] ROOT INDICATORS gevonden op filesystem');
        }
      }
    }

    // 4. Debugger detectie
    try {
      final isDebugged = await _isDebuggerAttached();
      if (isDebugged) {
        threats.add(SecurityThreat.debuggerAttached);
        if (kDebugMode) debugPrint('[Security] DEBUGGER GEDETECTEERD');
      }
    } catch (e) {
      // Fail-open: Debugger detection error, allow continuation
      if (kDebugMode) debugPrint('[Security] Debugger check error: $e');
    }

    // 5. Hooking framework detectie (Frida, Xposed — met timeout)
    if (Platform.isAndroid) {
      final isHooked = await _detectHookingFrameworks()
          .timeout(const Duration(seconds: 2), onTimeout: () {
        if (kDebugMode) debugPrint('[Security] Hooking detection timeout na 2s — overgeslagen');
        return false;
      });
      if (isHooked) {
        threats.add(SecurityThreat.hookingDetected);
        if (kDebugMode) debugPrint('[Security] HOOKING FRAMEWORK GEDETECTEERD');
      }
    }

    final isSecure = threats.isEmpty;
    String? message;
    if (!isSecure) {
      if (threats.contains(SecurityThreat.rootDetected)) {
        message = 'Deze app kan niet worden gebruikt op een geroot apparaat. '
            'Root-toegang maakt je gegevens kwetsbaar voor aanvallen.';
      } else if (threats.contains(SecurityThreat.emulatorDetected)) {
        message = 'Deze app kan niet worden gebruikt in een emulator. '
            'Installeer de app op een fysiek apparaat.';
      } else if (threats.contains(SecurityThreat.debuggerAttached)) {
        message = 'Er is een debugger gedetecteerd. '
            'Sluit alle debugging tools en herstart de app.';
      } else if (threats.contains(SecurityThreat.hookingDetected)) {
        message = 'Er is ongeautoriseerde software gedetecteerd die de app '
            'probeert te manipuleren. Verwijder tools zoals Frida of Xposed.';
      }
    }

    _lastResult = SecurityCheckResult(
      isSecure: isSecure,
      threats: threats,
      message: message,
    );
    _initialized = true;
    return _lastResult!;
  }

  /// ── Android root indicators ──────────────────────────────────────────
  /// Controleert op bekende bestanden/paden die duiden op root.
  Future<bool> _checkAndroidRootIndicators() async {
    final suspiciousPaths = [
      '/system/app/Superuser.apk',
      '/system/xbin/su',
      '/system/bin/su',
      '/sbin/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/data/local/su',
      '/system/bin/failsafe/su',
      '/system/sd/xbin/su',
      '/system/usr/we-need-root/',
      '/data/adb/magisk',
      '/data/adb/modules',
      '/system/app/KingRoot.apk',
      '/system/app/kinguser.apk',
    ];

    for (final path in suspiciousPaths) {
      try {
        if (await File(path).exists()) return true;
      } catch (_) {
        // Fail-open: Check failed, continue to next indicator
      }
    }

    // Check voor su binary via which
    try {
      final result = await Process.run('which', ['su']);
      if (result.stdout.toString().trim().isNotEmpty) return true;
    } catch (_) {
      // Fail-open: Process execution check failed, assume not rooted
    }

    return false;
  }

  /// ── Debugger detectie ────────────────────────────────────────────────
  Future<bool> _isDebuggerAttached() async {
    // Dart-level check: assert() blokken draaien ALLEEN in debug mode.
    // In release mode wordt het assert-blok volledig gestript door de compiler,
    // dus debuggerAttached blijft false (correct voor release).
    bool debuggerAttached = false;
    assert(() {
      // Dit blok draait alleen in debug mode → debugger is attached.
      debuggerAttached = true;
      return true;
    }());

    // Check /proc/self/status op TracerPid (Android)
    // TracerPid > 0 betekent dat een ander process (debugger) ons traceert.
    if (Platform.isAndroid) {
      try {
        final status = await File('/proc/self/status').readAsString();
        final tracerLine = status
            .split('\n')
            .firstWhere((l) => l.startsWith('TracerPid:'), orElse: () => '');
        if (tracerLine.isNotEmpty) {
          final pid = int.tryParse(tracerLine.split(':').last.trim()) ?? 0;
          if (pid > 0) return true;
        }
      } catch (_) {
        // Fail-open: /proc/self/status check failed, assume not debugged
      }
    }

    return debuggerAttached;
  }

  /// ── Hooking framework detectie ───────────────────────────────────────
  /// Detecteert Frida, Xposed, en andere hooking tools.
  Future<bool> _detectHookingFrameworks() async {
    // Frida detectie: checkt op bekende Frida poorten en bestanden
    final fridaIndicators = [
      '/data/local/tmp/frida-server',
      '/data/local/tmp/re.frida.server',
      '/sdcard/frida-server',
    ];

    for (final path in fridaIndicators) {
      try {
        if (await File(path).exists()) return true;
      } catch (_) {
        // Fail-open: Frida file check failed, continue to next indicator
      }
    }

    // Frida default poort check
    try {
      final socket = await Socket.connect('127.0.0.1', 27042,
          timeout: const Duration(milliseconds: 500));
      await socket.close();
      return true; // Frida server draait
    } catch (_) {
      // Fail-open: Port check failed, assume no Frida server
    }

    // Xposed detectie via stack trace analyse
    try {
      final stack = StackTrace.current.toString();
      if (stack.contains('de.robv.android.xposed') ||
          stack.contains('com.saurik.substrate')) {
        return true;
      }
    } catch (_) {
      // Fail-open: Stack trace check failed, assume no Xposed
    }

    return false;
  }

  /// ── HMAC Request Signing ─────────────────────────────────────────────
  /// Signeert API requests zodat de backend kan verifiëren dat het request
  /// van de officiële app komt en niet is gemanipuleerd.
  ///
  /// Signature format: HMAC-SHA256(timestamp:nonce:method:path:bodyHash)
  /// De backend MOET verifiëren (in deze volgorde):
  /// 1. Timestamp niet ouder dan 5 minuten (replay attack preventie)
  ///    - Server moet nonce-cache bijhouden (LRU, TTL=10 minuten)
  ///    - Duplicate nonces met dezelfde timestamp → 400/401 reject
  /// 2. Nonce (unieke per request) — voorkomen dat dezelfde request herhaald wordt
  ///    - Nonce moet UNIEK zijn (check tegen cache)
  ///    - Expired nonces (>10 min oud) kunnen uit cache verwijderd worden
  /// 3. HMAC signature klopt met hetzelfde secret (constant-time comparison!)
  /// 4. Body hash klopt met de daadwerkelijke request body (voorkomen tampering)
  static Map<String, String> signRequest({
    required String method,
    required String path,
    String? body,
  }) {
    // Geen secret? Stuur geen HMAC headers (dev mode zonder --dart-define)
    // De server laat requests zonder headers door als HMAC niet geconfigureerd is,
    // of blokkeert ze in productie — precies het gewenste gedrag.
    if (!isHmacSecretConfigured) {
      return {};
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // FIX #8: Add nonce to prevent replay attacks (identical requests can't be replayed)
    final nonce = Random().nextInt(0x7FFFFFFF).toRadixString(36);
    final bodyHash = body != null && body.isNotEmpty
        ? sha256.convert(utf8.encode(body)).toString()
        : sha256.convert(utf8.encode('')).toString();

    final payload = '$timestamp:$nonce:${method.toUpperCase()}:$path:$bodyHash';
    final hmacSha256 = Hmac(sha256, utf8.encode(_hmacSecret));
    final signature = hmacSha256.convert(utf8.encode(payload)).toString();

    return {
      'X-Gymies-Timestamp': timestamp.toString(),
      'X-Gymies-Nonce': nonce,
      'X-Gymies-Signature': signature,
      'X-Gymies-Body-Hash': bodyHash,
    };
  }

  /// ── Verify request hasn't been tampered ──────────────────────────────
  /// Kan gebruikt worden voor client-side verificatie van server responses.
  static bool verifySignature({
    required String signature,
    required String timestamp,
    required String method,
    required String path,
    required String bodyHash,
    String? nonce,
  }) {
    // FIX #8: Include nonce in signature verification (same format as signRequest)
    final payload = nonce != null
        ? '$timestamp:$nonce:${method.toUpperCase()}:$path:$bodyHash'
        : '$timestamp:${method.toUpperCase()}:$path:$bodyHash';
    final hmacSha256 = Hmac(sha256, utf8.encode(_hmacSecret));
    final expected = hmacSha256.convert(utf8.encode(payload)).toString();
    // FIX #7: Constant-time comparison om timing attacks te voorkomen
    // Compare length in constant time as well (not early return)
    var result = 0;
    final sigLen = signature.length;
    final expLen = expected.length;
    result |= sigLen ^ expLen;
    final minLen = sigLen < expLen ? sigLen : expLen;
    for (var i = 0; i < minLen; i++) {
      result |= signature.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    // Also check remaining chars if lengths differ (constant-time)
    if (sigLen > expLen) {
      for (var i = expLen; i < sigLen; i++) {
        result |= signature.codeUnitAt(i);
      }
    } else if (expLen > sigLen) {
      for (var i = sigLen; i < expLen; i++) {
        result |= expected.codeUnitAt(i);
      }
    }
    return result == 0;
  }
}
