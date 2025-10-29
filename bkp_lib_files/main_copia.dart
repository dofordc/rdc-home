import 'dart:convert';

import 'package:flutter/foundation.dart'; // para permitir print kDebugMode
import 'package:flutter/material.dart';
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
      title: 'Home Automation',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 49, 80, 179),
        ),
      ),
      // primarySwatch: Colors.blue),
      home: const MyHomePage(title: 'Home Automation App'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
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
    client.subscribe(
      '/status/#',
      MqttQos.atMostOnce,
    ); // # captura todos sub-tópicos
    client.subscribe('/dados/#', MqttQos.atMostOnce);
    // Query inicial
    // for (var id in relayStates.keys) {
    for (var id in ['esp001', 'esp002', 'esp004', 'esp005', 'esp006', 'esp003x']) {
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
      backgroundColor: const Color.fromARGB(255, 38, 56, 85),
      appBar: AppBar(
        title: const Text('Home Automation'),
        foregroundColor: Colors.white70,
        backgroundColor: Color.fromARGB(255, 38, 53, 85),
      ),
      body: ListView(
        padding: const EdgeInsets.all(1.0),
        children: [
          ...relayStates.entries.map((entry) {
            final id = entry.key;
            final state = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 100.0,
                vertical: 5.0,
              ),
              child: ElevatedButton(
                onPressed: () => _toggleRelay(id),
                style: ElevatedButton.styleFrom(
                  side: BorderSide(color: Colors.white70, width: 2.0),
                  backgroundColor: state == 'on'
                      ? Colors.green
                      : Colors.white70,
                  foregroundColor: state == 'on' ? Colors.white : Colors.black,
                ),
                child: Text('$id: ${state.toUpperCase()}'),
              ),
            );
          }), //.toList(),
          const SizedBox(height: 10),
          ...sensors.entries.map((entry) {
            final id = entry.key;
            final data = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 5),
              child: Text(
                // '$id == esp001 ${data['temp']?.toStringAsFixed(1)}°C, Umid: ${data['umid']?.toStringAsFixed(1)}%',
                // '$id: Temp: ${data['temp']?.toStringAsFixed(1)}°C, Umid: ${data['umid']?.toStringAsFixed(1)}%',
                '$id:  ${data['temp']?.toStringAsFixed(1)}°C  |  ${data['umid']?.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 26, color: Colors.white70),
              ),
            );
          }), // .toList(),
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
