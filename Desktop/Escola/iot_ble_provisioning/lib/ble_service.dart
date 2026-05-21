import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'crypto_service.dart';

class BLEService {
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? authCharacteristic;
  BluetoothCharacteristic? configCharacteristic;
  BluetoothCharacteristic? statusCharacteristic;
  SecureSession? secureSession;

  static const String serviceUUID = '12345678-1234-5678-1234-567812345678';
  static const String authCharacteristicUUID =
      '87654321-4321-8765-4321-876543210988';
  static const String configCharacteristicUUID =
      '87654321-4321-8765-4321-876543210987';
  static const String statusCharacteristicUUID =
      '87654321-4321-8765-4321-876543210989';

  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  Stream<String> get statusMessages => _statusController.stream;

  Future<void> startScan() async {
    if (await FlutterBluePlus.isSupported == false) {
      _statusController.add('Bluetooth nao suportado');
      return;
    }

    await FlutterBluePlus.stopScan();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    _statusController.add('Scan BLE iniciado: a mostrar todos os dispositivos');
  }

  Future<void> connect(BluetoothDevice device) async {
    try {
      if (connectedDevice != null) {
        await connectedDevice!.disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      _clearConnectionState();

      await device.connect();
      await device.requestMtu(512);

      connectedDevice = device;
      _statusController.add('Ligado ao dispositivo');

      final services = await device.discoverServices();

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() !=
            serviceUUID.toLowerCase()) {
          continue;
        }

        for (final characteristic in service.characteristics) {
          final uuid = characteristic.uuid.toString().toLowerCase();

          if (uuid == authCharacteristicUUID.toLowerCase()) {
            authCharacteristic = characteristic;
          } else if (uuid == configCharacteristicUUID.toLowerCase()) {
            configCharacteristic = characteristic;
          } else if (uuid == statusCharacteristicUUID.toLowerCase()) {
            statusCharacteristic = characteristic;
          }
        }
      }

      if (authCharacteristic == null || configCharacteristic == null) {
        throw StateError(
          'O dispositivo nao expoe as characteristics seguras esperadas',
        );
      }

      await _subscribeStatus();
      _statusController.add('Characteristics seguras encontradas');
    } catch (e) {
      await disconnect();
      _statusController.add('Erro BLE connect: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      if (connectedDevice != null) {
        await connectedDevice!.disconnect();
      }
    } finally {
      _clearConnectionState();
      _statusController.add('Dispositivo desconectado');
    }
  }

  Future<void> establishSecureSession(String provisioningPin) async {
    if (authCharacteristic == null) {
      throw StateError('Characteristic de autenticacao nao encontrada');
    }

    final pin = provisioningPin.trim();
    if (pin.length < 4) {
      throw ArgumentError(
        'O PIN de provisionamento deve ter pelo menos 4 digitos',
      );
    }

    final handshake = CryptoService.createClientHandshake();
    final clientHello = CryptoService.buildClientHello(handshake);

    await _writeJson(authCharacteristic!, clientHello);

    final serverHelloRaw = await authCharacteristic!.read();
    final serverHello = jsonDecode(utf8.decode(serverHelloRaw));
    if (serverHello is! Map<String, dynamic>) {
      throw const FormatException('Resposta de autenticacao invalida');
    }

    final session = CryptoService.createSession(
      handshake: handshake,
      serverHello: serverHello,
      provisioningPin: pin,
    );

    final serverPublicKey = base64Decode(serverHello['server_public_key']);
    final clientProof = CryptoService.createProof(
      session: session,
      label: 'client',
      clientPublicKey: handshake.publicKey,
      peerPublicKey: Uint8List.fromList(serverPublicKey),
    );

    await _writeJson(authCharacteristic!, {
      'type': 'client_proof',
      'version': CryptoService.protocolVersion,
      'session_id': session.sessionId,
      'client_proof': clientProof,
    });

    secureSession = session;
    _statusController.add('Sessao segura estabelecida');
  }

  Future<void> sendCredentials({
    required String ssid,
    required String password,
    required String provisioningPin,
  }) async {
    if (configCharacteristic == null) {
      throw StateError('Characteristic de configuracao nao encontrada');
    }

    if (ssid.trim().isEmpty || password.isEmpty) {
      throw ArgumentError('SSID e password sao obrigatorios');
    }

    if (secureSession == null) {
      await establishSecureSession(provisioningPin);
    }

    final payload = CryptoService.encryptPayload(
      session: secureSession!,
      ssid: ssid.trim(),
      password: password,
    );

    await _writeJson(configCharacteristic!, payload);
    _statusController.add('Credenciais cifradas enviadas');
  }

  Future<void> dispose() async {
    await disconnect();
    await _statusController.close();
  }

  Future<void> _subscribeStatus() async {
    final characteristic = statusCharacteristic;
    if (characteristic == null) {
      return;
    }

    await characteristic.setNotifyValue(true);
    characteristic.lastValueStream.listen((value) {
      if (value.isEmpty) {
        return;
      }

      _statusController.add(utf8.decode(value, allowMalformed: true));
    });
  }

  Future<void> _writeJson(
    BluetoothCharacteristic characteristic,
    Map<String, dynamic> payload,
  ) async {
    final bytes = utf8.encode(jsonEncode(payload));
    await characteristic.write(bytes, withoutResponse: false);
  }

  void _clearConnectionState() {
    connectedDevice = null;
    authCharacteristic = null;
    configCharacteristic = null;
    statusCharacteristic = null;
    secureSession = null;
  }
}
