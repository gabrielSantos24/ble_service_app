import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  final BLEService ble = BLEService();

  String ssid = "";
  String password = "";

  BluetoothDevice? selectedDevice;

  @override
  void initState() {
    super.initState();

    // iniciar scan quando abre app
    ble.startScan();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("BLE Provisioning IoT"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          children: [

            const Text(
              "Dispositivos BLE",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            // LISTA BLE
            Expanded(
              child: StreamBuilder<List<ScanResult>>(

                stream: ble.scanResults,

                builder: (context, snapshot) {

                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  final devices = snapshot.data!;

                  if (devices.isEmpty) {
                    return const Center(
                      child: Text("A procurar dispositivos BLE..."),
                    );
                  }

                  return ListView.builder(

                    itemCount: devices.length,

                    itemBuilder: (context, index) {

                      final result = devices[index];
                      final device = result.device;

                      final isSelected =
                          selectedDevice?.remoteId ==
                              device.remoteId;

                      return Card(

                        color: isSelected
                            ? Colors.blue.shade100
                            : null,

                        child: ListTile(

                          title: Text(
                            device.platformName.isNotEmpty
                                ? device.platformName
                                : "Dispositivo desconhecido",
                          ),

                          subtitle: Text(
                            device.remoteId.toString(),
                          ),

                          trailing: isSelected
                              ? const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          )
                              : null,

                          onTap: () async {

                            // DES-SELECIONAR
                            if (isSelected) {

                              await ble.disconnect();

                              setState(() {
                                selectedDevice = null;
                              });

                              return;
                            }

                            // SELECIONAR NOVO
                            setState(() {
                              selectedDevice = device;
                            });

                            await ble.connect(device);

                            setState(() {});
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // SSID
            TextField(
              decoration: const InputDecoration(
                labelText: "SSID",
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => ssid = v,
            ),

            const SizedBox(height: 10),

            // PASSWORD
            TextField(
              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              onChanged: (v) => password = v,
            ),

            const SizedBox(height: 20),

            // BOTÃO
            SizedBox(
              width: double.infinity,

              child: ElevatedButton(

                onPressed: () async {

                  if (selectedDevice == null) {

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Nenhum dispositivo selecionado",
                        ),
                      ),
                    );

                    return;
                  }

                  await ble.sendCredentials(
                    ssid,
                    password,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Credenciais enviadas",
                      ),
                    ),
                  );
                },

                child: const Text(
                  "Enviar credenciais",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}