import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Printer Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PrinterScreen(),
    );
  }
}

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({Key? key}) : super(key: key);

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  static const platform = MethodChannel('com.example.xprinter/printer');

  List<Map<String, dynamic>> _devices = [];
  String _status = 'Not connected';
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  String? _connectedDeviceId;

  // Controllers for cheque details
  final _payeeController = TextEditingController();
  final _amountController = TextEditingController();
  final _chequeNumberController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _bankNameController = TextEditingController(text: 'My Bank');
  final _additionalInfoController = TextEditingController();

  // Additional controllers for receipt printing
  final _companyNameController = TextEditingController(text: 'My Company');
  final _sellerController = TextEditingController();
  final _receiverController = TextEditingController();
  final _supplierController = TextEditingController();
  final _paymentMethodController = TextEditingController(text: 'Naqd');

  // Product details controllers
  final _productNameController = TextEditingController();
  final _productQuantityController = TextEditingController(text: '1.0');
  final _productUnitController = TextEditingController(text: 'pcs');
  final _productPriceController = TextEditingController(text: '0.0');

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _payeeController.dispose();
    _amountController.dispose();
    _chequeNumberController.dispose();
    _accountNumberController.dispose();
    _bankNameController.dispose();
    _additionalInfoController.dispose();
    _companyNameController.dispose();
    _sellerController.dispose();
    _receiverController.dispose();
    _supplierController.dispose();
    _paymentMethodController.dispose();
    _productNameController.dispose();
    _productQuantityController.dispose();
    _productUnitController.dispose();
    _productPriceController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    if (await Permission.bluetooth.request().isGranted &&
        await Permission.bluetoothScan.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted) {
      // Permissions granted
    }
  }

  Future<void> _scanDevices() async {
    setState(() {
      _isScanning = true;
      _devices = [];
      _status = 'Scanning...';
    });

    try {
      final List<dynamic> result = await platform.invokeMethod('scanDevices');
      setState(() {
        _devices = List<Map<String, dynamic>>.from(
          result.map((device) =>
            Map<String, dynamic>.from({
              'id': device['id']?.toString() ?? '',
              'name': device['name']?.toString() ?? 'Unknown Device'
            })
          )
        );
        _status = 'Found ${_devices.length} devices';
        _isScanning = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Failed to scan: ${e.message}';
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(String deviceId, String deviceName) async {
    setState(() {
      _isConnecting = true;
      _status = 'Connecting to $deviceName...';
    });

    try {
      final bool result = await platform.invokeMethod('connectDevice', {
        'deviceId': deviceId,
      });

      setState(() {
        if (result) {
          _status = 'Connected to $deviceName';
          _connectedDeviceId = deviceId;
        } else {
          _status = 'Failed to connect to $deviceName';
          _connectedDeviceId = null;
        }
        _isConnecting = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Connection error: ${e.message}';
        _isConnecting = false;
        _connectedDeviceId = null;
      });
    }
  }

  Future<void> _printTestReceipt() async {
    if (_connectedDeviceId == null) {
      setState(() {
        _status = 'Not connected to any printer';
      });
      return;
    }

    setState(() {
      _isPrinting = true;
      _status = 'Printing test receipt...';
    });

    try {
      final bool result = await platform.invokeMethod('printTestReceipt');

      setState(() {
        _status = result ? 'Test receipt printed successfully' : 'Failed to print test receipt';
        _isPrinting = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Printing error: ${e.message}';
        _isPrinting = false;
      });
    }
  }

  Future<void> _printCheque() async {
    if (_connectedDeviceId == null) {
      setState(() {
        _status = 'Not connected to any printer';
      });
      return;
    }

    if (_payeeController.text.isEmpty ||
        _amountController.text.isEmpty ||
        _chequeNumberController.text.isEmpty ||
        _accountNumberController.text.isEmpty) {
      setState(() {
        _status = 'Please fill in all required fields';
      });
      return;
    }

    setState(() {
      _isPrinting = true;
      _status = 'Printing cheque...';
    });

    try {
      // Create a complete receipt data object similar to example-cheque-print.dart
      final companyName = _companyNameController.text;
      final transactionId = _chequeNumberController.text;
      final currentDate = DateTime.now();
      final formattedDate = "${currentDate.toIso8601String()}";

      // Create product list
      final products = [];
      if (_productNameController.text.isNotEmpty && _productQuantityController.text.isNotEmpty) {
        final productPrice = double.tryParse(_productPriceController.text) ?? 0.0;
        final productQuantity = double.tryParse(_productQuantityController.text) ?? 0.0;

        products.add({
          "name": _productNameController.text,
          "quantity": productQuantity,
          "unitName": _productUnitController.text,
          "currentPrice": productPrice,
          "status": 1
        });
      }

      // Calculate total
      double totalAmount = 0.0;
      for (final product in products) {
        totalAmount += (product["currentPrice"] as double) * (product["quantity"] as double);
      }

      // Create payment methods
      final paymentMethods = [];
      if (_paymentMethodController.text.isNotEmpty) {
        final methodId = _paymentMethodController.text == "Naqd" ? 1 : 2;
        paymentMethods.add({
          "methodId": methodId,
          "amount": totalAmount
        });
      }

      final bool result = await platform.invokeMethod('printCheque', {
        "companyName": companyName,
        "transactionId": transactionId,
        "createdAt": formattedDate,
        "status": 1,
        "statusName": "",
        "seller": _sellerController.text,
        "receiver": _receiverController.text,
        "supplierName": _supplierController.text,
        "totalAmount": totalAmount,
        "finalAmount": totalAmount,
        "products": products,
        "paymentMethods": paymentMethods
      });

      setState(() {
        _status = result ? 'Cheque printed successfully' : 'Failed to print cheque';
        _isPrinting = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Printing error: ${e.message}';
        _isPrinting = false;
      });
    }
  }

  Future<void> _disconnectDevice() async {
    if (_connectedDeviceId == null) return;

    try {
      await platform.invokeMethod('disconnectDevice');
      setState(() {
        _status = 'Disconnected';
        _connectedDeviceId = null;
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Disconnect error: ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Printer Demo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Status: $_status'),
                ElevatedButton(
                  onPressed: _connectedDeviceId != null
                      ? _disconnectDevice
                      : (_isScanning ? null : _scanDevices),
                  child: Text(_connectedDeviceId != null
                      ? 'Disconnect'
                      : (_isScanning ? 'Scanning...' : 'Scan')),
                ),
              ],
            ),
          ),
          Expanded(
            child: _devices.isEmpty
                ? (_connectedDeviceId != null
                    ? _buildChequeForm()
                    : Center(
                        child: Text(_isScanning
                            ? 'Scanning for devices...'
                            : 'No devices found. Tap Scan to start.'),
                      ))
                : (_connectedDeviceId != null
                    ? _buildChequeForm()
                    : ListView.builder(
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          final bool isConnected =
                              _connectedDeviceId == device['id'];

                          return ListTile(
                            leading: Icon(
                              Icons.print,
                              color: isConnected ? Colors.green : Colors.grey,
                            ),
                            title: Text(device['name'] ?? 'Unknown Device'),
                            subtitle: Text(device['id']),
                            trailing: isConnected
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                            onTap: (_isConnecting || isConnected)
                                ? null
                                : () => _connectToDevice(
                                      device['id'],
                                      device['name'] ?? 'Unknown Device',
                                    ),
                          );
                        },
                      )),
          ),
          if (_connectedDeviceId != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isPrinting ? null : _printTestReceipt,
                      child: Text(
                        _isPrinting ? 'Printing...' : 'Print Test Receipt',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isPrinting ? null : _printCheque,
                      child: Text(
                        _isPrinting ? 'Printing...' : 'Print Cheque',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChequeForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cheque Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Company details
          TextField(
            controller: _companyNameController,
            decoration: const InputDecoration(
              labelText: 'Company Name *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),

          // Transaction ID (cheque number)
          TextField(
            controller: _chequeNumberController,
            decoration: const InputDecoration(
              labelText: 'Chek raqami (Transaction ID) *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),

          // Personnel
          TextField(
            controller: _sellerController,
            decoration: const InputDecoration(
              labelText: 'Kassir (Seller/Cashier)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _supplierController,
            decoration: const InputDecoration(
              labelText: 'Ta\'minotchi (Supplier)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _receiverController,
            decoration: const InputDecoration(
              labelText: 'Qabul qiluvchi (Receiver)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),

          // Product section
          const Divider(),
          const Text(
            'Product Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _productNameController,
            decoration: const InputDecoration(
              labelText: 'Product Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _productQuantityController,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _productUnitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _productPriceController,
            decoration: const InputDecoration(
              labelText: 'Price',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),

          // Payment method
          const Divider(),
          const Text(
            'Payment Method',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          DropdownButtonFormField<String>(
            value: _paymentMethodController.text,
            decoration: const InputDecoration(
              labelText: 'Payment Method',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Naqd', child: Text('Naqd (Cash)')),
              DropdownMenuItem(value: 'Plastik', child: Text('Plastik (Card)')),
            ],
            onChanged: (value) {
              if (value != null) {
                _paymentMethodController.text = value;
              }
            },
          ),

          // Legacy fields (kept for compatibility)
          const SizedBox(height: 16),
          const Divider(),
          const Text(
            'Additional Fields (Optional)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _payeeController,
            decoration: const InputDecoration(
              labelText: 'Payee Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _amountController,
            decoration: const InputDecoration(
              labelText: 'Amount',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _accountNumberController,
            decoration: const InputDecoration(
              labelText: 'Account Number',
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
        ],
      ),
    );
  }
}
