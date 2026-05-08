import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/timing_constants.dart';
import 'api_config.dart';
import 'app_security_service.dart';

const _kAuthViaQueryOnly = useAuthViaQueryOnly;

const int kStatusNetworkError = 0;
const Duration _kRequestTimeout = TimingConstants.apiRequestTimeout;
const Duration _kGetRetryDelay = TimingConstants.getRetryDelay;
const String _kAppVersion = TimingConstants.appVersion;

class ApiClient {
  ApiClient({String? baseUrl})
    : _baseUrl = _validateHttpsBaseUrl(baseUrl ?? gymiesApiBaseUrl) {
    if (kDebugMode) debugPrint('[ApiClient] init – baseUrl=$_baseUrl, useAuthViaQueryOnly=$_kAuthViaQueryOnly');
  }

  final String _baseUrl;
  String? _authToken;
  void Function()? _on401;
  String? Function()? _tokenProvider;
  bool _handling401 = false;
  final _tokenSyncLock = Object(); // Thread-safe token synchronization

  /// FIX #7: Reset 401 handler state so multiple 401s can trigger logout
  /// Call this when re-authenticating or when token is set again.
  void resetUnauthorizedHandler() {
    _handling401 = false;
  }

  /// In-flight mutation guard: voorkom dubbele POST/PUT/PATCH/DELETE requests
  /// bij snel dubbeltikken. Blokkeert alleen als exact hetzelfde method+path
  /// nog bezig is. Zodra het request klaar is (succes of fout), is retry direct
  /// mogelijk — geen valse 429 na een gefaald request.
  final Set<String> _inFlightMutations = {};

  /// In-flight GET request guard: voorkom dubbele GET requests naar dezelfde
  /// endpoint bij snelle scrolling (bijv. paginated lists, autocomplete).
  /// Elke GET naar /trainers/search?q=john wordt slechts eenmaal tegelijk afgevuurd.
  final Map<String, Future<Map<String, dynamic>>> _inFlightGets = {};

  /// Retourneert true als deze mutatie al in-flight is (duplicaat blokkeren).
  bool _isInFlight(String method, String path) {
    final key = '$method:$path';
    if (_inFlightMutations.contains(key)) {
      if (kDebugMode) debugPrint('[ApiClient] In-flight guard: $key wordt al verwerkt');
      return true;
    }
    return false;
  }

  /// Markeer een mutatie als gestart.
  void _markInFlight(String method, String path) {
    _inFlightMutations.add('$method:$path');
  }

  /// Markeer een mutatie als afgerond (succes of fout).
  void _clearInFlight(String method, String path) {
    _inFlightMutations.remove('$method:$path');
  }

  static String _validateHttpsBaseUrl(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null || parsed.host.isEmpty) {
      throw ApiException(
        500,
        'Ongeldige API URL gedetecteerd. Zorg voor een geldige URL met host.',
      );
    }
    // Allow HTTP only for localhost development (not for production domains)
    if (parsed.scheme != 'https' && !parsed.host.startsWith('localhost') && parsed.host != '127.0.0.1') {
      throw ApiException(
        500,
        'Onveilige API URL gedetecteerd. Gebruik https:// voor productie domeinen.',
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
    // CRITICAL: Synchronize token provider reads to prevent race conditions
    // during concurrent requests that might trigger simultaneous token updates.
    synchronized(_tokenSyncLock, () {
      if (_tokenProvider != null) {
        final t = _tokenProvider!();
        if (t != _authToken) _authToken = t;
      }
    });
  }

  /// Synchronization helper: prevent race conditions on shared mutable state.
  /// NOTE: This is a placeholder. Dart is single-threaded (event-loop based),
  /// so true lock-free synchronization isn't needed. However, for clarity and
  /// future-proofing (if migrating to isolates), we document synchronization points.
  /// Real synchronization should use Mutex from the synchronized_lite package
  /// if isolate-based concurrency is added later.
  static void synchronized(Object lock, void Function() fn) {
    fn();
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

  Map<String, String> _headersWithToken(String token, {bool? queryOnly, String method = 'GET', String path = ''}) {
    final noHeaders = queryOnly ?? _kAuthViaQueryOnly;
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'GymiesApp/$_kAppVersion (Flutter; com.Gymies.nl)',
      'X-Requested-With': 'com.Gymies.nl',
      'X-App-Version': _kAppVersion,
    };
    if (!noHeaders) {
      h['Authorization'] = 'Bearer $token';
      h['X-Authorization'] = 'Bearer $token';
      h['X-Gymies-Token'] = token;
      h['X-Gymies-Access-Token'] = token; // fallback voor EnsureGymiesUserFromToken
    }
    // HMAC Request Signing — consistent met _headers()
    h.addAll(AppSecurityService.signRequest(
      method: method,
      path: path,
      body: null,
    ));
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
  /// [method] en [path] worden gebruikt voor HMAC request signing.
  /// [body] wordt gehashed voor de signature.
  /// FIX-AUD-001: Ensure request headers never contain expired token or stale auth state
  Map<String, String> _headers({
    bool addIdempotency = false,
    bool? authInHeadersOverride,
    String method = 'GET',
    String path = '',
    String? body,
  }) {
    _syncTokenFromProvider();
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'GymiesApp/$_kAppVersion (Flutter; com.Gymies.nl)',
      'X-Requested-With': 'com.Gymies.nl',
      'X-App-Version': _kAppVersion,
    };
    final useAuthInHeaders = authInHeadersOverride ?? !_kAuthViaQueryOnly;
    // FIX-AUD-001: Double-check token is still valid before adding to headers
    // Prevent stale token being sent if it was cleared by concurrent 401 handler
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
    // HMAC Request Signing — voorkomt request tampering en replay attacks
    h.addAll(AppSecurityService.signRequest(
      method: method,
      path: path,
      body: body,
    ));
    return h;
  }

  /// Maximaal aantal retry-pogingen voor GET requests (401 auth-switch + network error).
  static const int _kMaxGetAttempts = 3;

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams, String? explicitToken}) async {
    // FIX: In-flight GET deduplication — prevent duplicate requests on fast scrolling
    final cacheKey = '$path?${queryParams?.entries.map((e) => '${e.key}=${e.value}').join('&') ?? ''}';
    if (_inFlightGets.containsKey(cacheKey)) {
      if (kDebugMode) debugPrint('[ApiClient] Deduplicating GET $path (in-flight)');
      return _inFlightGets[cacheKey]!;
    }

    // Create the actual request future
    final requestFuture = _performGet(path, queryParams: queryParams, explicitToken: explicitToken);

    // Store it to deduplicate concurrent calls
    _inFlightGets[cacheKey] = requestFuture;

    try {
      final result = await requestFuture;
      return result;
    } finally {
      // Clean up the cache entry
      _inFlightGets.remove(cacheKey);
    }
  }

  /// Performs the actual GET request with retry logic.
  /// FIX-AUD-003: Enhanced retry logic with token expiry detection
  Future<Map<String, dynamic>> _performGet(String path, {Map<String, String>? queryParams, String? explicitToken}) async {
    var attempts = 0;
    var last401Retry = false;
    try {
      while (attempts < _kMaxGetAttempts) {
        attempts += 1;
        try {
          final uri = explicitToken != null && explicitToken.isNotEmpty
              ? _uriWithToken(path, queryParams, explicitToken)
              : _uri(path, queryParams);
          // Bij 401-retry: probeer tegenovergestelde auth (query-only ↔ headers).
          final queryOnlyRetry = last401Retry ? !_kAuthViaQueryOnly : _kAuthViaQueryOnly;
          final headers = explicitToken != null && explicitToken.isNotEmpty
              ? _headersWithToken(explicitToken, queryOnly: queryOnlyRetry, method: 'GET', path: path)
              : _headers(authInHeadersOverride: last401Retry ? _kAuthViaQueryOnly : null);
          final hasQueryToken = uri.queryParameters.containsKey('access_token');
          final hasAuthHeader = headers.containsKey('Authorization');
          if (kDebugMode) debugPrint('[AUTH_DEBUG] ApiClient GET $path | tokenInQuery=$hasQueryToken tokenInHeaders=$hasAuthHeader tokenLen=${_authToken?.length ?? 0} attempt=$attempts/$_kMaxGetAttempts');
          // Gebruik redirect-handling zodat access_token in query behouden blijft bij gymies.nl→www redirect.
          final r = await _requestWithRedirectHandling('GET', uri, headers, null);
          return _handleResponse(r);
        } catch (e) {
          if (e is ApiException && e.statusCode == 401 && !last401Retry && _authToken != null) {
            // FIX-AUD-003: On 401, check if token was cleared by concurrent handler
            // If token is now null, don't retry — let 401 propagate to trigger login screen
            if (_authToken == null || _authToken!.isEmpty) {
              throw e; // Token cleared by 401 handler, don't retry
            }
            last401Retry = true;
            continue;
          }
          final wrapped = e is ApiException ? e : _wrapNetworkError(e);
          // Bij network errors: retry tot max attempts. Bij andere errors: direct gooien.
          if (wrapped.statusCode != kStatusNetworkError || attempts >= _kMaxGetAttempts) throw wrapped;
          await Future<void>.delayed(_kGetRetryDelay);
        }
      }
      // Vangnet: als while-conditie bereikt wordt zonder return/throw (zou niet moeten).
      throw _wrapNetworkError(Exception('Max retry attempts ($_kMaxGetAttempts) bereikt voor GET $path'));
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
      final r = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 30));
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
          // Behoud query params alleen bij same-origin redirect.
          // Voorkom dat access_token/auth tokens lekken naar externe domeinen.
          final sameOrigin = locUri.host == currentUri.host ||
              locUri.host.endsWith('.${currentUri.host}');
          if (sameOrigin && currentUri.queryParameters.isNotEmpty) {
            // Strip gevoelige auth params bij twijfel — alleen niet-auth params meenemen.
            final safeParams = Map<String, String>.from(
              locUri.queryParameters,
            );
            for (final e in currentUri.queryParameters.entries) {
              if (!safeParams.containsKey(e.key)) {
                safeParams[e.key] = e.value;
              }
            }
            locUri = locUri.replace(queryParameters: safeParams);
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
    if (_isInFlight('POST', path)) {
      throw ApiException(429, 'Even geduld — verzoek wordt al verwerkt.');
    }
    _markInFlight('POST', path);
    try {
      var last401Retry = false;
      var attempts = 0;
      while (attempts < 2) {
        attempts += 1;
        try {
          final uri = _uri(path);
          // CRITICAL: ALWAYS add idempotency to POST — prevents duplicate processing on retry
          final headers = _headers(addIdempotency: true, authInHeadersOverride: last401Retry ? _kAuthViaQueryOnly : null);
          if (kDebugMode) debugPrint('[AUTH_DEBUG] ApiClient POST $path');
          if (kDebugMode) debugPrint('[AUTH_DEBUG]   URL: $uri');
          if (kDebugMode) debugPrint('[AUTH_DEBUG]   authToken: ${_authToken != null ? "${_authToken!.length} chars" : "null"}');
          if (kDebugMode) debugPrint('[AUTH_DEBUG]   Authorization header: ${headers.containsKey('Authorization') ? "ja" : "nee"}');
          if (kDebugMode) debugPrint('[AUTH_DEBUG]   Idempotency-Key: ${headers.containsKey('Idempotency-Key') ? "ja" : "nee"}');
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
        } catch (e) {
          // FIX-AUD-003: Check if token was cleared by concurrent 401 handler
          if (e is ApiException && e.statusCode == 401 && !last401Retry && _authToken != null) {
            // FIX-AUD-003: Verify token still exists before retrying
            if (_authToken == null || _authToken!.isEmpty) {
              throw e; // Token cleared by 401 handler, don't retry
            }
            last401Retry = true;
            continue;
          }
          if (e is ApiException) {
            if (kDebugMode) debugPrint('[AUTH_DEBUG] ApiClient ApiException: ${e.statusCode} – ${e.message}');
            if (e.statusCode == 401) {
              if (kDebugMode) debugPrint('[AUTH_DEBUG] *** 401 *** path=$path, message=${e.message}');
            }
          }
          rethrow;
        }
      }
      throw ApiException(500, 'POST request failed after retries');
    } catch (e) {
      if (kDebugMode) debugPrint('[AUTH_DEBUG] ApiClient Error: $e');
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    } finally {
      _clearInFlight('POST', path);
    }
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    if (_isInFlight('PUT', path)) {
      throw ApiException(429, 'Even geduld — verzoek wordt al verwerkt.');
    }
    _markInFlight('PUT', path);
    try {
      var last401Retry = false;
      var attempts = 0;
      while (attempts < 2) {
        attempts += 1;
        try {
          final uri = _uri(path);
          final headers = _headers(addIdempotency: true, authInHeadersOverride: last401Retry ? _kAuthViaQueryOnly : null);
          final r = await _requestWithRedirectHandling(
            'PUT',
            uri,
            headers,
            jsonEncode(body),
          );
          return _handleResponse(r);
        } catch (e) {
          // FIX-AUD-003: Check if token was cleared by concurrent 401 handler
          if (e is ApiException && e.statusCode == 401 && !last401Retry && _authToken != null) {
            // FIX-AUD-003: Verify token still exists before retrying
            if (_authToken == null || _authToken!.isEmpty) {
              throw e; // Token cleared by 401 handler, don't retry
            }
            last401Retry = true;
            continue;
          }
          rethrow;
        }
      }
      throw ApiException(500, 'PUT request failed after retries');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    } finally {
      _clearInFlight('PUT', path);
    }
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    if (_isInFlight('PATCH', path)) {
      throw ApiException(429, 'Even geduld — verzoek wordt al verwerkt.');
    }
    _markInFlight('PATCH', path);
    try {
      var last401Retry = false;
      var attempts = 0;
      while (attempts < 2) {
        attempts += 1;
        try {
          final uri = _uri(path);
          final headers = _headers(addIdempotency: true, authInHeadersOverride: last401Retry ? _kAuthViaQueryOnly : null);
          final r = await _requestWithRedirectHandling(
            'PATCH',
            uri,
            headers,
            jsonEncode(body),
          );
          return _handleResponse(r);
        } catch (e) {
          // FIX-AUD-003: Check if token was cleared by concurrent 401 handler
          if (e is ApiException && e.statusCode == 401 && !last401Retry && _authToken != null) {
            // FIX-AUD-003: Verify token still exists before retrying
            if (_authToken == null || _authToken!.isEmpty) {
              throw e; // Token cleared by 401 handler, don't retry
            }
            last401Retry = true;
            continue;
          }
          rethrow;
        }
      }
      throw ApiException(500, 'PATCH request failed after retries');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    } finally {
      _clearInFlight('PATCH', path);
    }
  }

  Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? body}) async {
    if (_isInFlight('DELETE', path)) {
      throw ApiException(429, 'Even geduld — verzoek wordt al verwerkt.');
    }
    _markInFlight('DELETE', path);
    try {
      var last401Retry = false;
      var attempts = 0;
      while (attempts < 2) {
        attempts += 1;
        try {
          final uri = _uri(path);
          // FIX #4: Add idempotency key to DELETE (like POST/PUT/PATCH)
          final headers = _headers(addIdempotency: true, authInHeadersOverride: last401Retry ? _kAuthViaQueryOnly : null);
          final r = await _requestWithRedirectHandling(
            'DELETE',
            uri,
            headers,
            body == null ? null : jsonEncode(body),
          );
          return _handleResponse(r);
        } catch (e) {
          // FIX-AUD-003: Check if token was cleared by concurrent 401 handler
          if (e is ApiException && e.statusCode == 401 && !last401Retry && _authToken != null) {
            // FIX-AUD-003: Verify token still exists before retrying
            if (_authToken == null || _authToken!.isEmpty) {
              throw e; // Token cleared by 401 handler, don't retry
            }
            last401Retry = true;
            continue;
          }
          rethrow;
        }
      }
      throw ApiException(500, 'DELETE request failed after retries');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    } finally {
      _clearInFlight('DELETE', path);
    }
  }

  /// GET request die raw bytes teruggeeft (voor PDF/binary downloads).
  /// Gooit [ApiException] bij niet-2xx status.
  Future<Uint8List> getBytes(String path, {Map<String, String>? queryParams}) async {
    _syncTokenFromProvider();
    final uri = _uri(path, queryParams);
    final headers = _headers(method: 'GET', path: path);
    try {
      final r = await _requestWithRedirectHandling('GET', uri, headers, null);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        return r.bodyBytes;
      }
      final body = _parseBodyAsMap(r.body);
      throw ApiException(r.statusCode, body['message']?.toString() ?? 'Download mislukt (${r.statusCode}).');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> postMultipart(String path, {required String fileField, required Object file, Map<String, String>? fields}) async {
    // FIX #5: Add in-flight guard and idempotency to prevent duplicate uploads
    if (_isInFlight('POST_MULTIPART', path)) {
      throw ApiException(429, 'Even geduld — verzoek wordt al verwerkt.');
    }
    _markInFlight('POST_MULTIPART', path);
    try {
      _syncTokenFromProvider();
      final req = http.MultipartRequest('POST', _uri(path));
      req.headers.addAll(_headers(addIdempotency: true));
      req.fields.addAll(fields ?? {});
      if (file is http.MultipartFile) {
        req.files.add(file);
      } else {
        req.files.add(await http.MultipartFile.fromPath(fileField, file.toString()));
      }
      final streamed = await req.send().timeout(_kRequestTimeout);
      final r = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 30));
      return _handleResponse(r);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw _wrapNetworkError(e);
    } finally {
      _clearInFlight('POST_MULTIPART', path);
    }
  }

  ApiException _wrapNetworkError(Object e) {
    // FIX #6: Properly categorize network errors
    late String msg;
    if (e is TimeoutException) {
      msg = 'De verbinding duurde te lang. Controleer je internet en probeer opnieuw.';
    } else if (e is SocketException) {
      // FIX #6a: SocketException = network unavailable, DNS failure, etc.
      if (e.message.toLowerCase().contains('failed host lookup')) {
        msg = 'Kan server niet bereiken. Controleer je internetverbinding.';
      } else if (e.message.toLowerCase().contains('connection refused')) {
        msg = 'Server weigert verbinding. Probeer het later opnieuw.';
      } else {
        msg = 'Netwerkfout. Controleer je internetverbinding en probeer opnieuw.';
      }
    } else if (e is HandshakeException) {
      // FIX #6b: Explicit SSL/TLS error handling
      msg = 'Beveiligingsfout bij verbinding. Dit kan duiden op man-in-the-middle of ongeldig certificaat.';
    } else if (e is IOException) {
      msg = 'Invoer-/uitvoerfout. Probeer opnieuw.';
    } else {
      msg = 'Netwerkfout. Controleer je internetverbinding en probeer opnieuw.';
    }
    return ApiException(kStatusNetworkError, msg);
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response r) async {
    final body = _parseBodyAsMap(r.body);
    if (r.statusCode == 401) {
      if (kDebugMode) debugPrint('[AUTH_DEBUG] *** 401 UNAUTHORIZED ***');
      if (kDebugMode) debugPrint('[AUTH_DEBUG]   message: ${body['message'] ?? "unknown"}');
      if (kDebugMode) debugPrint('[AUTH_DEBUG]   authToken: ${_authToken == null ? "NULL" : "SET"}');
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    if (r.statusCode == 401) {
      if (kDebugMode) debugPrint('[ApiClient] 401 Unauthorized – message: ${body['message'] ?? "unknown"}');
      // CRITICAL FIX: Use synchronized access to prevent multiple concurrent
      // 401 handlers from calling _on401 multiple times.
      // FIX-AUD-002: Improve 401 handling by clearing in-flight requests to prevent cascading errors
      synchronized(_tokenSyncLock, () {
        if (!_handling401) {
          _handling401 = true;
          // Clear all in-flight requests to prevent them from retrying with expired token
          _inFlightMutations.clear();
          _inFlightGets.clear();
          // Call logout handler in next event loop to avoid blocking request thread
          Future.microtask(() => _on401?.call());
        }
      });
    }
    // FIX #1: Extract field-level validation errors (422 status)
    final validationErrors = _extractValidationErrors(body);
    throw ApiException(
      r.statusCode,
      _safeUserMessage(r.statusCode, body),
      body: body,
      errors: validationErrors,
    );
  }

  /// Genereert een korte foutcode voor support (bijv. #GYM-500-A7B2).
  static String generateSupportCode(int statusCode) {
    final part = (DateTime.now().microsecondsSinceEpoch % 0xFFFF).toRadixString(36).toUpperCase().padLeft(3, '0');
    return '#GYM-$statusCode-$part';
  }

  /// Generelt unieke nonce voor HMAC requests (voorkomen replay attacks).
  static String _generateNonce() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(0xFFFFFFFF);
    return '${timestamp}_${random.toRadixString(36)}';
  }

  /// Detecteert of een bericht technisch/interne foutinfo bevat (niet aan gebruiker tonen).
  /// FIX #6c: More aggressive detection of HTML, server errors, and technical details.
  static bool _looksTechnical(String msg) {
    final lower = msg.toLowerCase();
    final hasHtml = lower.contains('<!') ||
        lower.contains('<html') ||
        lower.contains('<body') ||
        lower.contains('<head') ||
        lower.contains('<div') ||
        lower.contains('<script');

    if (hasHtml) return true;

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
        lower.contains('parse error') ||
        lower.contains('deprecated') ||
        lower.contains('file not found') ||
        lower.contains('not found') && lower.contains('server') ||
        lower.contains('404 not found') ||
        lower.contains('nginx') ||
        lower.contains('apache') ||
        lower.contains('white screen') ||
        lower == 'server error' ||
        lower.contains('internal server error') ||
        lower.contains('502 bad gateway') ||
        lower.contains('503 service') ||
        lower.contains('undefined index') ||
        lower.contains('trying to get') ||
        lower.contains('call to undefined') ||
        lower.contains('fatal error');
  }

  String _safeUserMessage(int statusCode, Map<String, dynamic> body) {
    final raw = _extractServerMessage(body) ?? _statusFallback(statusCode);
    final msg = raw.trim().isEmpty ? _statusFallback(statusCode) : raw.trim();

    // N-044 FIX: 404 – gebruik server message als die bruikbaar is, anders fallback
    if (statusCode == 404) {
      if (kDebugMode) debugPrint('[ApiClient] 404 response: $msg');
      // Als de server een nuttig JSON-bericht stuurde (niet HTML/technisch), toon dat
      if (!_looksTechnical(msg) && msg != _statusFallback(404) && msg.length < 200) {
        return msg;
      }
      return _statusFallback(404);
    }

    // Auth-fouten: vertaal generieke Engelse termen
    if (statusCode == 401 &&
        (msg.toLowerCase().contains('unauthorized') || msg.toLowerCase().contains('unauthenticated'))) {
      return 'Session expired'  // TODO:l10n — needs context;
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

  /// FIX #1: Extract field-level validation errors from Laravel FormRequest response
  /// Laravel: {'email': ['already exists'], 'password': ['too short']}
  /// Returns: {'email': ['already exists'], 'password': ['too short']}
  Map<String, List<String>>? _extractValidationErrors(Map<String, dynamic> body) {
    final errorsRaw = body['errors'];
    if (errorsRaw is! Map<String, dynamic>) return null;

    final result = <String, List<String>>{};
    for (final entry in errorsRaw.entries) {
      final fieldName = entry.key;
      final fieldErrors = entry.value;

      if (fieldErrors is List) {
        final messages = <String>[];
        for (final msg in fieldErrors) {
          if (msg is String && msg.trim().isNotEmpty) {
            messages.add(msg.trim());
          }
        }
        if (messages.isNotEmpty) {
          result[fieldName] = messages;
        }
      } else if (fieldErrors is String && fieldErrors.trim().isNotEmpty) {
        result[fieldName] = [fieldErrors.trim()];
      }
    }

    return result.isEmpty ? null : result;
  }

  String _statusFallback(int statusCode) {
    if (statusCode == 401) return 'Session expired'  // TODO:l10n — needs context;
    if (statusCode == 404) return 'Feature unavailable'  // TODO:l10n — needs context;
    if (statusCode == 403) return 'Je hebt geen toegang tot deze functie.';
    if (statusCode == 422) return 'Controleer je invoer en probeer opnieuw.'; // FIX: Be specific about validation
    if (statusCode == 429) return 'Te veel verzoeken. Wacht even en probeer opnieuw.';
    if (statusCode == 0) return 'Netwerkverbinding mislukt. Controleer je internetverbinding.'; // FIX: Handle network errors
    if (statusCode == 503) return 'De server is tijdelijk niet bereikbaar. Probeer het later opnieuw.';
    if (statusCode >= 500) return 'Er ging iets mis. Probeer het later opnieuw.';
    return 'Er ging iets mis. Probeer opnieuw.';
  }

  Map<String, dynamic> _parseBodyAsMap(String rawBody) {
    if (rawBody.trim().isEmpty) return <String, dynamic>{};

    // FIX #6d: Detect HTML responses (server error pages, 500, etc.)
    // HTML usually starts with <!DOCTYPE, <html, <head, <body, or <div
    if (rawBody.trim().toLowerCase().startsWith('<!') ||
        rawBody.trim().toLowerCase().startsWith('<html') ||
        rawBody.trim().toLowerCase().startsWith('<head') ||
        rawBody.trim().toLowerCase().startsWith('<body')) {
      if (kDebugMode) debugPrint('[ApiClient] HTML response detected, will be masked as technical error');
      return {'message': 'Server error page (HTML)'};
    }

    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List) return {'data': decoded};
    } catch (e) {
      // Fail-open: Return raw body as message if JSON parsing fails
      if (kDebugMode) debugPrint('[ApiClient] JSON parse error: $e');
    }
    return {'message': rawBody};
  }
}

class ApiException implements Exception {
  ApiException(
    this.statusCode,
    this.message, {
    this.body,
    this.errors,
  });
  final int statusCode;
  final String message;
  final Map<String, dynamic>? body;
  /// FIX #1: Field-level validation errors (422 status)
  /// Maps field names to lists of error messages, e.g. {'email': ['already exists']}
  final Map<String, List<String>>? errors;
  @override
  String toString() => message;
}

