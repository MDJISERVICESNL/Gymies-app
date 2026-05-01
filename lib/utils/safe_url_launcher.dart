import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Veilige URL launcher met domein-whitelist voor betalingen.
///
/// Voorkomt phishing-aanvallen via gemanipuleerde payment_url responses.
/// Alleen bekende domeinen (Mollie, Gymies, iDEAL) worden direct geopend.
/// Onbekende domeinen tonen een waarschuwing aan de gebruiker.
class SafeUrlLauncher {
  SafeUrlLauncher._();

  /// Vertrouwde domeinen voor betalingen.
  static const _trustedPaymentDomains = <String>{
    // Mollie
    'mollie.com',
    'www.mollie.com',
    'checkout.mollie.com',
    'pay.mollie.com',
    // Gymies
    'gymies.nl',
    'www.gymies.nl',
    'api.gymies.nl',
    // iDEAL / banken
    'ideal.nl',
    'www.ideal.nl',
    'abnamro.nl',
    'ing.nl',
    'rabobank.nl',
    'bunq.com',
    'knab.nl',
    'sns.nl',
    'asn.nl',
    'regiobank.nl',
    'triodos.nl',
    'revolut.com',
    // Apple/Google Maps (voor locatie links)
    'maps.apple.com',
    'maps.google.com',
    'www.google.com',
    'goo.gl',
    // Stripe (mocht je migreren)
    'checkout.stripe.com',
    'pay.stripe.com',
  };

  /// Controleert of een URL-domein vertrouwd is.
  static bool isTrustedDomain(Uri uri) {
    if (uri.scheme != 'https') return false; // Nooit HTTP voor betalingen

    final host = uri.host.toLowerCase();
    for (final domain in _trustedPaymentDomains) {
      if (host == domain || host.endsWith('.$domain')) return true;
    }
    return false;
  }

  /// Opent een payment URL veilig.
  ///
  /// - HTTPS verplicht
  /// - Domein moet in whitelist staan
  /// - Bij onbekend domein: toon waarschuwing dialog
  ///
  /// Returns true als de URL succesvol geopend is.
  static Future<bool> launchPaymentUrl(
    BuildContext context,
    String url, {
    String? label,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showError(context, 'Ongeldige URL ontvangen.');
      return false;
    }

    // Blokkeer HTTP — alleen HTTPS voor betalingen
    if (uri.scheme != 'https') {
      _showError(context, 'Onveilige verbinding (geen HTTPS). Betaling geannuleerd.');
      return false;
    }

    // Check whitelist
    if (isTrustedDomain(uri)) {
      return _doLaunch(uri);
    }

    // Onbekend domein → vraag bevestiging
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Onbekend domein'),
        content: Text(
          'Je wordt doorgestuurd naar ${uri.host}.\n\n'
          'Dit domein staat niet in onze vertrouwde lijst. '
          'Weet je zeker dat je wilt doorgaan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Toch openen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      return _doLaunch(uri);
    }
    return false;
  }

  /// Opent een algemene URL (niet-payment). Minder strikt.
  /// Blokkeert alleen non-HTTP(S) schemes.
  static Future<bool> launchSafeUrl(
    BuildContext context,
    String url,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showError(context, 'Ongeldige URL.');
      return false;
    }

    if (uri.scheme != 'https' && uri.scheme != 'http') {
      _showError(context, 'Ongeldig URL-type.');
      return false;
    }

    return _doLaunch(uri);
  }

  static Future<bool> _doLaunch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (kDebugMode) debugPrint('[SafeUrlLauncher] Launch fout: $e');
      return false;
    }
  }

  static void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }
}
