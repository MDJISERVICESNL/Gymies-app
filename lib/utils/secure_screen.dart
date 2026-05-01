import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Blokkeert screenshots en screen recording op gevoelige schermen.
/// Werkt op Android via FLAG_SECURE, op iOS via screenshot notification.
///
/// Gebruik:
/// ```dart
/// @override
/// void initState() {
///   super.initState();
///   SecureScreen.enable();
/// }
///
/// @override
/// void dispose() {
///   SecureScreen.disable();
///   super.dispose();
/// }
/// ```
///
/// Of gebruik de [SecureScreenWrapper] widget voor automatisch lifecycle management.
class SecureScreen {
  static const _channel = MethodChannel('com.Gymies.nl/secure_screen');

  /// Activeert FLAG_SECURE — blokkeert screenshots en screen recording.
  static Future<void> enable() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('enableSecure');
      } catch (_) {
        // Fallback: als de native channel niet bestaat, geen crash
      }
    }
  }

  /// Deactiveert FLAG_SECURE — staat screenshots weer toe.
  static Future<void> disable() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('disableSecure');
      } catch (_) {}
    }
  }
}

/// Widget die automatisch FLAG_SECURE aan/uit zet op basis van lifecycle.
/// Wrap gevoelige schermen hiermee:
///
/// ```dart
/// SecureScreenWrapper(
///   child: PaymentScreen(),
/// )
/// ```
class SecureScreenWrapper extends StatefulWidget {
  const SecureScreenWrapper({super.key, required this.child});

  final Widget child;

  @override
  State<SecureScreenWrapper> createState() => _SecureScreenWrapperState();
}

class _SecureScreenWrapperState extends State<SecureScreenWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SecureScreen.enable();
  }

  @override
  void dispose() {
    SecureScreen.disable();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Heractiveer FLAG_SECURE wanneer app terugkomt van background
    if (state == AppLifecycleState.resumed) {
      SecureScreen.enable();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
