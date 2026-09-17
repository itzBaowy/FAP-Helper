import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:fap_helper_v1/data/google_identity.dart';

void main() {
  final now = DateTime.utc(2026, 9, 15, 3);
  late JsonWebKey key;
  late GoogleIdentityVerifier verifier;
  var fetches = 0;
  const client = 'test.apps.googleusercontent.com';
  setUpAll(() {
    key = JsonWebKey.fromJson({
      ...JsonWebKey.generate('RS256', keyBitLength: 2048).toJson(),
      'kid': 'test-key',
    });
  });
  setUp(() {
    fetches = 0;
    final public = Map<String, dynamic>.from(key.toJson())
      ..removeWhere(
        (name, _) => ['d', 'p', 'q', 'dp', 'dq', 'qi'].contains(name),
      );
    verifier = GoogleIdentityVerifier(
      clientId: client,
      domains: {'gmail.com', 'fpt.edu.vn'},
      now: () => now,
      loadKeys: () async {
        fetches++;
        return {
          'keys': [public],
        };
      },
    );
  });
  tearDown(() => verifier.dispose());
  String credential([
    Map<String, dynamic> overrides = const {},
    JsonWebKey? signingKey,
  ]) {
    final seconds = now.millisecondsSinceEpoch ~/ 1000;
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = {
        'iss': 'https://accounts.google.com',
        'aud': client,
        'sub': 'test-google-user',
        'exp': seconds + 3600,
        'iat': seconds,
        'nonce': 'scan-nonce',
        'email': 'Student@fpt.edu.vn',
        'email_verified': true,
        'hd': 'fpt.edu.vn',
        ...overrides,
      };
    builder.addRecipient(signingKey ?? key, algorithm: 'RS256');
    return builder.build().toCompactSerialization();
  }

  test(
    'verifies RS256 Google audience, managed school email, nonce; caches keys',
    () async {
      expect(
        (await verifier.verify(credential(), 'scan-nonce')).email,
        'student@fpt.edu.vn',
      );
      expect(
        (await verifier.verify(
          credential({'email': 'student@gmail.com', 'hd': null}),
          'scan-nonce',
        )).email,
        'student@gmail.com',
      );
      expect(fetches, 1);
    },
  );
  test('rejects wrong issuer/audience/nonce/expiry/unverified email/domain and unmanaged school account', () async {
    for (final bad in <Map<String, dynamic>>[
      {'iss': 'https://evil.example'},
      {'aud': 'another-client'},
      {'azp': 'another-client'},
      {'nonce': 'another-scan'},
      {'exp': now.millisecondsSinceEpoch ~/ 1000},
      {'iat': now.millisecondsSinceEpoch ~/ 1000 + 100},
      {'email_verified': false},
      {'email_verified': 'true'},
      {'email': 'a@evil.example'},
      {'hd': null},
      {'sub': ''},
    ]) {
      await expectLater(
        verifier.verify(credential(bad), 'scan-nonce'),
        throwsFormatException,
        reason: bad.keys.join(','),
      );
    }
  });
  test('rejects forged signature, unsigned JWT and key supplied in header', () async {
    final other = JsonWebKey.fromJson({
      ...JsonWebKey.generate('RS256', keyBitLength: 2048).toJson(),
      'kid': 'test-key',
    });
    await expectLater(
      verifier.verify(credential({}, other), 'scan-nonce'),
      throwsFormatException,
    );
    final parts = credential().split('.');
    String encoded(Object json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    await expectLater(
      verifier.verify(
        '${encoded({'alg': 'none', 'kid': 'test-key'})}.${parts[1]}.',
        'scan-nonce',
      ),
      throwsFormatException,
    );
    await expectLater(
      verifier.verify(
        '${encoded({'alg': 'RS256', 'kid': 'test-key', 'jku': 'https://evil.example/keys'})}.${parts[1]}.${parts[2]}',
        'scan-nonce',
      ),
      throwsFormatException,
    );
    expect(fetches, 1);
  });
}
