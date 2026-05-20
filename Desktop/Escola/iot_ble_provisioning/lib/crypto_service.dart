import 'dart:convert';
import 'dart:math';
import 'package:encrypt/encrypt.dart';

class CryptoService {

  // mesma chave do Raspberry
  static final key = Key.fromUtf8('1234567890123456');

  static Map<String, dynamic> encryptPayload(
      String ssid,
      String password
      ) {

    final iv = IV.fromSecureRandom(12);

    final encrypter = Encrypter(
      AES(
        key,
        mode: AESMode.gcm,
      ),
    );

    final data = jsonEncode({
      "ssid": ssid,
      "password": password,
    });

    final encrypted = encrypter.encrypt(
      data,
      iv: iv,
    );

    return {
      "ciphertext": encrypted.base64,
      "nonce": iv.base64,
    };
  }
}