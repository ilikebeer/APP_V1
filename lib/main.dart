import 'dart:async';

import 'package:flutter/material.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ModbusSmartHomeApp());
}

class ModbusSmartHomeApp extends StatelessWidget {
  const ModbusSmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Modbus TCP Smart Home',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0288D1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final TextEditingController _ipController =
      TextEditingController(text: '192.168.178.104');
  final TextEditingController _portController = TextEditingController(text: '502');
  final TextEditingController _unitIdController = TextEditingController(text: '1');

  bool _isConnected = false;
  ModbusClientTcp? _modbusClient;
  Timer? _pollingTimer;

  final List<Map<String, dynamic>> _registers = [
    {
      'address': 40070,
      'name': 'Batterie_Leistung',
      'desc': 'Batterie-Leistung in Watt',
      'unit': 'W',
      'value': 0,
    },
    {
      'address': 40072,
      'name': 'Hausverbrauch_Leistung',
      'desc': 'Hausverbrauchs-Leistung in Watt',
      'unit': 'W',
      'value': 0,
    },
    {
      'address': 40074,
      'name': 'Netz_Leistung',
      'desc': 'Leistung am Netzübergabepunkt in Watt',
      'unit': 'W',
      'value': 0,
    },
    {
      'address': 40076,
      'name': 'Externe_Quelle',
      'desc': 'Leistung Externe Quelle',
      'unit': 'W',
      'value': 0,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _modbusClient?.disconnect();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ipController.text = prefs.getString('modbus_ip') ?? '192.168.178.104';
      _portController.text = prefs.getString('modbus_port') ?? '502';
      _unitIdController.text = prefs.getString('modbus_unit_id') ?? '1';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('modbus_ip', _ipController.text.trim());
    await prefs.setString('modbus_port', _portController.text.trim());
    await prefs.setString('modbus_unit_id', _unitIdController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verbindungseinstellungen gespeichert!')),
    );
  }

  Future<void> _toggleConnection() async {
    if (_isConnected) {
      _pollingTimer?.cancel();
      await _modbusClient?.disconnect();
      setState(() => _isConnected = false);
      return;
    }

    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text) ?? 502;
    final unitId = int.tryParse(_unitIdController.text) ?? 1;

    _modbusClient = ModbusClientTcp(
      ip,
      serverPort: port,
      unitId: unitId,
      connectionTimeout: const Duration(seconds: 3),
      responseTimeout: const Duration(seconds: 3),
    );

    try {
      final connected = await _modbusClient!.connect();
      setState(() => _isConnected = connected);

      if (connected) {
        _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) => _readRegisters());
        await _readRegisters();
      }
    } catch (e) {
      setState(() => _isConnected = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verbindungsfehler: $e')),
      );
    }
  }

  Future<void> _readRegisters() async {
    if (_modbusClient == null || !_isConnected) return;

    final unitId = int.tryParse(_unitIdController.text) ?? 1;

    for (final reg in _registers) {
      final int address = reg['address'] as int;
      final int rawAddress = address >= 40001 ? address - 40001 : address;

      final element = ModbusInt32Register(
        name: reg['name'] as String,
        description: reg['desc'] as String,
        type: ModbusElementType.holdingRegister,
        address: rawAddress,
        endianness: ModbusEndianness.CDAB,
        uom: reg['unit'] as String,
      );

      try {
        final request = element.getReadRequest(unitId: unitId);
        final responseCode = await _modbusClient!.send(request);

        if (responseCode == ModbusResponseCode.requestSucceed &&
            element.value != null) {
          setState(() {
            reg['value'] = element.value as int;
          });
        }
      } catch (e) {
        debugPrint('Fehler beim Lesen von Register $address: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modbus TCP App'),
        backgroundColor: const Color(0xFF0288D1),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amber,
          tabs: const [
            Tab(text: 'VERBINDUNG'),
            Tab(text: 'HOLDING-REGISTER'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildVerbindungTab(),
          _buildHoldingRegisterTab(),
        ],
      ),
    );
  }

  Widget _buildVerbindungTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Modbus TCP Verbindungseinstellungen',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'Slave-Adresse / IP-Adresse',
              hintText: '192.168.178.104',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '502',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: TextField(
                  controller: _unitIdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Geräte-ID (Unit ID)',
                    hintText: '1',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save),
                  label: const Text('Speichern'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: _isConnected ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _toggleConnection,
                  icon: Icon(_isConnected ? Icons.power_off : Icons.power),
                  label: Text(_isConnected ? 'Trennen' : 'Verbinden'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHoldingRegisterTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _registers.length,
      itemBuilder: (context, index) {
        final reg = _registers[index];
        final int val = reg['value'] as int;
        final String unit = reg['unit'] as String;

        Color valColor = Colors.black;
        if (val > 0) valColor = Colors.green.shade700;
        if (val < 0) valColor = Colors.red.shade700;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF0288D1),
              foregroundColor: Colors.white,
              child: Text('${reg['address']}'),
            ),
            title: Text(
              reg['name'] as String,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(reg['desc'] as String),
            trailing: Text(
              '$val $unit',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: valColor,
              ),
            ),
          ),
        );
      },
    );
  }
}
