import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// import 'package:google_fonts/google_fonts.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:my_home_app2/temperature_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

void main() {
  AppTheme.init();
  runApp(const MyApp());
}

// Extensão para mapas
extension MapX on Map<String, String> {
  String get(String key) => this[key] ?? key;
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Home Automation',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const MyHomePage(),
        );
      },
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
  Map<String, String> nomeSala = {}; // Sensores (temp/umid)
  Map<String, String> nomeBotoes = {}; // Todos os botões

  Map<String, List<Map<String, double>>> tempHistory = {}; // esp001 → lista de {temp, umid}

  void _addToHistory(String id, double temp, double umid) {
    tempHistory[id] ??= [];
    tempHistory[id]!.add({'temp': temp, 'umid': umid});
    if (tempHistory[id]!.length > 50) tempHistory[id]!.removeAt(0); // limite
  }

  bool _isConnected = false;
  bool _isReconnecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // AppTheme.init();
    _loadAllNames(); // Carrega tudo do disco
    _initMqttClient();
  }





  Future<void> _loadAllNames() async {
    final prefs = await SharedPreferences.getInstance();

    // Nomes padrão
    final defaultSalas = {
      'esp001': 'Sala 1',
      'esp002': 'Sala 2',
      'esp004': 'Sala 4',
      'esp005': 'Sala 5',
      'esp006': 'Sala 6',
    };

    final defaultBotoes = {
      'esp001': 'Luz Sala 1',
      'esp002': 'Luz Sala 2',
      'esp004': 'Luz Sala 4',
      'esp005': 'Luz Sala 5',
      'esp006': 'Luz Sala 6',
      'esp0031': 'Luz 1',
      'esp0032': 'Luz 2',
      'esp0033': 'Luz 3',
      'esp0034': 'Luz 4',
    };

    setState(() {
      // Carrega ou usa padrão
      nomeSala = {for (var id in defaultSalas.keys) id: prefs.getString('sala_$id') ?? defaultSalas[id]!};
      nomeBotoes = {for (var id in defaultBotoes.keys) id: prefs.getString('botao_$id') ?? defaultBotoes[id]!};
    });
  }

  Future<void> _saveName(String type, String id, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${type}_$id';
    await prefs.setString(key, newName);

    setState(() {
      if (type == 'sala') {
        nomeSala[id] = newName;
      } else {
        nomeBotoes[id] = newName;
      }
    });
  }

  @override
  void dispose() {
    AppTheme.dispose();
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
      client.publishMessage(topic, MqttQos.atMostOnce, MqttClientPayloadBuilder().addString(message).payload!);
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
        if (data['temp'] != null && data['umid'] != null) {
          sensors[data['id']] = {'temp': data['temp'], 'umid': data['umid']};
          _addToHistory(data['id'], data['temp'], data['umid']);
        }

        if (data['id'] != null) {
          if (data['estado_rele'] != null) {
            relayStates[data['id']] = data['estado_rele'];
          }
          if (data['temp'] != null && data['umid'] != null) {
            sensors[data['id']] = {'temp': data['temp'], 'umid': data['umid']};
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

  Future<void> _showEditDialog(String type, String id, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final isSala = type == 'sala';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.indigo[100],
        title: Text(
          isSala ? 'Editar Nome da Sala' : 'Editar Nome do Botão',
          style: const TextStyle(fontFamily: 'Marmelad'),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontFamily: 'Marmelad'),
          decoration: InputDecoration(
            hintText: isSala ? 'ex: Jardim, Varanda...' : 'ex: Luz TV, Ar Condicionado...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                _saveName(type, id, newName);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.indigo[100],
        title: const Text('Resetar Nomes?', style: TextStyle(fontFamily: 'Marmelad')),
        content: const Text('Todos os nomes voltarão ao padrão. Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Resetar'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // Limpa tudo
      await _loadAllNames(); // Recarrega padrões
      if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nomes resetados!'), backgroundColor: Colors.green));
    }}
  }

  Widget _buildAnimatedRelayButton(String id, String state) {
    final isOn = state == 'on';
    final buttonName = nomeBotoes[id] ?? id; // Nome personalizado

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5.0),
          color: isOn ? Colors.lightBlueAccent[400] : Colors.white24,
          boxShadow: isOn
              ? [BoxShadow(color: Colors.lightBlueAccent.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 2)]
              : [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(5.0),
            splashColor: isOn ? Colors.white.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.3),
            onTap: () => _toggleRelay(id),
            onLongPress: () => _showEditDialog('botao', id, buttonName),
            child: Container(
              width: 250.0,
              height: 50.0,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      buttonName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isOn ? Colors.black87 : Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    state.toUpperCase(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isOn ? Colors.black87 : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sensorTile(String id, Map<String, double> data) {
    return GestureDetector(
      onLongPress: () => _showEditDialog('sala', id, nomeSala.get(id)),
      child: Column(
        children: [
          Text(
            nomeSala.get(id),
            style: const TextStyle(fontFamily: 'Marmelad', fontWeight: FontWeight.bold, fontSize: 20),
          ),
          Text(
            '${data['temp']?.toStringAsFixed(1)}°C\n${data['umid']?.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 18, fontFamily: 'Marmelad', color: Colors.white),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (tempHistory['esp001']?.isNotEmpty == true) {
      TemperatureChart(history: tempHistory['esp001']!, sala: nomeSala['esp001'] ?? 'Sala 1');
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Home Automation',
          style: TextStyle(fontFamily: 'Marmelad', fontSize: 26, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo[300],
        actions: [
          // Ícone de conexão
          AnimatedOpacity(
            opacity: _isConnected ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 500),
            child: Icon(_isConnected ? Icons.wifi : Icons.wifi_off, color: _isConnected ? Colors.green : Colors.red),
          ),
          const SizedBox(width: 8),

          // Botão Reset
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Resetar nomes',
            onPressed: _showResetDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Sensores
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,

              children: sensors.entries.map((e) => _sensorTile(e.key, e.value)).toList(),




            ),
          ),
          const Divider(color: Colors.white54),
          // if (tempHistory['esp001']?.isNotEmpty == true)
          //   TemperatureChart(
          //     history: tempHistory['esp001']!,
          //     sala: nomeSala['esp001'] ?? 'Sala 1',
          //   ),
          // Botões
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: relayStates.length,
              itemBuilder: (_, i) {
                final e = relayStates.entries.elementAt(i);
                return _buildAnimatedRelayButton(e.key, e.value);
              },
            ),
          ),
        ],
      ),
    );
  }
}
