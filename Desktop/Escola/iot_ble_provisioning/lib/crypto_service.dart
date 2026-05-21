import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' hide SecureRandom;
import 'package:pointycastle/export.dart';

class SecureSession {  //para guardar os dados da sessão (anti replay)
  SecureSession({
    required this.sessionId,
    required this.key,
    required this.clientNonce,
    required this.serverNonce,
  });

  final String sessionId;
  final Key key;
  final Uint8List clientNonce;
  final Uint8List serverNonce;
}

class ClientHandshake {  // inicio do handshake com chaves ECDH
  ClientHandshake({
    required this.privateKey,
    required this.publicKey,
    required this.clientNonce,
  });

  final ECPrivateKey privateKey;
  final Uint8List publicKey;
  final Uint8List clientNonce;
}

class CryptoService { //
  static const int protocolVersion = 1;
  static final ECDomainParameters _domain = ECDomainParameters('prime256v1'); // esta é a curva do ECDH
  static final Random _random = Random.secure(); // para nonces

  static ClientHandshake createClientHandshake() {
    final secureRandom = _secureRandom();
    final keyGenerator = ECKeyGenerator()
      ..init(
        ParametersWithRandom(ECKeyGeneratorParameters(_domain), secureRandom),
      );

    final keyPair = keyGenerator.generateKeyPair();
    final privateKey = keyPair.privateKey as ECPrivateKey;
    final publicKey = keyPair.publicKey as ECPublicKey;

    return ClientHandshake(
      privateKey: privateKey,
      publicKey: Uint8List.fromList(publicKey.Q!.getEncoded(false)), // codifica a chave publica em formato nao comprimido
      clientNonce: _randomBytes(16),
    );
  }

  static Map<String, dynamic> buildClientHello(ClientHandshake handshake) {
    return {
      'type': 'client_hello',
      'version': protocolVersion,
      'client_nonce': base64Encode(handshake.clientNonce),
      'client_public_key': base64Encode(handshake.publicKey),
    };
  }

  static SecureSession createSession({
    required ClientHandshake handshake,
    required Map<String, dynamic> serverHello, // resposta do servidor
    required String provisioningPin,
  }) {
    final serverNonce = _readBase64(serverHello, 'server_nonce');
    final serverPublicKeyBytes = _readBase64(serverHello, 'server_public_key');
    final sessionId = serverHello['session_id'] as String?;
    final serverProof = serverHello['server_proof'] as String?;

    if (sessionId == null || sessionId.isEmpty) {
      throw const FormatException('session_id em falta no servidor');
    }

    final sharedSecret = _calculateSharedSecret(
      handshake.privateKey,
      serverPublicKeyBytes,
    );

    final nonceSalt = _xorNonces(handshake.clientNonce, serverNonce);
    final keyBytes = _hkdfSha256(
      ikm: sharedSecret,
      salt: nonceSalt,
      info: utf8.encode(
        'ble-provisioning-v$protocolVersion|$sessionId|$provisioningPin', // PIN obriga a app e o servidor a conhecer o mesmo segredo
      ), // ajuda com spoofing e MITM
      length: 16,
    );

    final session = SecureSession(
      sessionId: sessionId,
      key: Key(Uint8List.fromList(keyBytes)),
      clientNonce: handshake.clientNonce,
      serverNonce: serverNonce,
    );

    if (serverProof != null && serverProof.isNotEmpty) {
      final expectedProof = createProof(
        session: session,
        label: 'server',
        clientPublicKey: handshake.publicKey,
        peerPublicKey: serverPublicKeyBytes,
      );

      if (!_constantTimeEquals(serverProof, expectedProof)) {
        throw const FormatException('prova criptografica do servidor invalida');
      }
    }

    return session;
  }

  static String createProof({ // prova criptografica
    required SecureSession session,
    required String label,
    required Uint8List clientPublicKey,
    required Uint8List peerPublicKey,
  }) {
    final transcript = <int>[
      ...utf8.encode('ble-provisioning|$label|${session.sessionId}|'),
      ...session.clientNonce,
      ...session.serverNonce,
      ...clientPublicKey,
      ...peerPublicKey,
    ];

    return base64Encode(
      Hmac(sha256, session.key.bytes).convert(transcript).bytes, // so quem tem a chave AES consegue produzir a prova
    );
  }

  static Map<String, dynamic> encryptPayload({
    required SecureSession session,
    required String ssid,
    required String password,
  }) {
    final iv = IV.fromSecureRandom(12);
    final encrypter = Encrypter(AES(session.key, mode: AESMode.gcm));

    final data = jsonEncode({
      'ssid': ssid,
      'password': password,
      'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
    });

    final aad = utf8.encode( // Additional Authenticated Data
      'ble-provisioning-v$protocolVersion|${session.sessionId}',
    );
    final encrypted = encrypter.encrypt(data, iv: iv, associatedData: aad);

    return {
      'type': 'wifi_credentials',
      'version': protocolVersion,
      'session_id': session.sessionId,
      'nonce': iv.base64,
      'ciphertext': encrypted.base64,
      'aad': base64Encode(aad),
    };
  }

  static Uint8List _calculateSharedSecret(
    ECPrivateKey privateKey,
    Uint8List peerPublicKeyBytes,
  ) {
    final point = _domain.curve.decodePoint(peerPublicKeyBytes);
    if (point == null) {
      throw const FormatException('chave publica do servidor invalida');
    }

    final agreement = ECDHBasicAgreement()..init(privateKey);
    final sharedSecret = agreement.calculateAgreement(
      ECPublicKey(point, _domain),
    );

    return _bigIntToFixedLengthBytes(sharedSecret, 32);
  }

  static List<int> _hkdfSha256({ // transforma o segredo bruto numa chave AES
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
    required int length,
  }) {
    final prk = Hmac(sha256, salt).convert(ikm).bytes;
    final output = <int>[];
    var previous = <int>[];
    var counter = 1;

    while (output.length < length) {
      previous = Hmac(
        sha256,
        prk,
      ).convert([...previous, ...info, counter]).bytes;
      output.addAll(previous);
      counter++;
    }

    return output.take(length).toList();
  }

  static Uint8List _xorNonces(Uint8List a, Uint8List b) {
    final length = min(a.length, b.length);
    return Uint8List.fromList(
      List<int>.generate(length, (index) => a[index] ^ b[index]),
    );
  }

  static Uint8List _readBase64(Map<String, dynamic> payload, String field) {
    final value = payload[field] as String?;
    if (value == null || value.isEmpty) {
      throw FormatException('$field em falta');
    }

    return base64Decode(value);
  }

  static Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  static SecureRandom _secureRandom() {
    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(_randomBytes(32)));
    return secureRandom;
  }

  static Uint8List _bigIntToFixedLengthBytes(BigInt value, int length) {
    final bytes = value
        .toRadixString(16)
        .padLeft(length * 2, '0')
        .replaceFirst(RegExp('^00'), '');
    final normalized = bytes.padLeft(length * 2, '0');

    return Uint8List.fromList([
      for (var i = 0; i < normalized.length; i += 2)
        int.parse(normalized.substring(i, i + 2), radix: 16),
    ]);
  }

  static bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) {
      return false;
    }

    var difference = 0;
    for (var i = 0; i < aBytes.length; i++) {
      difference |= aBytes[i] ^ bBytes[i];
    }

    return difference == 0;
  }
}
