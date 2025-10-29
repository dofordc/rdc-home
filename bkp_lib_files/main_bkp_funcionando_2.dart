import 'dart:convert';
import 'package:flutter/foundation.dart';
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
        textTheme: GoogleFonts.ptMonoTextTheme(),
        scaffoldBackgroundColor: Colors.indigo[200],
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  late final MqttServerClient client;
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

  bool _isConnected = false;
  bool _isReconnecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Observa ciclo de vida
    _initMqttClient();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    client.disconnect();
    super.dispose();
  }

  // Detecta volta do background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (kDebugMode) print('App voltou do background! Verificando conexão...');
      _reconnectIfNeeded();
    }
  }

  void _initMqttClient() {
    final clientId = 'flutter_client_${DateTime.now().millisecondsSinceEpoch}';
    client = MqttServerClient('192.168.0.171', clientId);
    client.port = 1883;
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;

    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;
    client.onSubscribed = (topic) {
      if (kDebugMode) print('Subscrito: $topic');
    };

    _connect();
  }

  Future<void> _connect() async {
    if (_isReconnecting) return;
    _isReconnecting = true;

    try {
      if (kDebugMode) print('Conectando ao MQTT...');
      await client.connect();
    } catch (e) {
      if (kDebugMode) print('Erro de conexão: $e');
      _scheduleReconnect();
    } finally {
      _isReconnecting = false;
    }
  }

  void _onConnected() {
    if (kDebugMode) print('Conectado ao broker!');
    setState(() => _isConnected = true);
    _subscribeToTopics();
    _requestInitialData();
    _setupListener();
  }

  void _onDisconnected() {
    if (kDebugMode) print('Desconectado do broker.');
    setState(() => _isConnected = false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isConnected && !_isReconnecting) {
        if (kDebugMode) print('Tentando reconectar...');
        _connect();
      }
    });
  }

  // Força reconexão ao voltar do background
  Future<void> _reconnectIfNeeded() async {
    if (_isConnected) {
      _requestInitialData(); // Já conectado? Só atualiza dados
    } else {
      client.disconnect();
      await Future.delayed(const Duration(milliseconds: 300));
      _connect();
    }
  }

  void _subscribeToTopics() {
    client.subscribe('/status/#', MqttQos.atMostOnce);
    client.subscribe('/dados/#', MqttQos.atMostOnce);
  }

  void _requestInitialData() {
    final ids = ['esp001', 'esp002', 'esp004', 'esp005', 'esp006', 'esp003x'];
    for (var id in ids) {
      _publish('/comando/$id', '{"comando": "status"}');
    }
    for (var id in ['esp001', 'esp002', 'esp004', 'esp005', 'esp006']) {
      _publish('/comando/$id', '{"comando": "data"}');
    }
  }

  void _publish(String topic, String message) {
    if (_isConnected) {
      client.publishMessage(
        topic,
        MqttQos.atMostOnce,
        MqttClientPayloadBuilder().addString(message).payload!,
      );
    }
  }

  void _setupListener() {
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final recMess = c[0].payload as MqttPublishMessage;
      final topic = c[0].topic;
      final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      if (kDebugMode) print('Recebido: $topic = $payload');

      setState(() {
        final data = parsePayload(payload);
        if (data['id'] != null) {
          if (data['estado_rele'] != null) {
            relayStates[data['id']] = data['estado_rele'];
          }
          if (data['temp'] != null && data['umid'] != null) {
            sensors[data['id']] = {
              'temp': data['temp'],
              'umid': data['umid'],
            };
          }
        }
      });
    });
  }

  Map<String, dynamic> parsePayload(String payload) {
    try {
      return jsonDecode(payload);
    } catch (e) {
      if (kDebugMode) print('Erro ao parsear payload: $e');
      return {};
    }
  }

  void _toggleRelay(String id) {
    if (id.length == 7) {
      String id7 = id[6];
      String idEsp = '${id.substring(0, 6)}x';
      _publish('/comando/$idEsp', '{"comando": "$id7"}');
    } else {
      _publish('/comando/$id', '{"comando": "toggle"}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Home Automation',
          style: TextStyle(
            fontFamily: 'Marmelad',
            fontSize: 26.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.indigo[300],
        actions: [
          Icon(
            _isConnected ? Icons.wifi : Icons.wifi_off,
            color: _isConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Sensores
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: sensors.entries.map((entry) {
                String sala = nomeSala[entry.key] ?? entry.key;
                final data = entry.value;
                return Column(
                  children: [
                    Text(
                      sala,
                      style: const TextStyle(
                        fontFamily: 'Marmelad',
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      '${data['temp']?.toStringAsFixed(1)}°C\n${data['umid']?.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontFamily: 'Marmelad',
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const Divider(color: Colors.white54),
          // Relés
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8.0),
              children: relayStates.entries.map((entry) {
                final id = entry.key;
                final state = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      side: const BorderSide(color: Colors.white30, width: 1.0),
                      elevation: 5.0,
                      fixedSize: const Size(250.0, 30.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5.0),
                      ),
                      backgroundColor: state == 'on'
                          ? Colors.lightBlueAccent[400]
                          : Colors.white24,
                      foregroundColor:
                      state == 'on' ? Colors.black87 : Colors.white70,
                    ),
                    onPressed: () => _toggleRelay(id),
                    child: Text(
                      '${id.padRight(7, ' ')}: ${state.toUpperCase().padLeft(3, ' ')}',
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}