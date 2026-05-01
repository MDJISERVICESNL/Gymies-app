import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/ui_constants.dart';
import '../../services/connectivity_service.dart';

/// Compacte offline banner die bovenaan het scherm verschijnt.
/// Animated: schuift in/uit wanneer de connectie verandert.
///
/// Gebruik in je Scaffold body:
/// ```dart
/// Column(children: [
///   const OfflineBanner(),
///   Expanded(child: yourContent),
/// ])
/// ```
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: connectivity.isOnline ? 0 : 44,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: UiConstants.deepDarkBlue,
      ),
      child: Material(
        color: UiConstants.deepDarkBlue,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, color: UiConstants.warningYellow, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Geen internetverbinding',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.read<ConnectivityService>().checkNow(),
                child: const Text(
                  'Opnieuw',
                  style: TextStyle(
                    color: UiConstants.warningYellow,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
