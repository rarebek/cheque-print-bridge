import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Cheque Printer Demo'),
    );
  }
}

class PrinterService {
  static const MethodChannel _channel = MethodChannel('com.example.xprinter/printer');

  // Scan for Bluetooth devices
  static Future<List<Map<String, dynamic>>> scanDevices() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('scanDevices');
      return List<Map<String, dynamic>>.from(result);
    } on PlatformException catch (e) {
      throw 'Failed to scan devices: ${e.message}';
    }
  }

  // Connect to a device
  static Future<bool> connectDevice(String deviceId) async {
    try {
      return await _channel.invokeMethod('connectDevice', {'deviceId': deviceId});
    } on PlatformException catch (e) {
      throw 'Failed to connect: ${e.message}';
    }
  }

  // Disconnect current device
  static Future<bool> disconnectDevice() async {
    try {
      return await _channel.invokeMethod('disconnectDevice');
    } on PlatformException catch (e) {
      throw 'Failed to disconnect: ${e.message}';
    }
  }

  // Print test receipt
  static Future<bool> printTestReceipt() async {
    try {
      return await _channel.invokeMethod('printTestReceipt');
    } on PlatformException catch (e) {
      throw 'Failed to print test receipt: ${e.message}';
    }
  }

  // Print cheque with provided details
  static Future<bool> printCheque({
    required String payeeName,
    required String amount,
    required String date,
    required String chequeNumber,
    required String accountNumber,
    String bankName = 'My Bank',
    String additionalInfo = '',
  }) async {
    try {
      return await _channel.invokeMethod('printCheque', {
        'payeeName': payeeName,
        'amount': amount,
        'date': date,
        'chequeNumber': chequeNumber,
        'accountNumber': accountNumber,
        'bankName': bankName,
        'additionalInfo': additionalInfo,
      });
    } on PlatformException catch (e) {
      throw 'Failed to print cheque: ${e.message}';
    }
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Map<String, dynamic>> _devices = [];
  String? _selectedDeviceId;
  bool _isConnected = false;
  bool _isLoading = false;

  final _payeeController = TextEditingController();
  final _amountController = TextEditingController();
  final _chequeNumberController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _bankNameController = TextEditingController(text: 'My Bank');
  final _additionalInfoController = TextEditingController();

  @override
  void dispose() {
    _payeeController.dispose();
    _amountController.dispose();
    _chequeNumberController.dispose();
    _accountNumberController.dispose();
    _bankNameController.dispose();
    _additionalInfoController.dispose();
    super.dispose();
  }

  Future<void> _scanDevices() async {
    setState(() => _isLoading = true);
    try {
      final devices = await PrinterService.scanDevices();
      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    } catch (e) {
      _showError('Scan failed: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _connectDevice() async {
    if (_selectedDeviceId == null) return;

    setState(() => _isLoading = true);
    try {
      final success = await PrinterService.connectDevice(_selectedDeviceId!);
      setState(() {
        _isConnected = success;
        _isLoading = false;
      });
      if (success) {
        _showMessage('Connected successfully');
      }
    } catch (e) {
      _showError('Connection failed: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _disconnectDevice() async {
    setState(() => _isLoading = true);
    try {
      final success = await PrinterService.disconnectDevice();
      setState(() {
        _isConnected = !success;
        _isLoading = false;
      });
      if (success) {
        _showMessage('Disconnected successfully');
      }
    } catch (e) {
      _showError('Disconnection failed: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _printTestReceipt() async {
    if (!_isConnected) {
      _showError('Please connect to a printer first');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await PrinterService.printTestReceipt();
      setState(() => _isLoading = false);
      _showMessage('Test receipt printed');
    } catch (e) {
      _showError('Printing failed: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _printCheque() async {
    if (!_isConnected) {
      _showError('Please connect to a printer first');
      return;
    }

    if (_payeeController.text.isEmpty ||
        _amountController.text.isEmpty ||
        _chequeNumberController.text.isEmpty ||
        _accountNumberController.text.isEmpty) {
      _showError('Please fill in all required fields');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await PrinterService.printCheque(
        payeeName: _payeeController.text,
        amount: _amountController.text,
        date: DateTime.now().toString().split(' ')[0], // Today's date
        chequeNumber: _chequeNumberController.text,
        accountNumber: _accountNumberController.text,
        bankName: _bankNameController.text,
        additionalInfo: _additionalInfoController.text,
      );
      setState(() => _isLoading = false);
      _showMessage('Cheque printed successfully');
    } catch (e) {
      _showError('Printing failed: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Printer Connection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _scanDevices,
                            child: const Text('Scan for Printers'),
                          ),
                          const SizedBox(height: 8),
                          if (_devices.isNotEmpty) ...[
                            DropdownButton<String>(
                              isExpanded: true,
                              hint: const Text('Select a printer'),
                              value: _selectedDeviceId,
                              items: _devices.map((device) {
                                return DropdownMenuItem<String>(
                                  value: device['id'],
                                  child: Text(device['name']),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedDeviceId = value;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                  onPressed: _isConnected ? null : _connectDevice,
                                  child: const Text('Connect'),
                                ),
                                ElevatedButton(
                                  onPressed: _isConnected ? _disconnectDevice : null,
                                  child: const Text('Disconnect'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isConnected) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Cheque Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _payeeController,
                              decoration: const InputDecoration(
                                labelText: 'Payee Name *',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _amountController,
                              decoration: const InputDecoration(
                                labelText: 'Amount *',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _chequeNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Cheque Number *',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _accountNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Account Number *',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _bankNameController,
                              decoration: const InputDecoration(
                                labelText: 'Bank Name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _additionalInfoController,
                              decoration: const InputDecoration(
                                labelText: 'Additional Information',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                  onPressed: _printTestReceipt,
                                  child: const Text('Print Test Receipt'),
                                ),
                                ElevatedButton(
                                  onPressed: _printCheque,
                                  child: const Text('Print Cheque'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
