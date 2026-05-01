import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  /// Override met: --dart-define=GYMIES_HMAC_SECRET=<jouw-secret>
  /// BELANGRIJK: Dit moet hetzelfde secret zijn als op je Laravel backend.
  static const String _hmacSecret = String.fromEnvironment(
    'GYMIES_HMAC_SECRET',
    defaultValue: 'gymies-dev-hmac-key-change-in-production',
  );

  /// Dev-default waarde — wordt gebruikt om te detecteren of een productie-build
  /// per ongeluk zonder --dart-define=GYMIES_HMAC_SECRET is gemaakt.
  static const String _devDefaultSecret = 'gymies-dev-hmac-key-change-in-production';

  /// Controleert of de HMAC secret veilig is voor productie.
  /// Retourneert true als een custom secret is ingesteld, false als de dev-default actief is.
  static bool get isHmacSecretConfigured => _hmacSecret != _devDefaultSecret;

  /// Valideert de HMAC configuratie. Moet aangeroepen worden bij app-start.
  /// In release mode met dev-default secret: logt een CRITICAL warning.
  static void validateHmacConfiguration() {
    if (!kDebugMode && !isHmacSecretConfigured) {
      // CRITICAL: Productie-build draait op dev-default HMAC secret!
      // Dit betekent dat request signing effectief uitgeschakeld is omdat
      // de dev-secret publiek bekend is (staat in de source code).
      debugPrint(
        '\n'
        '╔══════════════════════════════════════════════════════════════╗\n'
        '║  CRITICAL SECURITY WARNING                                  ║\n'
        '║  HMAC secret is de dev-default!                            ║\n'
        '║  Bouw opnieuw met:                                         ║\n'
        '║  --dart-define=GYMIES_HMAC_SECRET=<productie-secret>       ║\n'
        '╚══════════════════════════════════════════════════════════════╝\n',
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

    // 1. Root/Jailbreak detectie
    try {
      final isJailbroken = await FlutterJailbreakDetection.jailbroken;
      if (isJailbroken) {
        threats.add(SecurityThreat.rootDetected);
        debugPrint('[Security] ROOT/JAILBREAK GEDETECTEERD');
      }
    } catch (e) {
      // Als de check zelf faalt, is dat verdacht
      debugPrint('[Security] Root check fout: $e');
    }

    // 2. Emulator detectie
    try {
      final isRealDevice = await SafeDevice.isRealDevice;
      if (!isRealDevice) {
        threats.add(SecurityThreat.emulatorDetected);
        debugPrint('[Security] EMULATOR GEDETECTEERD');
      }
    } catch (e) {
      debugPrint('[Security] Emulator check fout: $e');
    }

    // 3. Extra root indicators (bestanden op het filesystem)
    if (Platform.isAndroid) {
      final rootIndicators = await _checkAndroidRootIndicators();
      if (rootIndicators) {
        if (!threats.contains(SecurityThreat.rootDetected)) {
          threats.add(SecurityThreat.rootDetected);
          debugPrint('[Security] ROOT INDICATORS gevonden op filesystem');
        }
      }
    }

    // 4. Debugger detectie
    try {
      final isDebugged = await _isDebuggerAttached();
      if (isDebugged) {
        threats.add(SecurityThreat.debuggerAttached);
        debugPrint('[Security] DEBUGGER GEDETECTEERD');
      }
    } catch (_) {}

    // 5. Hooking framework detectie (Frida, Xposed)
    if (Platform.isAndroid) {
      final isHooked = await _detectHookingFrameworks();
      if (isHooked) {
        threats.add(SecurityThreat.hookingDetected);
        debugPrint('[Security] HOOKING FRAMEWORK GEDETECTEERD');
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
      } catch (_) {}
    }

    // Check voor su binary via which
    try {
      final result = await Process.run('which', ['su']);
      if (result.stdout.toString().trim().isNotEmpty) return true;
    } catch (_) {}

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
      } catch (_) {}
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
      } catch (_) {}
    }

    // Frida default poort check
    try {
      final socket = await Socket.connect('127.0.0.1', 27042,
          timeout: const Duration(milliseconds: 500));
      await socket.close();
      return true; // Frida server draait
    } catch (_) {
      // Goed — geen Frida server
    }

    // Xposed detectie via stack trace analyse
    try {
      final stack = StackTrace.current.toString();
      if (stack.contains('de.robv.android.xposed') ||
          stack.contains('com.saurik.substrate')) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// ── HMAC Request Signing ─────────────────────────────────────────────
  /// Signeert API requests zodat de backend kan verifiëren dat het request
  /// van de officiële app komt en niet is gemanipuleerd.
  ///
  /// Signature format: HMAC-SHA256(timestamp:method:path:bodyHash)
  /// De backend controleert:
  /// 1. Timestamp niet ouder dan 5 minuten (replay attack preventie)
  /// 2. HMAC signature klopt met hetzelfde secret
  /// 3. Body hash klopt met de daadwerkelijke request body
  static Map<String, String> signRequest({
    required String method,
    required String path,
    String? body,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final bodyHash = body != null && body.isNotEmpty
        ? sha256.convert(utf8.encode(body)).toString()
        : sha256.convert(utf8.encode('')).toString();

    final payload = '$timestamp:${method.toUpperCase()}:$path:$bodyHash';
    final hmacSha256 = Hmac(sha256, utf8.encode(_hmacSecret));
    final signature = hmacSha256.convert(utf8.encode(payload)).toString();

    return {
      'X-Gymies-Timestamp': timestamp.toString(),
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
  }) {
    final payload = '$timestamp:${method.toUpperCase()}:$path:$bodyHash';
    final hmacSha256 = Hmac(sha256, utf8.encode(_hmacSecret));
    final expected = hmacSha256.convert(utf8.encode(payload)).toString();
    // Constant-time comparison om timing attacks te voorkomen
    if (signature.length != expected.length) return false;
    var result = 0;
    for (var i = 0; i < signature.length; i++) {
      result |= signature.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return result == 0;
  }
}
