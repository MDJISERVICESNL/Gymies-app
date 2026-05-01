import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/app_config.dart';
import '../theme/gymies_theme.dart';

/// WebView voor Mollie Connect OAuth.
/// Onderschept gymies://mollie-connect/success en sluit met result true.
class MollieConnectWebViewScreen extends StatefulWidget {
  const MollieConnectWebViewScreen({
    super.key,
    required this.initialUrl,
  });

  final String initialUrl;

  @override
  State<MollieConnectWebViewScreen> createState() =>
      _MollieConnectWebViewScreenState();
}

class _MollieConnectWebViewScreenState extends State<MollieConnectWebViewScreen> {
  bool _loading = true;
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: GymiesColors.primary,
        title: const Text('Mollie koppelen'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  WebViewController _createController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onWebResourceError: (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Fout: ${e.description}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          onNavigationRequest: (request) {
            final url = request.url.toLowerCase();
            if (url.startsWith('gymies://mollie-connect/success')) {
              if (mounted) {
                Navigator.of(context).pop(true);
              }
              return NavigationDecision.prevent;
            }
            if (url.startsWith('gymies://')) {
              return NavigationDecision.prevent;
            }
            // Domein-allowlist: sta alleen Mollie en Gymies toe.
            // Blokkeert JS-injection als Mollie ooit redirectt naar een externe pagina.
            final uri = Uri.tryParse(request.url);
            if (uri != null && uri.host.isNotEmpty) {
              final host = uri.host.toLowerCase();
              const allowedHosts = AppConfig.mollieWebViewHosts;
              final isAllowed = allowedHosts.contains(host) ||
                  allowedHosts.any((h) => host.endsWith('.$h'));
              if (!isAllowed) {
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
    return controller;
  }
}

