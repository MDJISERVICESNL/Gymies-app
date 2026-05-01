import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import 'api_client.dart';

/// Force Update Service
/// ────────────────────
/// Controleert bij app startup of de huidige versie nog ondersteund wordt.
/// Als de backend een hogere min_version vereist, toont een blokkerende dialog.
///
/// Gebruik in LoadingScreen of na auth init:
/// ```dart
/// await ForceUpdateService.checkAndBlock(context, apiClient);
/// ```
class ForceUpdateService {
  ForceUpdateService._();

  /// Controleert de app versie tegen de backend. Toont een blokkerende dialog als update nodig is.
  /// Retourneert true als de app mag doorgaan, false als geblokkeerd.
  static Future<bool> checkAndBlock(BuildContext context, ApiClient api) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version; // e.g. "1.2.1"
      final platform = Platform.isIOS ? 'ios' : 'android';

      final response = await api.get(
        'app-version',
        queryParams: {
          'version': currentVersion,
          'platform': platform,
        },
      );

      final forceUpdate = response['force_update'] == true;
      if (!forceUpdate) return true; // Alles OK, app mag doorgaan

      // Blokkerende dialog tonen
      if (!context.mounted) return false;

      final message = response['message'] as String? ??
          'Er is een belangrijke update beschikbaar. Werk de app bij om door te gaan.';
      final updateUrl = Platform.isIOS
          ? (response['update_url_ios'] as String? ?? 'https://apps.apple.com/app/gymies/id${AppConfig.iosAppStoreId}')
          : (response['update_url_android'] as String? ?? 'https://play.google.com/store/apps/details?id=com.gymies.app');

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Update vereist'),
            content: Text(message),
            actions: [
              FilledButton(
                onPressed: () {
                  final uri = Uri.tryParse(updateUrl);
                  if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text('Update nu'),
              ),
            ],
          ),
        ),
      );

      return false; // Dialog getoond, app is geblokkeerd
    } catch (e) {
      // Bij netwerk-fout of als endpoint niet bestaat: app gewoon doorlaten.
      // Force-update check mag de app nooit breken.
      if (kDebugMode) debugPrint('[ForceUpdate] Check mislukt (app doorgaan): $e');
      return true;
    }
  }
}
