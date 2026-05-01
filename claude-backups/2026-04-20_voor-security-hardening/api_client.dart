import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

const _kAuthViaQueryOnly = useAuthViaQueryOnly;

const int kStatusNetworkError = 0;
const Duration _kRequestTimeout = Duration(seconds: 20);
const Duration _kGetRetryDelay = Duration(milliseconds: 450);

class ApiClient {
  ApiClient({String? baseUrl})
    : _baseUrl = _validateHttpsBaseUrl(baseUrl ?? gymiesApiBaseUrl) {
    if (kDebugMode) debugPrint('[ApiClient] init – baseUrl=$_baseUrl, useAuthViaQueryOnly=$_kAuthViaQueryOnly');
  }

  final String _baseUrl;
  String? _authToken;
  void Function()? _on401;
  String? Function()? _tokenProvider;

  static String _validateHttpsBaseUrl(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      throw ApiException(
        500,
        'Onveilige API URL gedetecteerd. Gebruik een geldige https:// URL.',
      );
    }
    return parsed.toString();
  }

  String? get authToken => _authToken;

  void setAuthToken(String? token) {
    _authToken = token;
  }

  void setOn401(void Function()? cb) {
    _on401 = cb;
  }

  void setTokenProvider(String? Function()? provider) {
    _tokenProvider = provider;
  }

  void _syncTokenFromProvider() {
    if (_tokenProvider != null) {
      final t = _tokenProvider!();
      if (t != _authToken) _authToken = t;
    }
  }

  Uri _uriWithToken(String path, Map<String, String>? queryParams, String token) {
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    String p = path.trim();
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    final params = Map<String, String>.from(queryParams ?? {});
    params['access_token'] = token;
    return Uri.parse('$base/$p').replace(queryParameters: params);
  }

  Map<String, String> _headersWithToken(String token, {bool? queryOnly}) {
    final noHeaders = queryOnly ?? _kAuthViaQueryOnly;
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'GymiesApp/1.2.0 (Flutter; nl.gymies.app)',
      'X-Requested-With': 'nl.gymies.app',
      'X-App-Version': '1.2.0',
    };
    if (!noHeaders) {
      h['Authorization'] = 'Bearer $token';
      h['X-Authorization'] = 'Bearer $token';
      h['X-Gymies-Token'] = token;
      h['X-Gymies-Access-Token'] = token; // fallback voor EnsureGymiesUserFromToken
    }
    return h;
  }

  Uri _uri(String path, [Map<String, String>? queryParams]) {
    _syncTokenFromProvider();
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    String p = path.trim();
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    final params = Map<String, String>.from(queryParams ?? {});
    // Fallback: access_token in query voor wanneer Nginx/proxy Authorization header strippen
    if (_authToken != null && _authToken!.isNotEmpty) {
      params['access_token'] = _authToken!;
    }
    final uri = Uri.parse('$base/$p').replace(queryParameters: params.isEmpty ? null : params);
    if (uri.scheme != 'https') {
      throw ApiException(500, 'Onveilige verbinding geblokkeerd. Alleen HTTPS is toegestaan.');
    }
    return uri;
  }

  /// [authInHeadersOverride] – bij 401-retry: tegenovergestelde auth-strategie proberen.
  Map<String, String> _headers({bool addIdempotency = false, bool? authInHeadersOverride}) {
    _syncTokenFromProvider();
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'GymiesApp/1.2.0 (Flutter; nl.gymies.app)',
      'X-Requested-With': 'nl.gymies.app',
      'X-App-Version': '1.2.0',
    };
    final useAuthInHeaders = authInHeadersOverride ?? !_kAuthViaQueryOnly;
    if (useAuthInHeaders && _authToken != null && _authToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_authToken';
      h['X-Authorization'] = 'Bearer $_authToken';
      h['X-Gymies-Token'] = _authToken!;
      h['X-Gymies-Access-Token'] = _authToken!; // fallback voor EnsureGymiesUserFromToken
    }
    if (addIdempotency) {
      final key = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x7FFFFFFF).toRadixString(36)}';
      h['Idempotency-Key'] = key;
      h['idempotency_key'] = key;
    }
    return h;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams, String? explicitToken}) async {
    var attempts = 0;
    var last401Retry = false;
    try {
      while (true) {
        attempts += 1;
        try {
          final uri = explicitToken != null && explicitToken.isNotEmpty
              ? _uriWithToken(path, queryParams, explicitToken)
              : _uri(path, queryParams);
          // Bij 401-retry: probeer tegenovergestelde auth (query-only ↔ headers).
          final queryOnlyRetry = last401Retry ? !_kAuthViaQueryOnly : _kAuthViaQueryOnly;
          final headers = explicitToken != null && explicitToken.isNotEmpty
              ? _headersWithToken(explicitToken, queryOnly: queryOnlyRetry)
              : _headers(authInHeadersOverride: last401Retry ? _kAuthViaQueryOnly : null);
          final hasQueryToken = uri.queryParameters.containsKey('access_token');
          final hasAuthHeader = headers.containsKey('Authorization');
          if (kDebugMode) debugPrint('[AUTH_DEBUG] ApiClient GET $path | tokenInQuery=$hasQueryToken tokenInHeaders=$hasAuthHeader tokenLen=${_authToken?.length ?? 0} attempt=$attempts');
          // Gebruik redirect-handling zodat access_token in query behouden blijft bij gymies.nl→www redirect.
          final r = await _requestWithRedirectHandling('GET', uri, headers, null);
          return _handleResponse(r);
        } catch (e) {
          if (e is ApiException && e.statusCode == 401 && !last401Retry) {
            last401Retry = true;
            continue;
          }
          final wrapped = e is ApiException ? e : _wrapNetworkError(e);
          if (wrapped.statusCode != kStatusNetworkError || attempts >= 2) throw wrapped;
          await Future<void>.delayed(_kGetRetryDelay);
        }
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    }
  }

  /// Voert request uit; bij 301/302/307/308 retry naar Location metzelfde methode en body.
  /// Voorkomt 301 "Permanent Moved" waarbij standaard POST als GET wordt herhaald (body gaat verloren).
  Future<http.Response> _requestWithRedirectHandling(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body, {
    int maxRedirects = 3,
  }) async {
    var currentUri = uri;
    var attempt = 0;
    while (true) {
      attempt += 1;
      final req = http.Request(method, currentUri);
      req.headers.addAll(headers);
      if (body != null) req.body = body;
      req.followRedirects = false;
      final streamed = await req.send().timeout(_kRequestTimeout);
      final r = await http.Response.fromStream(streamed);
      final code = r.statusCode;
      if (kDebugMode && attempt == 1) {
        debugPrint('[ApiClient] Response: $code ${currentUri.toString()}');
      }
      if (code >= 200 && code < 300) return r;
      if (code == 401) return r;
      if ((code == 301 || code == 302 || code == 307 || code == 308) &&
          attempt <= maxRedirects) {
        final loc = r.headers['location'] ?? r.headers['Location'];
        if (loc != null && loc.trim().isNotEmpty) {
          var locUri = Uri.tryParse(loc.trim());
          locUri = (locUri != null && locUri.scheme.isNotEmpty)
              ? locUri
              : currentUri.resolve(loc.trim());
          // Behoud query params (access_token!) – redirect-URL bevat ze vaak niet.
          if (currentUri.queryParameters.isNotEmpty &&
              locUri.queryParameters.isEmpty) {
            locUri = locUri.replace(queryParameters: currentUri.queryParameters);
          } else if (currentUri.queryParameters.isNotEmpty) {
            final merged = Map<String, String>.from(locUri.queryParameters);
            for (final e in currentUri.queryParameters.entries) {
              if (!merged.containsKey(e.key)) merged[e.key] = e.value;
            }
            locUri = locUri.replace(queryParameters: merged);
          }
          currentUri = locUri;
          if (currentUri.scheme != 'https' && currentUri.scheme != 'http') {
            throw ApiException(
              code,
              'Ongeldige redirect. Probeer opnieuw.',
              body: _parseBodyAsMap(r.body),
            );
          }
          if (kDebugMode) {
            debugPrint('[ApiClient] Redirect $code → ${currentUri.toString()}');
          }
          continue;
        }
      }
      return r;
    }
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    try {
      final uri = _uri(path);
      final headers = _headers(addIdempotency: true);
      if (kDebugMode) debugPrint('[AUTH_DEBUG] ApiClient POST $path');
      if (kDebugMode) debugPrint('[AUTH_DEBUG]   URL: $uri');
      if (kDebugMode) debugPrint('[AUTH_DEBUG]   authToken: ${_authToken != null ? "${_authToken!.length} chars" : "null"}');
      if (kDebugMode) debugPrint('[AUTH_DEBUG]   Authorization header: ${headers.containsKey('Authorization') ? "ja" : "nee"}');
      if (path == 'login') {
        if (kDebugMode) debugPrint('[AUTH_DEBUG]   Login request – geen token nodig');
      }
      final r = await _requestWithRedirectHandling(
        'POST',
        uri,
        headers,
        jsonEncode(body),
      );
      if (kDebugMode) debugPrint('[AUTH_DEBUG] ApiClient POST response: status=${r.statusCode}, bodyLen=${r.body.length}');
      if (r.statusCode == 200 && path == 'login') {
        final parsed = _parseBodyAsMap(r.body);
        final tok = parsed['token'] ?? parsed['access_token'];
        if (tok is String) {
          if (kDebugMode) debugPrint('[AUTH_DEBUG]   Login token ontvangen: ${tok.length} chars');
        }
      }
      return _handleResponse(r);
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[AUTH_DEBUG] ApiClient ApiException: ${e.statusCode} – ${e.message}');
      if (e.statusCode == 401) {
        if (kDebugMode) debugPrint('[AUTH_DEBUG] *** 401 *** path=$path, message=${e.message}');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[AUTH_DEBUG] ApiClient Error: $e');
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    try {
      final uri = _uri(path);
      final headers = _headers(addIdempotency: true);
      final r = await _requestWithRedirectHandling(
        'PUT',
        uri,
        headers,
        jsonEncode(body),
      );
      return _handleResponse(r);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    try {
      final uri = _uri(path);
      final headers = _headers(addIdempotency: true);
      final r = await _requestWithRedirectHandling(
        'PATCH',
        uri,
        headers,
        jsonEncode(body),
      );
      return _handleResponse(r);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? body}) async {
    try {
      final uri = _uri(path);
      final headers = _headers();
      final r = await _requestWithRedirectHandling(
        'DELETE',
        uri,
        headers,
        body == null ? null : jsonEncode(body),
      );
      return _handleResponse(r);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> postMultipart(String path, {required String fileField, required Object file, Map<String, String>? fields}) async {
    try {
      _syncTokenFromProvider();
      final req = http.MultipartRequest('POST', _uri(path));
      req.headers.addAll(_headers());
      req.fields.addAll(fields ?? {});
      if (file is http.MultipartFile) {
        req.files.add(file);
      } else {
        req.files.add(await http.MultipartFile.fromPath(fileField, file.toString()));
      }
      final streamed = await req.send().timeout(_kRequestTimeout);
      final r = await http.Response.fromStream(streamed);
      return _handleResponse(r);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    }
  }

  ApiException _wrapNetworkError(Object e) {
    final msg = e is TimeoutException
        ? 'De verbinding duurde te lang. Controleer je internet en probeer opnieuw.'
        : 'Geen verbinding. Controleer je internet en probeer het later opnieuw.';
    return ApiException(kStatusNetworkError, msg);
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response r) async {
    final body = _parseBodyAsMap(r.body);
    if (r.statusCode == 401) {
      if (kDebugMode) debugPrint('[AUTH_DEBUG] *** 401 UNAUTHORIZED ***');
      if (kDebugMode) debugPrint('[AUTH_DEBUG]   message: ${body['message'] ?? "unknown"}');
      if (kDebugMode) debugPrint('[AUTH_DEBUG]   authToken: ${_authToken == null ? "NULL" : "${_authToken!.length} chars"}');
      if (_authToken != null && _authToken!.isNotEmpty) {
        final p = _authToken!.length > 12 ? '${_authToken!.substring(0, 8)}...${_authToken!.substring(_authToken!.length - 4)}' : '***';
        if (kDebugMode) debugPrint('[AUTH_DEBUG]   token preview: $p');
        final hexLen = _authToken!.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').length;
        if (kDebugMode) debugPrint('[AUTH_DEBUG]   token hex-only chars: $hexLen (middleware verwacht 64)');
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    if (r.statusCode == 401) {
      if (kDebugMode) debugPrint('[ApiClient] 401 Unauthorized – message: ${body['message'] ?? "unknown"}');
      _on401?.call();
    }
    throw ApiException(r.statusCode, _safeUserMessage(r.statusCode, body), body: body);
  }

  /// Genereert een korte foutcode voor support (bijv. #GYM-500-A7B2).
  static String generateSupportCode(int statusCode) {
    final part = (DateTime.now().microsecondsSinceEpoch % 0xFFFF).toRadixString(36).toUpperCase().padLeft(3, '0');
    return '#GYM-$statusCode-$part';
  }

  /// Detecteert of een bericht technisch/interne foutinfo bevat (niet aan gebruiker tonen).
  static bool _looksTechnical(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('sql') ||
        lower.contains('sqlstate') ||
        lower.contains('database') ||
        lower.contains('exception') ||
        lower.contains('stack trace') ||
        lower.contains('stacktrace') ||
        (lower.contains(' at ') && lower.contains('.dart')) ||
        lower.contains('pdo') ||
        lower.contains('query') && lower.contains('select') ||
        lower.contains('integrity constraint') ||
        lower.contains('foreign key') ||
        lower.contains('syntax error') ||
        // N-044 FIX: Detecteer HTML-responses en server 404-pagina's
        lower.contains('<!doctype') ||
        lower.contains('<html') ||
        lower.contains('<body') ||
        lower.contains('file not found') ||
        lower.contains('not found') && lower.contains('server') ||
        lower.contains('404 not found') ||
        lower.contains('nginx') ||
        lower.contains('apache');
  }

  String _safeUserMessage(int statusCode, Map<String, dynamic> body) {
    final raw = _extractServerMessage(body) ?? _statusFallback(statusCode);
    final msg = raw.trim().isEmpty ? _statusFallback(statusCode) : raw.trim();

    // N-044 FIX: 404 altijd fallback – server stuurt vaak rauwe HTML/tekst terug
    if (statusCode == 404) {
      if (kDebugMode) debugPrint('[ApiClient] 404 response gemaskeerd: $msg');
      return _statusFallback(404);
    }

    // Auth-fouten: vertaal generieke Engelse termen
    if (statusCode == 401 &&
        (msg.toLowerCase().contains('unauthorized') || msg.toLowerCase().contains('unauthenticated'))) {
      return 'Ongeldige of verlopen sessie. Log opnieuw in.';
    }

    // Technische fouten: toon geen serverdetails, wel foutcode voor support
    if (_looksTechnical(msg)) {
      if (kDebugMode) debugPrint('[ApiClient] Technische fout gemaskeerd: $msg');
      final code = generateSupportCode(statusCode);
      return 'Oeps, er is wat mis gegaan bij GYMIES. Gebruik deze foutcode in de help/support: $code';
    }

    return msg;
  }

  String? _extractServerMessage(Map<String, dynamic> body) {
    final m = body['message'];
    if (m is String && m.trim().isNotEmpty) return m;
    final e = body['error'];
    if (e is String && e.trim().isNotEmpty) return e;
    final err = body['errors'];
    if (err is List && err.isNotEmpty) {
      final first = err.first;
      if (first is String) return first;
      if (first is Map && first['message'] is String) return first['message'] as String;
    }
    if (err is Map && err['message'] is String) return err['message'] as String;
    return null;
  }

  String _statusFallback(int statusCode) {
    if (statusCode == 401) return 'Ongeldige of verlopen sessie. Log opnieuw in.';
    // N-044 FIX: Specifieke 404-foutmelding i.p.v. generieke tekst
    if (statusCode == 404) return 'De server kon het verzoek niet verwerken. Controleer je internetverbinding of probeer later opnieuw.';
    if (statusCode == 403) return 'Je hebt geen toegang tot deze functie.';
    if (statusCode == 422) return 'Controleer je invoer en probeer opnieuw.';
    if (statusCode == 429) return 'Te veel verzoeken. Wacht even en probeer opnieuw.';
    if (statusCode == 503) return 'De server is tijdelijk niet bereikbaar. Probeer het later opnieuw.';
    if (statusCode >= 500) return 'Er ging iets mis. Probeer het later opnieuw.';
    return 'Er ging iets mis. Probeer opnieuw.';
  }

  Map<String, dynamic> _parseBodyAsMap(String rawBody) {
    if (rawBody.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List) return {'data': decoded};
    } catch (_) {}
    return {'message': rawBody};
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.body});
  final int statusCode;
  final String message;
  final Map<String, dynamic>? body;
  @override
  String toString() => message;
}
