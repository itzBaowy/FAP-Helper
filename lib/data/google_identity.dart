import 'dart:convert';
import 'dart:io';

import 'package:jose/jose.dart';

class GoogleIdentity {
  const GoogleIdentity(this.email, this.subject);
  final String email;
  final String subject;
}

abstract interface class IdentityVerifier {
  Future<GoogleIdentity> verify(String credential, String nonce);
  void dispose();
}

/// Keys only come from Google's fixed HTTPS endpoint, never from a JWT header.
class GoogleIdentityVerifier implements IdentityVerifier {
  GoogleIdentityVerifier({
    required this.clientId,
    required this.domains,
    DateTime Function()? now,
    this.loadKeys,
  }) : _now = now ?? DateTime.now;
  final String clientId;
  final Set<String> domains;
  final DateTime Function() _now;
  final Future<Map<String, dynamic>> Function()? loadKeys;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  JsonWebKeyStore? _keys;
  DateTime? _refreshAt;
  DateTime? _lastFetch;

  Future<void> _refresh() async {
    Map<String, dynamic> json;
    var seconds = 3600;
    _lastFetch = _now();
    if (loadKeys != null) {
      json = await loadKeys!();
    } else {
      final request = await _client.getUrl(
        Uri.parse('https://www.googleapis.com/oauth2/v3/certs'),
      );
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw const FormatException(
          'Chưa lấy được khóa xác thực Google. Hãy thử lại.',
        );
      }
      final cache =
          response.headers.value(HttpHeaders.cacheControlHeader) ?? '';
      seconds =
          int.tryParse(
            RegExp(r'max-age=(\d+)').firstMatch(cache)?.group(1) ?? '',
          ) ??
          seconds;
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) {
          throw const FormatException('Phản hồi Google không hợp lệ.');
        }
      }
      json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }
    _keys = JsonWebKeyStore()..addKeySet(JsonWebKeySet.fromJson(json));
    _refreshAt = _now().add(Duration(seconds: seconds.clamp(60, 86400)));
  }

  @override
  Future<GoogleIdentity> verify(String credential, String nonce) async {
    try {
      if (credential.length > 12000 || nonce.isEmpty) {
        throw const FormatException();
      }
      final parts = credential.split('.');
      if (parts.length != 3) throw const FormatException();
      final header = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts.first))),
      ) as Map;
      if (header['alg'] != 'RS256' ||
          header['kid'] is! String ||
          header.containsKey('jku') ||
          header.containsKey('jwk') ||
          header.containsKey('x5u')) {
        throw const FormatException();
      }
      if (_keys == null || !_now().isBefore(_refreshAt!)) await _refresh();
      final token = JsonWebToken.unverified(credential);
      var verified = await token.verify(_keys!, allowedArguments: ['RS256']);
      // Accommodate Google's key rotation, with a bound on unknown-key refreshes.
      if (!verified && _now().difference(_lastFetch!).inSeconds >= 60) {
        await _refresh();
        verified = await token.verify(_keys!, allowedArguments: ['RS256']);
      }
      if (!verified) throw const FormatException();
      final claims = token.claims;
      final now = _now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final exp = claims['exp'];
      final issued = claims['iat'];
      final email = claims['email'];
      final subject = claims['sub'];
      if (![
            'https://accounts.google.com',
            'accounts.google.com',
          ].contains(claims['iss']) ||
          claims['aud'] != clientId ||
          (claims['azp'] != null && claims['azp'] != clientId) ||
          exp is! int ||
          exp <= now ||
          issued is! int ||
          issued > now + 30 ||
          (claims['nbf'] != null &&
              (claims['nbf'] is! int || (claims['nbf'] as int) > now + 30)) ||
          claims['nonce'] != nonce ||
          claims['email_verified'] != true ||
          email is! String ||
          subject is! String ||
          subject.isEmpty ||
          subject.length > 255) {
        throw const FormatException();
      }
      final normalized = email.trim().toLowerCase();
      final pieces = normalized.split('@');
      if (pieces.length != 2 || !domains.contains(pieces.last)) {
        throw const FormatException();
      }
      // Google is authoritative for Gmail and managed Workspace accounts.
      if (pieces.last != 'gmail.com' && !domains.contains(claims['hd'])) {
        throw const FormatException();
      }
      return GoogleIdentity(normalized, subject);
    } catch (_) {
      throw const FormatException(
        'Không xác thực được tài khoản Google. Dùng email được phép và đăng nhập lại.',
      );
    }
  }

  @override
  void dispose() => _client.close(force: true);
}
