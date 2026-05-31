import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BLEService ble = BLEService();
  final TextEditingController ssidController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController pinController = TextEditingController();

  StreamSubscription<String>? statusSubscription;
  BluetoothDevice? selectedDevice;

  String statusMessage = 'A procurar dispositivos BLE perto de si...';
  bool isConnecting = false;
  bool isSending = false;
  bool isPasswordVisible = false;

  @override
  void initState() {
    super.initState();

    statusSubscription = ble.statusMessages.listen((message) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusMessage = message;
      });
    });

    ble.startScan();
  }

  @override
  void dispose() {
    statusSubscription?.cancel();
    ssidController.dispose();
    passwordController.dispose();
    pinController.dispose();
    ble.dispose();
    super.dispose();
  }

  Future<void> _restartScan() async {
    setState(() {
      selectedDevice = null;
      statusMessage = 'A procurar dispositivos BLE...';
    });

    await ble.disconnect();
    await ble.startScan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Provisioning IoT'),
        actions: [
          IconButton(
            onPressed: _restartScan,
            icon: const Icon(Icons.refresh),
            tooltip: 'Procurar novamente',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Dispositivos BLE encontrados',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            StreamBuilder<List<ScanResult>>(
              stream: ble.scanResults,
              builder: (context, snapshot) {
                final count = snapshot.data?.length ?? 0;

                return Text(
                  '$statusMessage\nDispositivos detetados pelo Flutter: $count',
                );
              },
            ),

            const SizedBox(height: 10),

            Expanded(
              child: StreamBuilder<List<ScanResult>>(
                stream: ble.scanResults,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final devices = snapshot.data!;

                  if (devices.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Nenhum dispositivo BLE encontrado pelo Flutter',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _restartScan,
                            icon: const Icon(Icons.search),
                            label: const Text('Procurar novamente'),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final result = devices[index];
                      final device = result.device;

                      final deviceName = device.platformName.isNotEmpty
                          ? device.platformName
                          : result.advertisementData.advName.isNotEmpty
                          ? result.advertisementData.advName
                          : 'Dispositivo desconhecido';

                      final isSelected =
                          selectedDevice?.remoteId == device.remoteId;

                      return Card(
                        color: isSelected ? Colors.blue.shade100 : null,
                        child: ListTile(
                          title: Text(deviceName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(device.remoteId.toString()),
                              Text('RSSI: ${result.rssi}'),
                            ],
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : null,
                          onTap: isConnecting
                              ? null
                              : () async {
                                  if (isSelected) {
                                    await ble.disconnect();

                                    if (!mounted) {
                                      return;
                                    }

                                    setState(() {
                                      selectedDevice = null;
                                      statusMessage =
                                          'Dispositivo desconectado';
                                    });

                                    return;
                                  }

                                  setState(() {
                                    isConnecting = true;
                                    selectedDevice = null;
                                    statusMessage = 'A ligar ao dispositivo...';
                                  });

                                  try {
                                    await ble.connect(device);

                                    if (!mounted) {
                                      return;
                                    }

                                    setState(() {
                                      selectedDevice = device;
                                      statusMessage = 'Ligado a $deviceName';
                                    });
                                  } catch (e) {
                                    if (!mounted) {
                                      return;
                                    }

                                    setState(() {
                                      selectedDevice = null;
                                      statusMessage =
                                          'Falha ao ligar ao dispositivo';
                                    });

                                    _showSnackBar(
                                      'Falha ao ligar ao dispositivo: $e',
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        isConnecting = false;
                                      });
                                    }
                                  }
                                },
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: ssidController,
              decoration: const InputDecoration(
                labelText: 'SSID',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      isPasswordVisible = !isPasswordVisible;
                    });
                  },
                  icon: Icon(
                    isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                  ),
                  tooltip: isPasswordVisible
                      ? 'Ocultar password'
                      : 'Mostrar password',
                ),
              ),
              obscureText: !isPasswordVisible,
            ),

            const SizedBox(height: 10),

            TextField(
              controller: pinController,
              decoration: const InputDecoration(
                labelText: 'PIN de provisionamento',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: isSending ? null : _sendCredentials,
              child: Text(
                isSending ? 'A enviar...' : 'Enviar credenciais cifradas',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendCredentials() async {
    if (selectedDevice == null) {
      _showSnackBar('Nenhum dispositivo selecionado');
      return;
    }

    setState(() {
      isSending = true;
      statusMessage = 'A estabelecer sessao segura...';
    });

    try {
      await ble.sendCredentials(
        ssid: ssidController.text,
        password: passwordController.text,
        provisioningPin: pinController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        statusMessage = 'Credenciais cifradas enviadas';
      });

      _showSnackBar('Credenciais cifradas enviadas');
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusMessage = 'Erro no provisionamento seguro';
      });

      _showSnackBar('Erro no provisionamento seguro: $e');
    } finally {
      if (mounted) {
        setState(() {
          isSending = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
