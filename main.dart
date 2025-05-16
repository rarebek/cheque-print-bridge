import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'lib/cheque_formatter.dart';
import 'cheque_designer.dart';

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

  // Current template data from the designer
  Map<String, dynamic>? _templateData;

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

    setState(() {
      _isPrinting = true;
      _status = 'Printing cheque...';
    });

    try {
      // Create the cheque data, using template data if available
      Map<String, dynamic> chequeData;

      if (_templateData != null) {
        chequeData = Map<String, dynamic>.from(_templateData!);

        // Update with current form values
        if (_companyNameController.text.isNotEmpty) {
          chequeData["companyName"] = _companyNameController.text;
        }

        if (_chequeNumberController.text.isNotEmpty) {
          chequeData["transactionId"] = _chequeNumberController.text;
        }

        if (_sellerController.text.isNotEmpty) {
          chequeData["seller"] = _sellerController.text;
        }

        if (_receiverController.text.isNotEmpty) {
          chequeData["receiver"] = _receiverController.text;
        }

        if (_supplierController.text.isNotEmpty) {
          chequeData["supplierName"] = _supplierController.text;
        }

        // Add or update product if provided
        if (_productNameController.text.isNotEmpty) {
          final productPrice = double.tryParse(_productPriceController.text) ?? 0.0;
          final productQuantity = double.tryParse(_productQuantityController.text) ?? 1.0;

          final newProduct = {
            "name": _productNameController.text,
            "quantity": productQuantity,
            "unitName": _productUnitController.text.isNotEmpty ? _productUnitController.text : "dona",
            "currentPrice": productPrice,
            "status": 1
          };

          // Add to products list or create new list
          if (chequeData.containsKey("products")) {
            (chequeData["products"] as List).add(newProduct);
          } else {
            chequeData["products"] = [newProduct];
          }
        }

        // Recalculate total
        double totalAmount = 0.0;
        for (final product in (chequeData["products"] as List)) {
          totalAmount += (product["currentPrice"] as double) * (product["quantity"] as double);
        }

        chequeData["totalAmount"] = totalAmount;
        chequeData["finalAmount"] = totalAmount;

        // Update payment method if provided
        chequeData["paymentMethods"] = [{
          "methodId": _paymentMethodController.text == "Plastik" ? 2 : 1,
          "amount": totalAmount
        }];
      } else {
        // Use default data from form inputs if no template
        final companyName = _companyNameController.text.isNotEmpty ? _companyNameController.text : "MyStore1";
        final transactionId = _chequeNumberController.text.isNotEmpty ? _chequeNumberController.text : "00000001";
        final currentDate = DateTime.now();
        final formattedDate = "${currentDate.toIso8601String()}";

        // Create product list with at least one default product if none provided
        final products = [];
        if (_productNameController.text.isNotEmpty) {
          final productPrice = double.tryParse(_productPriceController.text) ?? 0.0;
          final productQuantity = double.tryParse(_productQuantityController.text) ?? 1.0;

          products.add({
            "name": _productNameController.text,
            "quantity": productQuantity,
            "unitName": _productUnitController.text.isNotEmpty ? _productUnitController.text : "dona",
            "currentPrice": productPrice,
            "status": 1
          });
        } else {
          // Add a default product if none provided
          products.add({
            "name": "Test Product",
            "quantity": 1.0,
            "unitName": "dona",
            "currentPrice": 10000.0,
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
        paymentMethods.add({
          "methodId": _paymentMethodController.text == "Plastik" ? 2 : 1,
          "amount": totalAmount
        });

        chequeData = {
          "companyName": companyName,
          "transactionId": transactionId,
          "createdAt": formattedDate,
          "status": 1,
          "statusName": "",
          "seller": _sellerController.text.isNotEmpty ? _sellerController.text : "Default Seller",
          "receiver": _receiverController.text,
          "supplierName": _supplierController.text,
          "totalAmount": totalAmount,
          "finalAmount": totalAmount,
          "products": products,
          "paymentMethods": paymentMethods
        };
      }

      // Format the cheque in Flutter
      final rawCommandsData = ChequeFormatter.formatCheque(
        chequeDetails: chequeData,
        pageWidth: 32,
        useAutoCut: true,
        feedLineCount: 4,
      );

      // Pass the raw command data to Swift
      final bool result = await platform.invokeMethod('printCheque', {
        "rawCommandsData": rawCommandsData,
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

  // Add a new method for printing test with two products
  Future<void> _printTwoProductsTest() async {
    if (_connectedDeviceId == null) {
      setState(() {
        _status = 'Not connected to any printer';
      });
      return;
    }

    setState(() {
      _isPrinting = true;
      _status = 'Printing two products test...';
    });

    try {
      // Create a receipt with two products
      final List<Map<String, dynamic>> testProducts = [
        {
          "name": "Product with ʻ special char",
          "quantity": 2.0,
          "unitName": "dona",
          "currentPrice": 10000.0,
          "status": 1
        },
        {
          "name": "This is a long product name that should wrap nicely",
          "quantity": 1.0,
          "unitName": "kg",
          "currentPrice": 25000.0,
          "status": 1
        }
      ];

      // Calculate total
      double totalAmount = 0.0;
      for (final product in testProducts) {
        totalAmount += (product["currentPrice"] as double) * (product["quantity"] as double);
      }

      // Create payment methods
      final paymentMethods = [
        {"methodId": 1, "amount": totalAmount / 2},
        {"methodId": 2, "amount": totalAmount / 2}
      ];

      // Show dialog to select transaction type
      final transactionType = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Receipt Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 1),
                child: const Text('Sales Receipt'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 2),
                child: const Text('Purchase Receipt'),
              ),
            ],
          ),
        ),
      );

      if (transactionType == null) {
        setState(() {
          _isPrinting = false;
          _status = 'Printing cancelled';
        });
        return;
      }

      // Build receipt data based on transaction type
      final Map<String, dynamic> receiptData = {
        "companyName": "TEST COMPANY",
        "transactionId": "T${DateTime.now().millisecondsSinceEpoch}",
        "createdAt": DateTime.now().toIso8601String(),
        "status": 1,
        "statusName": "",
        "totalAmount": totalAmount,
        "finalAmount": totalAmount,
        "products": testProducts,
        "paymentMethods": paymentMethods
      };

      // Add type-specific fields
      if (transactionType == 1) {
        // Sale receipt
        receiptData["seller"] = "Test Seller";
      } else {
        // Purchase receipt
        receiptData["supplierName"] = "Test Supplier";
        receiptData["receiver"] = "Test Receiver";
      }

      // Format the cheque in Flutter
      final rawCommandsData = ChequeFormatter.formatCheque(
        chequeDetails: receiptData,
        pageWidth: 32,
        useAutoCut: true,
        feedLineCount: 4,
      );

      // Pass the raw command data to Swift
      final bool result = await platform.invokeMethod('printCheque', {
        "rawCommandsData": rawCommandsData,
      });

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

  // Add method to open the designer screen
  Future<void> _openChequeDesigner() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const ChequeDesignerPage()),
    );

    if (result != null) {
      setState(() {
        _templateData = result;
        _status = 'Template saved. Ready to print.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Printer Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.design_services),
            onPressed: _openChequeDesigner,
            tooltip: 'Design Cheque Template',
          ),
        ],
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
              child: Column(
                children: [
                  // Show template status if available
                  if (_templateData != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Custom template loaded from Designer',
                              style: TextStyle(color: Colors.green[800]),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _templateData = null;
                              });
                            },
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ),

                  // Existing buttons
                  Row(
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
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isPrinting ? null : _printTwoProductsTest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        _isPrinting ? 'Printing...' : 'Test Two Products',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _openChequeDesigner,
                      child: const Text('Design Custom Cheque'),
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
        ],
      ),
    );
  }
}
