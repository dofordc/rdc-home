import 'dart:convert';
import 'package:flutter/foundation.dart'; // para permitir print kDebugMode
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Home Automation',
      theme: ThemeData(
        // primarySwatch: Colors.blue,
        textTheme: GoogleFonts.ptMonoTextTheme(),
        scaffoldBackgroundColor: Colors.indigo[200],
      ),
      // primarySwatch: Colors.blue),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class LayoutByRdc extends StatelessWidget {
  const LayoutByRdc({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container(color: Colors.lightBlue));
  }
}

class _MyHomePageState extends State<MyHomePage> {
  // bool _toggled = false;
  // bool _lights = false;
  final client = MqttServerClient('192.168.0.171', 'flutter_client');
  Map<String, String> relayStates = {
    'esp001': 'off',
    'esp002': 'off',
    'esp004': 'off',
    'esp005': 'off',
    'esp006': 'off',
    'esp0031': 'off',
    'esp0032': 'off',
    'esp0033': 'off',
    'esp0034': 'off',
  };
  Map<String, Map<String, double>> sensors = {};
  Map<String, String> nomeSala = {
    'esp001': 'Sala 1',
    'esp002': 'Sala 2',
    'esp004': 'Sala 4',
    'esp005': 'Sala 5',
    'esp006': 'Sala 6',
  };

  @override
  void initState() {
    super.initState();
    _setupMqttClient();
  }

  Future<void> _setupMqttClient() async {
    client.port = 1883;
    client.keepAlivePeriod = 20;
    client.onDisconnected = () {
      // print('Desconectado do broker');
      setState(() {});
    };
    client.onConnected = () {
      // print('Conectado ao broker');
      _subscribeToTopics();
    };
    client.onSubscribed = (topic) {
      // print('Subscrito em: $topic');
    };

    try {
      await client.connect();
    } on Exception catch (e) {
      if (kDebugMode) {
        print('Erro de conexão: $e');
      }
      client.disconnect();
    }

    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final recMess = c[0].payload as MqttPublishMessage;
      final pt = client.updates!.first; // .topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      if (kDebugMode) {
        print('Recebido: $pt = $payload');
      }

      setState(() {
        final data = parsePayload(payload);
        if (data['estado_rele'] != null) {
          relayStates[data['id']] = data['estado_rele'];
        }
        if (data['temp'] != null && data['umid'] != null) {
          sensors[data['id']] = {'temp': data['temp'], 'umid': data['umid']};
        }
      });
    });
  }

  void _subscribeToTopics() {
    client.subscribe('/status/#', MqttQos.atMostOnce); // captura os sub-tópicos
    client.subscribe('/dados/#', MqttQos.atMostOnce);
    // Query inicial
    // for (var id in relayStates.keys) {
    for (var id in [
      'esp001',
      'esp002',
      'esp004',
      'esp005',
      'esp006',
      'esp003x',
    ]) {
      client.publishMessage(
        '/comando/$id',
        MqttQos.atMostOnce,
        MqttClientPayloadBuilder().addString('{"comando": "status"}').payload!,
      );
    }
    for (var id in ['esp001', 'esp002', 'esp004', 'esp005', 'esp006']) {
      client.publishMessage(
        '/comando/$id',
        MqttQos.atMostOnce,
        MqttClientPayloadBuilder().addString('{"comando": "data"}').payload!,
      );
    }
  }

  Map<String, dynamic> parsePayload(String payload) {
    try {
      return jsonDecode(payload);
    } catch (e) {
      if (kDebugMode) {
        print('Erro ao parsear payload: $e');
      }
      return {};
    }
  }

  void _toggleRelay(String id) {
    if (id.length == 7) {
      String id7 = id[6];
      String idEsp = '${id.substring(0, 6)}x';
      // print('idEsp: $idEsp, comando = $id7');
      client.publishMessage(
        '/comando/$idEsp',
        MqttQos.atMostOnce,
        MqttClientPayloadBuilder().addString('{"comando": "$id7"}').payload!,
      );
    } else {
      client.publishMessage(
        '/comando/$id',
        MqttQos.atMostOnce,
        MqttClientPayloadBuilder().addString('{"comando": "toggle"}').payload!,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: Colors.white30, //.fromARGB(255, 38, 56, 85),
      appBar: AppBar(
        title: const Text(
          'Home Automation',
          style: TextStyle(
            fontFamily: 'Marmelad',
            fontSize: 26.0,
            fontWeight: FontWeight.bold,
          ),
        ),backgroundColor: Colors.indigo[300],
        // foregroundColor: Colors.white,
        // backgroundColor: Colors.black, // .fromARGB(255, 38, 53, 85),
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ...sensors.entries.map((entry) {
                String sala = '';
                for (var nome in nomeSala.entries) {
                  if (entry.key == nome.key) {
                    sala = nome.value;
                  }
                }
                final id = sala;
                final data = entry.value;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              id,
                              //${data['temp']?.toStringAsFixed(1)}°C\n${data['umid']?.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontFamily: 'Marmelad',
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                // color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              //'$id\n
                              '${data['temp']?.toStringAsFixed(1)}°C\n${data['umid']?.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 20,
                                fontFamily: 'Marmelad',
                                // fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ],
          ),
          Expanded(
            child: SizedBox(
              width: double.infinity,
              // color: Colors.black,
              child: Column(
                children: [
                  SizedBox(height: 16.0),
                  ...relayStates.entries.map((entry) {
                    final id = entry.key;
                    final state = entry.value;
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.white30,
                                width: 1.0,
                              ),
                              elevation: 5.0,
                              fixedSize: Size(250.0, 30.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadiusGeometry.circular(
                                  5.0,
                                ),
                              ),
                              backgroundColor: state == 'on'
                                  ? Colors.lightBlueAccent[400]
                                  : Colors.white24,
                              foregroundColor: state == 'on'
                                  ? Colors.black87
                                  : Colors.white70,
                            ),
                            onPressed: () {
                              _toggleRelay(id);
                            },
                            child: Text(
                              '${id.padRight(7, ' ')}: ${state.toUpperCase().padLeft(3, ' ')}',
                              textAlign: TextAlign.left,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    client.disconnect();
    super.dispose();
  }
}
