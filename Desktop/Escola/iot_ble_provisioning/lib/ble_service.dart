import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'crypto_service.dart';

class BLEService {

  BluetoothDevice? connectedDevice;

  BluetoothCharacteristic? writeCharacteristic;

  // UUIDs DO SERVIDOR
  final String serviceUUID =
      "12345678-1234-5678-1234-567812345678";

  final String characteristicUUID =
      "87654321-4321-8765-4321-876543210987";

  // STREAM DE RESULTADOS
  Stream<List<ScanResult>> get scanResults =>
      FlutterBluePlus.scanResults;

  // INICIAR SCAN
  Future<void> startScan() async {

    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth não suportado");
      return;
    }

    await FlutterBluePlus.stopScan();

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
    );

    print("Scan BLE iniciado");
  }

  // CONNECT
  Future<void> connect(
      BluetoothDevice device
      ) async {

    try {

      // desconectar anterior
      if (connectedDevice != null) {

        await connectedDevice!.disconnect();

        await Future.delayed(
          const Duration(milliseconds: 500),
        );
      }

      writeCharacteristic = null;

      // conectar
      await device.connect();

      connectedDevice = device;

      print("Ligado ao dispositivo");

      // descobrir serviços
      List<BluetoothService> services =
      await device.discoverServices();

      for (var service in services) {

        print("Serviço encontrado:");
        print(service.uuid);

        // procurar o NOSSO serviço
        if (service.uuid.toString().toLowerCase()
            == serviceUUID.toLowerCase()) {

          for (var characteristic
          in service.characteristics) {

            print("Characteristic:");
            print(characteristic.uuid);

            // procurar characteristic correta
            if (characteristic.uuid
                .toString()
                .toLowerCase() ==
                characteristicUUID.toLowerCase()) {

              writeCharacteristic =
                  characteristic;

              print(
                "WRITE characteristic encontrada",
              );
            }
          }
        }
      }

      if (writeCharacteristic == null) {
        print(
          "Characteristic do projeto não encontrada",
        );
      }

    } catch (e) {

      print("Erro BLE connect:");
      print(e);
    }
  }

  // DISCONNECT
  Future<void> disconnect() async {

    try {

      if (connectedDevice != null) {

        await connectedDevice!.disconnect();

        connectedDevice = null;

        writeCharacteristic = null;

        print("Dispositivo desconectado");
      }

    } catch (e) {

      print("Erro disconnect:");
      print(e);
    }
  }

  // ENVIAR CREDENCIAIS
  Future<void> sendCredentials(
      String ssid,
      String password
      ) async {

    if (writeCharacteristic == null) {

      print(
        "WRITE characteristic não encontrada",
      );

      return;
    }

    try {

      // payload AES
      final payload =
      CryptoService.encryptPayload(
        ssid,
        password,
      );

      // JSON
      final jsonPayload =
      jsonEncode(payload);

      print("Payload enviado:");
      print(jsonPayload);

      // enviar BLE
      await writeCharacteristic!.write(
        utf8.encode(jsonPayload),
        withoutResponse: false,
      );

      print(
        "Credenciais enviadas com sucesso",
      );

    } catch (e) {

      print("Erro envio BLE:");
      print(e);
    }
  }
}