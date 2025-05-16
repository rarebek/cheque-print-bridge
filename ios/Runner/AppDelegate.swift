import UIKit
import Flutter
import CoreBluetooth

@main
@objc class AppDelegate: FlutterAppDelegate, TSCBLEManagerDelegate {
    private var bleManager: TSCBLEManager!
    private var methodChannel: FlutterMethodChannel!
    private var printerConnected = false

    private var scannedDevices = [CBPeripheral]()
    private var connectionResult: FlutterResult?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window!.rootViewController as! FlutterViewController
        methodChannel = FlutterMethodChannel(
            name: "com.example.xprinter/printer",
            binaryMessenger: controller.binaryMessenger
        )

        methodChannel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "scanDevices":
                self.scanDevices(result: result)
            case "connectDevice":
                guard
                    let args = call.arguments as? [String: Any],
                    let deviceId = args["deviceId"] as? String
                else {
                    return result(FlutterError(
                        code: "INVALID_ARGUMENT",
                        message: "Missing or invalid deviceId",
                        details: nil
                    ))
                }
                self.connectToDevice(deviceId: deviceId, result: result)
            case "disconnectDevice":
                self.disconnectDevice(result: result)
            case "printTestReceipt":
                self.printTestReceipt(result: result)
            case "printCheque":
                guard
                    let args = call.arguments as? [String: Any]
                else {
                    return result(FlutterError(
                        code: "INVALID_ARGUMENT",
                        message: "Missing or invalid cheque details",
                        details: nil
                    ))
                }
                self.printCheque(chequeDetails: args, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        bleManager = TSCBLEManager.sharedInstance()
        bleManager.delegate = self

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - BLE Actions

    private func scanDevices(result: @escaping FlutterResult) {
        guard !bleManager.isScaning else {
            return result(FlutterError(
                code: "ALREADY_SCANNING",
                message: "Already scanning",
                details: nil
            ))
        }
        scannedDevices.removeAll()
        bleManager.startScan()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.bleManager.stopScan()
            let list = self.scannedDevices.map {
                ["id": $0.identifier.uuidString, "name": $0.name ?? "Unknown"]
            }
            result(list)
        }
    }

    private func connectToDevice(deviceId: String, result: @escaping FlutterResult) {
        guard
            let uuid = UUID(uuidString: deviceId),
            let peripheral = scannedDevices.first(where: { $0.identifier == uuid })
        else {
            return result(FlutterError(
                code: "DEVICE_NOT_FOUND",
                message: "Device not found",
                details: nil
            ))
        }
        connectionResult = result
        bleManager.connectDevice(peripheral)
    }

    private func disconnectDevice(result: @escaping FlutterResult) {
        bleManager.disconnectRootPeripheral()
        printerConnected = false
        result(true)
    }

    private func printTestReceipt(result: @escaping FlutterResult) {
        guard printerConnected, bleManager.writePeripheral != nil else {
            return result(FlutterError(
                code: "NOT_CONNECTED",
                message: "Not connected",
                details: nil
            ))
        }

        // Create date/time string
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = df.string(from: Date())

        // ESC/POS commands for 58mm paper
        var commands: [UInt8] = []

        // Initialize printer (ESC @)
        commands.append(contentsOf: [0x1B, 0x40])

        // Set text alignment center (ESC a 1)
        commands.append(contentsOf: [0x1B, 0x61, 0x01])

        // Store name (bold)
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "STORE NAME".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Receipt title
        commands.append(contentsOf: "TEST RECEIPT".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Date time
        commands.append(contentsOf: now.data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Set text alignment left (ESC a 0)
        commands.append(contentsOf: [0x1B, 0x61, 0x00])

        // Horizontal line (using dash characters)
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "--------------------------------".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Item 1
        commands.append(contentsOf: "Item 1".data(using: .utf8) ?? Data())
        // Tab to position price at right (9 spaces)
        commands.append(contentsOf: "         $10.00".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Item 2
        commands.append(contentsOf: "Item 2".data(using: .utf8) ?? Data())
        // Tab to position price at right (9 spaces)
        commands.append(contentsOf: "         $15.00".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Horizontal line (using dash characters)
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "--------------------------------".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Total (bold)
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "TOTAL".data(using: .utf8) ?? Data())
        // Tab to position price at right (10 spaces)
        commands.append(contentsOf: "          $25.00".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Set text alignment center (ESC a 1)
        commands.append(contentsOf: [0x1B, 0x61, 0x01])

        // Thank you message
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: "Thank you for your purchase!".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Feed and cut
        commands.append(contentsOf: [0x0A, 0x0A, 0x0A, 0x0A]) // Feed lines
        commands.append(contentsOf: [0x1D, 0x56, 0x01]) // Cut paper (partial cut)

        // Send the commands to the printer
        let commandData = Data(commands)
        bleManager.writeCommand(with: commandData)
        result(true)
    }

    private func printCheque(chequeDetails: [String: Any], result: @escaping FlutterResult) {
        guard printerConnected, bleManager.writePeripheral != nil else {
            return result(FlutterError(
                code: "NOT_CONNECTED",
                message: "Not connected",
                details: nil
            ))
        }

        // Extract all possible fields from the received arguments
        let companyName = chequeDetails["companyName"] as? String ?? "My Company"
        let transactionId = chequeDetails["transactionId"] as? String ?? "0000000"
        let status = chequeDetails["status"] as? Int ?? 1
        let statusName = chequeDetails["statusName"] as? String ?? ""

        // Persons involved
        let seller = chequeDetails["seller"] as? String ?? ""
        let receiver = chequeDetails["receiver"] as? String ?? ""
        let supplierName = chequeDetails["supplierName"] as? String ?? ""

        // Financial details
        let totalAmount = chequeDetails["totalAmount"] as? Double ?? 0.0
        let finalAmount = chequeDetails["finalAmount"] as? Double ?? totalAmount

        // Payment method details
        let paymentMethods = chequeDetails["paymentMethods"] as? [[String: Any]] ?? []

        // Products list
        let products = chequeDetails["products"] as? [[String: Any]] ?? []

        // Date details
        let createdDate = chequeDetails["createdAt"] as? String ?? Date().description

        // Format the date for display
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        let date: Date
        if let parsedDate = dateFormatter.date(from: createdDate) {
            date = parsedDate
        } else {
            date = Date()
        }

        dateFormatter.dateFormat = "dd-MM-yyyy"
        let formattedDate = dateFormatter.string(from: date)

        dateFormatter.dateFormat = "HH:mm"
        let formattedTime = dateFormatter.string(from: date)

        // ESC/POS commands for 58mm paper
        var commands: [UInt8] = []

        // Initialize printer (ESC @)
        commands.append(contentsOf: [0x1B, 0x40])

        // Set text alignment center (ESC a 1)
        commands.append(contentsOf: [0x1B, 0x61, 0x01])

        // Company name (bold)
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: companyName.data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Set text alignment left (ESC a 0)
        commands.append(contentsOf: [0x1B, 0x61, 0x00])

        // Date and time
        commands.append(contentsOf: "Sana: \(formattedDate)  Vaqti: \(formattedTime)".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Transaction ID
        commands.append(contentsOf: "Chek raqami: \(transactionId)".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Status (if not 1)
        if status != 1 && !statusName.isEmpty {
            commands.append(contentsOf: "Holati: \(statusName)".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
        }

        // Personnel information - different based on transaction type
        if !seller.isEmpty {
            commands.append(contentsOf: "Kassir: \(seller)".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
        }

        if !supplierName.isEmpty {
            commands.append(contentsOf: "Ta'minotchi: \(supplierName)".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
        }

        if !receiver.isEmpty {
            commands.append(contentsOf: "Qabul qiluvchi: \(receiver)".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
        }

        // Horizontal line
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "--------------------------------".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Products
        for product in products {
            let name = product["name"] as? String ?? "Unknown Product"
            let quantity = product["quantity"] as? Double ?? 0.0
            let unitName = product["unitName"] as? String ?? "pcs"
            let price = product["currentPrice"] as? Double ?? 0.0
            let productStatus = product["status"] as? Int ?? 1

            let statusLabel = productStatus == 1 ? "" : "(Qaytarilgan)"
            let total = price * quantity

            // Product name (bold) with status if returned
            commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
            commands.append(contentsOf: "\(name) \(statusLabel)".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
            commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

            // Quantity and unit
            commands.append(contentsOf: "(\(quantity) \(unitName))".data(using: .utf8) ?? Data())

            // Format price to show commas for thousands
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = " "
            let formattedPrice = formatter.string(from: NSNumber(value: total)) ?? "\(total)"

            // Tab over to display price at right
            commands.append(contentsOf: "    \(formattedPrice) so'm".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
        }

        // Horizontal line
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "--------------------------------".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Format total amount
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        let formattedTotal = formatter.string(from: NSNumber(value: finalAmount)) ?? "\(finalAmount)"

        // Total amount
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "Umumiy summa:".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off
        // Tab to position price at right
        commands.append(contentsOf: "    \(formattedTotal) so'm".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Tax (15%)
        let tax = finalAmount * 0.15
        let formattedTax = formatter.string(from: NSNumber(value: tax)) ?? "\(tax)"

        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "QQS 15%:".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off
        // Tab to position price at right
        commands.append(contentsOf: "    \(formattedTax) so'm".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Payment methods section
        if !paymentMethods.isEmpty {
            // Horizontal line
            commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
            commands.append(contentsOf: "--------------------------------".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
            commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

            commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
            commands.append(contentsOf: "To'lov turi:".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
            commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

            for method in paymentMethods {
                let methodId = method["methodId"] as? Int ?? 0
                let amount = method["amount"] as? Double ?? 0.0
                let methodName = methodId == 1 ? "Naqd" : "Plastik"
                let formattedAmount = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"

                commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
                commands.append(contentsOf: methodName.data(using: .utf8) ?? Data())
                commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off
                // Tab to position price at right
                commands.append(contentsOf: "    \(formattedAmount) so'm".data(using: .utf8) ?? Data())
                commands.append(contentsOf: [0x0A]) // Line feed
            }
        }

        // Change amount (always 0 in the example)
        commands.append(contentsOf: "Qaytim: 0 so'm".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Horizontal line
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "--------------------------------".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Thank you message - center aligned
        commands.append(contentsOf: [0x1B, 0x61, 0x01]) // Center align
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "Xaridingiz uchun rahmat!".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Feed and cut
        commands.append(contentsOf: [0x0A, 0x0A, 0x0A, 0x0A]) // Feed lines
        commands.append(contentsOf: [0x1D, 0x56, 0x01]) // Cut paper (partial cut)

        // Send the commands to the printer
        let commandData = Data(commands)
        bleManager.writeCommand(with: commandData)
        result(true)
    }

    // MARK: - TSCBLEManagerDelegate

    func tsCbleUpdatePeripheralList(_ peripherals: [Any]?, rssiList: [Any]?) {
        guard let list = peripherals as? [CBPeripheral] else { return }
        for p in list where p.name != nil && !scannedDevices.contains(p) {
            scannedDevices.append(p)
        }
    }

    func tsCbleConnect(_ peripheral: CBPeripheral?) {
        printerConnected = true
        connectionResult?(true)
        connectionResult = nil
    }

    func tsCbleFail(toConnect peripheral: CBPeripheral?, error: Error?) {
        connectionResult?(FlutterError(
            code: "CONNECTION_FAILED",
            message: error?.localizedDescription ?? "Unknown error",
            details: nil
        ))
        connectionResult = nil
    }

    func tsCbleDisconnectPeripheral(_ peripheral: CBPeripheral?, error: Error?) {
        printerConnected = false
    }
}
