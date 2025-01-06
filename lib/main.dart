
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:math';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Command Sender',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ScanScreen(),
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    startScan();
  }

  void startScan() async {
    setState(() => _isScanning = true);

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results;
      });
    }).onError((e) {
      print('Scan error: $e');
    });

    FlutterBluePlus.isScanning.listen((isScanning) {
      if (!isScanning) {
        setState(() => _isScanning = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Scanner')),
      body: _isScanning
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: _scanResults.length,
        itemBuilder: (context, index) {
          final result = _scanResults[index];
          return ListTile(
            title: Text(result.device.platformName.isNotEmpty
                ? result.device.platformName
                : 'Unknown Device'),
            subtitle: Text(result.device.remoteId.toString()),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CommandScreen(
                    device: result.device,
                    initialRssi: result.rssi,
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: startScan,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class CommandScreen extends StatefulWidget {
  final BluetoothDevice device;
  final int initialRssi;

  const CommandScreen({required this.device, required this.initialRssi, super.key});

  @override
  State<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends State<CommandScreen> {
  bool _isConnecting = false;
  bool _isConnected = false;
  BluetoothCharacteristic? _targetCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;
  String _status = "No status received yet";
  int _currentRssi = 0;
  Timer? _rssiPoller;

  @override
  void initState() {
    super.initState();
    _currentRssi = widget.initialRssi;
    _connectToDeviceAndFindCharacteristic();
    _startRssiPolling();
  }

  Future<void> _connectToDeviceAndFindCharacteristic() async {
    setState(() => _isConnecting = true);

    try {
      await widget.device.connect();
      List<BluetoothService> services = await widget.device.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == '12345678-1234-5678-1234-56789abcdef1') {
            _targetCharacteristic = characteristic;
          } else if (characteristic.uuid.toString() == '12345678-1234-5678-1234-56789abcdef2') {
            _statusCharacteristic = characteristic;
            await _statusCharacteristic!.setNotifyValue(true);
            _statusCharacteristic!.lastValueStream.listen((value) {
              setState(() {
                _status = String.fromCharCodes(value);
              });
              print('Notification received: $_status');
            });
          }
        }
      }
      setState(() {
        _isConnecting = false;
        _isConnected = true;
      });
    } catch (e) {
      print('Connection error: $e');
      setState(() {
        _isConnecting = false;
        _isConnected = false;
      });
    }
  }

  void _startRssiPolling() {
    _rssiPoller = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final rssi = await widget.device.readRssi();
        setState(() {
          _currentRssi = rssi;
        });
        print('Updated RSSI: $rssi');
      } catch (e) {
        print('Error reading RSSI: $e');
      }
    });
  }

  num calculateDistance(int rssi) {
    const int txPower = -59; // Adjust based on your device's TX power
    return pow(10, (txPower - rssi) / 20.0);
  }

  void sendCommand(String command) async {
    if (_targetCharacteristic == null) {
      print('Target characteristic not found.');
      return;
    }
    try {
      String dataToSend = command;
      if (command == 'start') {
        final distance = calculateDistance(_currentRssi);
        dataToSend = '$command:$distance';
      }
      await _targetCharacteristic!.write(dataToSend.codeUnits, withoutResponse: false);
      print('Sent command: $dataToSend');
    } catch (e) {
      print('Error sending command: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.platformName)),
      body: _isConnecting
          ? const Center(child: CircularProgressIndicator())
          : _isConnected
          ? Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () => sendCommand('start'),
                child: const Text('Start'),
              ),
              ElevatedButton(
                onPressed: () => sendCommand('stop'),
                child: const Text('Stop'),
              ),
              ElevatedButton(
                onPressed: () => sendCommand('calibrate'),
                child: const Text('Calibrate'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Status: $_status',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      )
          : const Center(child: Text('Failed to connect to device.')),
    );
  }

  @override
  void dispose() {
    _rssiPoller?.cancel();
    widget.device.disconnect();
    super.dispose();
  }
}
