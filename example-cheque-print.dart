import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:intl/intl.dart';
import 'package:my_store/presentation/monitoring/models/purchase_transaction.dart';
import 'package:my_store/presentation/monitoring/models/sale_history_transaction.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
// import 'package:esc_pos_utils_plus/esc_pos_utils.dart';
import 'package:image/image.dart' as img;

import 'number_formatter.dart';


const int paperWidth = 384;

Future<void> requestBluetoothPermissions() async {
  if (await Permission.bluetoothScan.isDenied) {
    await Permission.bluetoothScan.request();
  }

  if (await Permission.bluetoothConnect.isDenied) {
    await Permission.bluetoothConnect.request();
  }

  if (await Permission.nearbyWifiDevices.isDenied) {
    await Permission.nearbyWifiDevices.request();
  }
}

Future<void> checkBluetoothPermissions() async {
  await requestBluetoothPermissions();

  bool isBluetoothScanGranted = await Permission.bluetoothScan.isGranted;
  bool isBluetoothConnectGranted = await Permission.bluetoothConnect.isGranted;
  // bool isNearbyDevicesGranted = await Permission.nearbyDevices.isGranted;

  // if (isBluetoothScanGranted && isBluetoothConnectGranted && isNearbyDevicesGranted) {
  if (isBluetoothScanGranted && isBluetoothConnectGranted ) {
    print("All required Bluetooth permissions are granted.");
  } else {
    print("Bluetooth permissions not granted. Check device settings.");
  }
}

Future<void> printSaleReceipt58mm({SaleHistoryTransaction? saleTransaction,PurchaseTransaction? purchaseTransaction}) async {
  var result = false;
  if (Platform.isIOS){
    result = await connectBLEPrinter();
  }else{
    result = await connectPrinter();
  }
  if (result){
    if(saleTransaction != null){
      await printSaleInfo(saleTransaction);
    }

    if(purchaseTransaction != null){
      await printPurchaseInfo(purchaseTransaction);
    }
  }
}

Future<bool> connectPrinter()async{
  // 1. Enable Bluetooth if not already on
  await checkBluetoothPermissions();
  bool isBluetoothOn = await PrintBluetoothThermal.bluetoothEnabled;
  print("isBluetoothOn $isBluetoothOn");
  if (!isBluetoothOn) {
    return false;
    // await PrintBluetoothThermal.enableBluetooth();
    // On Android, opens Bluetooth settings. On iOS, this has no effect (just ensure Bluetooth is on).
  }

  // 2. Get the list of paired (Android) or nearby (iOS) Bluetooth printers
  List<BluetoothInfo> pairedDevices = await PrintBluetoothThermal.pairedBluetooths;
  print("pairedDevices ${pairedDevices.length}");
  if (pairedDevices.isEmpty) {
    print('No Bluetooth printers found. Please pair the printer first.');
    return false;
  }

  // Find the XP-365B printer in the list by name (if multiple devices found)
  BluetoothInfo printer;
  try {
    printer = pairedDevices.firstWhere((d) => (d.name ?? '').contains('XP-365B'));
  } catch (e) {
    printer = pairedDevices.first; // default to the first device if name not found
  }
  print('Selected printer: ${printer.name} - ${printer.macAdress}');

  // 3. Connect to the selected printer
  bool connected = await PrintBluetoothThermal.connect(macPrinterAddress: printer.macAdress);
  if (!connected) {
    print('Failed to connect to the printer.');
    return false;
  }
  print('Connected to XP-365B BLE printer.');
  return connected;
}

Future<bool> connectBLEPrinter() async {

  await checkBluetoothPermissions();

  print('Starting BLE scan...');

  bool isBluetoothOn = await PrintBluetoothThermal.bluetoothEnabled;
  if (!isBluetoothOn) {
    await PrintBluetoothThermal.bluetoothEnabled;
  }

  print('Scanning for BLE devices... (15s timeout)');
  List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;

  if (devices.isEmpty) {
    print('No Bluetooth devices found. Ensure the XP-365B is powered on and in BLE mode.');
    return false;
  }

  print('Devices found:');
  for (var device in devices) {
    print('Device: ${device.name}, Address: ${device.macAdress}');
  }

  // Identify the XP-365B printer by scanning for BLE
  BluetoothInfo? printer;
  for (var device in devices) {
    if ((device.name ?? '').contains('XP-365B') || (device.name ?? '').contains('RECEIPT') || (device.name ?? '').contains('LABEL')) {
      printer = device;
      print('Potential BLE printer detected: ${device.name}  ${device.macAdress}');
      break;
    }
  }


  if (printer == null) {
    print('XP-365B printer not found in BLE mode. Ensure it is in BLE mode and not connected to another device.');
    return false;
  }

  print('Attempting to connect to XP-365B BLE printer...');

  bool connected = await PrintBluetoothThermal.connect(macPrinterAddress: printer.macAdress);
  if (!connected) {
    print('Failed to connect. Ensure the printer is in BLE mode and not connected to another device.');
    return false;
  }
  print('Connected to XP-365B BLE printer.');
  return connected;

}


Future<void> printSaleInfo(SaleHistoryTransaction transaction)async{
  final profile = await CapabilityProfile.load();
  final generator = Generator(PaperSize.mm58, profile);
  List<int> receiptBytes = [];
  receiptBytes += generator.reset();

  //1
  try {
    ByteData logoData = await rootBundle.load('assets/images/logo-horizontal.png');
    Uint8List logoBytes = logoData.buffer.asUint8List();
    img.Image? logoImage = img.decodeImage(logoBytes);
    if (logoImage != null) {
      if (logoImage.width > 384) {
        logoImage = img.copyResize(logoImage, width: 384);
      }
      receiptBytes += generator.image(logoImage, align: PosAlign.left);
    }
  } catch (e) {
    print('Logo not found or failed to load.');
  }

  //2
  // try {
  //   ByteData logoData = await rootBundle.load('assets/images/logo-horizontal.png');
  //   Uint8List logoBytes = logoData.buffer.asUint8List();
  //   img.Image? logoImage = img.decodeImage(logoBytes);
  //
  //   if (logoImage != null) {
  //     const int paddingWidth = 40;
  //     print("logoImage.width ${logoImage.width}");
  //     int adjustedWidth = logoImage.width + paddingWidth;
  //
  //     if (adjustedWidth > 384) {
  //       adjustedWidth = 384; // Ensure it fits within 58mm width
  //     }
  //
  //     adjustedWidth = 250;
  //     // Resize with padding
  //     logoImage = img.copyResize(logoImage, width: adjustedWidth);
  //
  //     receiptBytes += generator.image(logoImage, align: PosAlign.left);
  //   }
  // } catch (e) {
  //   print('Logo not found or failed to load.');
  // }



  // Print store name and transaction date
  var createdDate1 = DateFormat('dd-MM-yyyy').format(DateTime.parse(transaction.createdAt));
  var createdDate2 = DateFormat('HH:mm').format(DateTime.parse(transaction.createdAt));
  receiptBytes += generator.text(transaction.companyName, styles: PosStyles(align: PosAlign.left, bold: true));
  receiptBytes += generator.text('Sana: $createdDate1  Vaqti: $createdDate2', styles: PosStyles(align: PosAlign.left));

  // Print transaction ID and status
  receiptBytes += generator.text('Chek raqami: ${transaction.transactionId}', styles: PosStyles(align: PosAlign.left));
  if (transaction.status != 1) {
    receiptBytes += generator.text('Holati: ${transaction.statusName}', styles: PosStyles(align: PosAlign.left));
  }

  // Print cashier info
  receiptBytes += generator.text('Kassir: ${transaction.seller}', styles: PosStyles(align: PosAlign.left));

  // Print divider
  receiptBytes += generator.hr();

  // Print product items
  for (var product in transaction.products) {

    receiptBytes += generator.row([
      PosColumn(text: '${product.name} ${product.status == 1 ? "" : "(Qaytarilgan)"}', width: 5,styles: PosStyles(align: PosAlign.left, bold: true)),
      PosColumn(text: '(${product.quantity} ${product.unitName})', width: 3,styles: PosStyles(align: PosAlign.left)),
      PosColumn(text: '${NumberFormatter.priceFormat(product.currentPrice * product.quantity)} so\'m', width: 4,styles: PosStyles(align: PosAlign.left)),
    ]);

    // receiptBytes += generator.row([
    //   PosColumn(text: '${product.name} ${product.status == 1 ? "" : "(Qaytarilgan)"}', width: 5,styles: PosStyles(align: PosAlign.left, bold: true)),
    //   PosColumn(text: '(${product.quantity} ${product.unitName})', width: 3,styles: PosStyles(align: PosAlign.left)),
    //   PosColumn(text: '${NumberFormatter.priceFormat(product.currentPrice * product.quantity)} so\'m', width: 4,styles: PosStyles(align: PosAlign.left)),
    // ]);
  }

  // Print total and tax
  receiptBytes += generator.hr();

  receiptBytes += generator.row([
    PosColumn(text: 'Umumiy summa:', width: 6,styles: PosStyles(align: PosAlign.left, bold: true)),
    PosColumn(text: '${NumberFormatter.priceFormat(transaction.finalAmount)} so\'m', width: 6,styles: PosStyles(align: PosAlign.left)),
  ]);

  receiptBytes += generator.row([
    PosColumn(text: 'QQS 15%:', width: 6,styles: PosStyles(align: PosAlign.left, bold: true)),
    PosColumn(text: '${NumberFormatter.priceFormat(transaction.finalAmount * 0.15)} so\'m', width: 6,styles: PosStyles(align: PosAlign.left)),
  ]);

  // Print payment methods
  receiptBytes += generator.hr();
  receiptBytes += generator.text('To\'lov turi:', styles: PosStyles(align: PosAlign.left, bold: true));
  for (var e in transaction.paymentMethods) {
    receiptBytes += generator.row([
      PosColumn(text: e.methodId == 1 ? "Naqd" : "Plastik", width: 6,styles: PosStyles(align: PosAlign.left, bold: true)),
      PosColumn(text: '${NumberFormatter.priceFormat(e.amount)} so\'m', width: 6,styles: PosStyles(align: PosAlign.left)),
    ]);
    receiptBytes += generator.emptyLines(1);
  }
  // Print change
  receiptBytes += generator.text('Qaytim: 0 so\'m', styles: PosStyles(align: PosAlign.left));

  // Print footer message
  receiptBytes += generator.hr();

  receiptBytes += generator.row([
    PosColumn(text:'', width: 2,styles: PosStyles(align: PosAlign.center, bold: true)),
    PosColumn(text:'Xaridingiz uchun rahmat!', width: 10,styles: PosStyles(align: PosAlign.left, bold: true)),
  ]);

  // receiptBytes += generator.emptyLines(1);

  // Print QR Code (optional)
  // receiptBytes += generator.qrcode('https://myshop.com/order/${transaction.transactionId}', size: QRSize.size6, align: PosAlign.left);

  // Cut the receipt
  receiptBytes += generator.cut();

  receiptBytes.addAll([0x1D, 0x56, 0x01]);

  print("receiptBytes ${receiptBytes.length}");

  if (Platform.isIOS){
    // Initialize printer (ESC @)
    receiptBytes.addAll([0x1B, 0x40]);
    // ESC/POS Initialize Printer (ESC @)
    receiptBytes.addAll([0x1B, 0x40]);
    await Future.delayed(const Duration(milliseconds: 100));
  }else{

  }

  // Send the receipt to the printer
  final success = await PrintBluetoothThermal.writeBytes(receiptBytes);
  print(success ? 'Print successful' : 'Print failed');

  // Disconnect from the printer
  await PrintBluetoothThermal.disconnect;
}

Future<void> printPurchaseInfo(PurchaseTransaction transaction)async{
  final profile = await CapabilityProfile.load();
  final generator = Generator(PaperSize.mm58, profile);
  List<int> receiptBytes = [];
  receiptBytes += generator.reset();

  try {
    ByteData logoData = await rootBundle.load('assets/images/logo-horizontal.png');
    Uint8List logoBytes = logoData.buffer.asUint8List();
    img.Image? logoImage = img.decodeImage(logoBytes);
    if (logoImage != null) {
      if (logoImage.width > 384) {
        logoImage = img.copyResize(logoImage, width: 384);
      }
      receiptBytes += generator.image(logoImage, align: PosAlign.left);
    }
  } catch (e) {
    print('Logo not found or failed to load.');
  }

  // Print store name and transaction date
  var createdDate1 = DateFormat('dd-MM-yyyy').format(DateTime.parse(transaction.createdAt));
  var createdDate2 = DateFormat('HH:mm').format(DateTime.parse(transaction.createdAt));
  receiptBytes += generator.text(transaction.companyName, styles: PosStyles(align: PosAlign.left, bold: true));
  receiptBytes += generator.text('Sana: $createdDate1  Vaqti: $createdDate2', styles: PosStyles(align: PosAlign.left));

  // Print transaction ID and status
  receiptBytes += generator.text('Chek raqami: ${transaction.transactionId}', styles: PosStyles(align: PosAlign.left));
  if (transaction.status != 1) {
    receiptBytes += generator.text('Holati: ${transaction.statusName}', styles: PosStyles(align: PosAlign.left));
  }

  // Print cashier info
  receiptBytes += generator.text('Ta\'minotchi: ${transaction.supplier.name}', styles: PosStyles(align: PosAlign.left));
  receiptBytes += generator.text('Qabul qiluvchi: ${transaction.receiver?.name ?? '-'}', styles: PosStyles(align: PosAlign.left));

  // Print divider
  receiptBytes += generator.hr();

  // Print product items
  for (var product in transaction.products) {

    receiptBytes += generator.row([
      PosColumn(text: '${product.name} ${product.status == 1 ? "" : "(Qaytarilgan)"}', width: 5,styles: PosStyles(align: PosAlign.left, bold: true)),
      PosColumn(text: '(${product.quantity} ${product.unitName})', width: 3,styles: PosStyles(align: PosAlign.left)),
      PosColumn(text: '${NumberFormatter.priceFormat(product.currentPrice * product.quantity)} so\'m', width: 4,styles: PosStyles(align: PosAlign.left)),
    ]);

    // receiptBytes += generator.row([
    //   PosColumn(text: '${product.name} ${product.status == 1 ? "" : "(Qaytarilgan)"}', width: 5,styles: PosStyles(align: PosAlign.left, bold: true)),
    //   PosColumn(text: '(${product.quantity} ${product.unitName})', width: 3,styles: PosStyles(align: PosAlign.left)),
    //   PosColumn(text: '${NumberFormatter.priceFormat(product.currentPrice * product.quantity)} so\'m', width: 4,styles: PosStyles(align: PosAlign.left)),
    // ]);
  }

  // Print total and tax
  receiptBytes += generator.hr();

  receiptBytes += generator.row([
    PosColumn(text: 'Umumiy summa:', width: 6,styles: PosStyles(align: PosAlign.left, bold: true)),
    PosColumn(text: '${NumberFormatter.priceFormat(transaction.totalAmount)} so\'m', width: 6,styles: PosStyles(align: PosAlign.left)),
  ]);

  receiptBytes += generator.row([
    PosColumn(text: 'QQS 15%:', width: 6,styles: PosStyles(align: PosAlign.left, bold: true)),
    PosColumn(text: '${NumberFormatter.priceFormat(transaction.totalAmount * 0.15)} so\'m', width: 6,styles: PosStyles(align: PosAlign.left)),
  ]);

  // Print payment methods
  // Print change
  receiptBytes += generator.text('Qaytim: 0 so\'m', styles: PosStyles(align: PosAlign.left));

  // receiptBytes += generator.emptyLines(1);

  // Print QR Code (optional)
  // receiptBytes += generator.qrcode('https://myshop.com/order/${transaction.transactionId}', size: QRSize.size6, align: PosAlign.left);

  // Cut the receipt
  receiptBytes += generator.cut();

  // Send the receipt to the printer
  final success = await PrintBluetoothThermal.writeBytes(receiptBytes);
  print(success ? 'Print successful' : 'Print failed');

  // Disconnect from the printer
  await PrintBluetoothThermal.disconnect;
}

Future<void> testPrinting() async {
  // Create test data for sale receipt
  final saleTransaction = SaleHistoryTransaction(
    transactionId: "123456",
    companyName: "TEST COMPANY NAME",
    createdAt: DateTime.now().toIso8601String(),
    seller: "Test Seller",
    status: 1,
    statusName: "",
    finalAmount: 45000,
    products: [
      // Product with special character ʻ to test encoding
      SaleProduct(
        name: "Product with ʻ special char",
        quantity: 2,
        unitName: "dona",
        currentPrice: 10000,
        status: 1
      ),
      // Product with long name to test wrapping
      SaleProduct(
        name: "This is a very long product name that should be wrapped to multiple lines on the receipt",
        quantity: 1,
        unitName: "kg",
        currentPrice: 25000,
        status: 1
      ),
    ],
    paymentMethods: [
      PaymentMethod(methodId: 1, amount: 25000),
      PaymentMethod(methodId: 2, amount: 20000),
    ],
  );

  // Create test data for purchase receipt
  final purchaseTransaction = PurchaseTransaction(
    transactionId: "P123456",
    companyName: "TEST COMPANY NAME",
    createdAt: DateTime.now().toIso8601String(),
    supplier: Supplier(name: "Test Supplier"),
    receiver: Receiver(name: "Test Receiver"),
    status: 1,
    statusName: "",
    totalAmount: 45000,
    products: [
      // Product with special character ʻ to test encoding
      PurchaseProduct(
        name: "Purchase item with ʻ special char",
        quantity: 2,
        unitName: "dona",
        currentPrice: 10000,
        status: 1
      ),
      // Product with long name to test wrapping
      PurchaseProduct(
        name: "This is a very long product name that should be wrapped to multiple lines on the receipt for purchase",
        quantity: 1,
        unitName: "kg",
        currentPrice: 25000,
        status: 1
      ),
    ],
  );

  // Test sale receipt
  print("Printing sale receipt...");
  await printSaleReceipt58mm(saleTransaction: saleTransaction);

  // Wait a bit between prints
  await Future.delayed(const Duration(seconds: 3));

  // Test purchase receipt
  print("Printing purchase receipt...");
  await printSaleReceipt58mm(purchaseTransaction: purchaseTransaction);
}
