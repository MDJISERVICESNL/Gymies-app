import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/generated/app_localizations.dart';
import '../config/ui_constants.dart';
import '../services/app_security_service.dart';

/// Scherm dat wordt getoond wanneer de app een security threat detecteert.
/// De gebruiker kan de app niet verder gebruiken totdat het probleem is opgelost.
class SecurityBlockedScreen extends StatelessWidget {
  const SecurityBlockedScreen({
    super.key,
    required this.result,
  });

  final SecurityCheckResult result;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: UiConstants.deepDarkBlue,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Shield icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: UiConstants.errorRed.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 56,
                    color: UiConstants.errorRed,
                  ),
                ),
                const SizedBox(height: 32),

                // Titel
                Text(
                  S.of(context).securityWarning,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sora(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Bericht
                Text(
                  result.message ?? S.of(context).erIsEenBeveiligingsprobleemGedetecteerd,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sora(
                    color: Color(0xAAFFFFFF),
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),

                // Detected threats
                if (result.threats.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0x11FFFFFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: result.threats.map((t) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: UiConstants.warningYellow, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _threatLabel(t),
                                  style: GoogleFonts.sora(
                                    color: Color(0xCCFFFFFF),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 40),

                // Informatie
                Text(
                  S.of(context).gymiesProtects,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sora(
                    color: Color(0x88FFFFFF),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                // Sluit app knop
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // Sluit de app
                      if (Platform.isAndroid) {
                        SystemNavigator.pop();
                      } else if (Platform.isIOS) {
                        exit(0);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: UiConstants.errorRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      S.of(context).closeApp,
                      style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _threatLabel(SecurityThreat threat) {
    switch (threat) {
      case SecurityThreat.rootDetected:
        return 'Root/Jailbreak gedetecteerd';
      case SecurityThreat.emulatorDetected:
        return 'Emulator gedetecteerd';
      case SecurityThreat.debuggerAttached:
        return 'Debugger verbonden';
      case SecurityThreat.tamperingDetected:
        return S.of(context).appIsGemanipuleerd;
      case SecurityThreat.hookingDetected:
        return 'Hooking framework gedetecteerd (Frida/Xposed)';
    }
  }
}
