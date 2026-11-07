import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiError implements Exception {
  final String message;
  final int status;
  final bool additionalRequired;
  ApiError(this.message, [this.status = 0, this.additionalRequired = false]);
  @override
  String toString() => message;
}

Uri validatedServer(String raw) {
  final u = Uri.tryParse(raw.trim());
  if (u == null ||
      u.scheme != 'https' ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty ||
      u.hasQuery ||
      u.hasFragment ||
      (u.path.isNotEmpty && u.path != '/')) {
    throw ApiError(
      'Enter the HTTPS server origin, for example https://trade.example.com. Do not include a path or tunnel token.',
    );
  }
  return Uri(scheme: 'https', host: u.host, port: u.hasPort ? u.port : null);
}

class TradeApi {
  final http.Client client;
  final FlutterSecureStorage storage;
  Uri? server;
  String _cookie = '';
  bool authenticated = false;
  bool rememberSession = true, additionalPasswordRequired = false;
  TradeApi({http.Client? client, FlutterSecureStorage? storage})
    : client = client ?? http.Client(),
      storage = storage ?? const FlutterSecureStorage();
  String get address => server?.toString() ?? '';
  Future<void> restore() async {
    final raw = await storage.read(key: 'server') ?? 'https://sureshkatz.shop';
    if (raw.isNotEmpty) {
      server = validatedServer(raw);
      _cookie = await storage.read(key: 'session') ?? '';
    }
  }

  Future<void> setServer(String raw) async {
    final next = validatedServer(raw);
    if (server != next) {
      _cookie = '';
      authenticated = false;
      await storage.delete(key: 'session');
    }
    server = next;
    await storage.write(key: 'server', value: address);
  }

  Uri uri(String path) {
    if (server == null) throw ApiError('Configure your server first.');
    final result = server!.resolve(path);
    if (result.origin != server!.origin)
      throw ApiError('Cross-origin API requests are blocked.');
    return result;
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final req = http.Request(method, uri(path));
    req.followRedirects = false;
    req.headers['Accept'] = 'application/json';
    if (_cookie.isNotEmpty) req.headers['Cookie'] = _cookie;
    if (data != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(data);
    }
    http.StreamedResponse streamed;
    try {
      streamed = await client.send(req).timeout(timeout);
    } on TimeoutException {
      throw ApiError(
        'Server timed out. Check that your Windows backend and tunnel are running.',
      );
    } catch (e) {
      throw ApiError(
        'Cannot reach server. Check your connection and HTTPS address.',
      );
    }
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw ApiError(
        'The server redirected this request. Check the HTTPS origin. Cloudflare Access browser sessions are not integrated with this native client.',
      );
    }
    dynamic result;
    try {
      result = jsonDecode(response.body);
    } catch (_) {
      throw ApiError(
        'The server returned a page instead of API data. Check your server address or Cloudflare Access configuration.',
        response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) authenticated = false;
      throw ApiError(
        result is Map
            ? '${result['detail'] ?? result['error'] ?? 'Request failed'}'
            : 'Request failed',
        response.statusCode,
        response.headers['x-additional-password-required'] == '1',
      );
    }
    final cookies = response.headers['set-cookie'];
    if (cookies != null) {
      final match = RegExp(r'(skxtrade_session=[^;,\s]+)').firstMatch(cookies);
      if (match != null) {
        _cookie = match.group(1)!;
        if (rememberSession)
          await storage.write(key: 'session', value: _cookie);
        else
          await storage.delete(key: 'session');
      }
    }
    return result;
  }

  Future<bool> checkSession() async {
    final x = await request('/api/auth/status');
    authenticated = x['authenticated'] == true;
    additionalPasswordRequired = x['additionalPasswordRequired'] == true;
    return authenticated;
  }

  Future<void> login(
    String username,
    String password,
    String additional, {
    bool remember = true,
  }) async {
    rememberSession = remember;
    if (!remember) await storage.delete(key: 'session');
    await request(
      '/api/auth/login',
      method: 'POST',
      data: {
        'username': username.trim(),
        'password': password,
        'additionalPassword': additional,
      },
    );
    if (remember)
      await storage.write(key: 'username', value: username.trim());
    else
      await storage.delete(key: 'username');
    if (!await checkSession())
      throw ApiError(
        'Login completed without a valid session. Check server cookie settings.',
      );
  }

  Future<void> logout() async {
    try {
      await request('/api/auth/logout', method: 'POST');
    } finally {
      _cookie = '';
      authenticated = false;
      await storage.delete(key: 'session');
    }
  }

  Future<dynamic> get(String p) => request(p);
  Future<dynamic> post(String p, [dynamic d]) =>
      request(p, method: 'POST', data: d ?? <String, dynamic>{});
  Future<dynamic> put(String p, dynamic d) =>
      request(p, method: 'PUT', data: d);
}

Map<String, dynamic> obj(dynamic x) =>
    x is Map ? Map<String, dynamic>.from(x) : {};
List<dynamic> arr(dynamic x) => x is List ? x : [];
double numv(dynamic x) => x is num ? x.toDouble() : double.tryParse('$x') ?? 0;
String money(dynamic x, {int decimals = 2}) {
  final n = numv(x);
  if (!n.isFinite) return n.isNegative ? '−∞' : '∞';
  final parts = n.toStringAsFixed(decimals).split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
}

String pretty(dynamic x) => const JsonEncoder.withIndent('  ').convert(x);
