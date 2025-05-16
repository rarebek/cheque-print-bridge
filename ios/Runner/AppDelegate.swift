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

        // Extract cheque details from the received arguments
        let payeeName = chequeDetails["payeeName"] as? String ?? "Unknown Payee"
        let amount = chequeDetails["amount"] as? String ?? "0.00"
        let date = chequeDetails["date"] as? String ?? Date().description
        let chequeNumber = chequeDetails["chequeNumber"] as? String ?? "00000000"
        let accountNumber = chequeDetails["accountNumber"] as? String ?? "Unknown Account"
        let bankName = chequeDetails["bankName"] as? String ?? "Bank"
        let additionalInfo = chequeDetails["additionalInfo"] as? String ?? ""

        // ESC/POS commands for 58mm paper
        var commands: [UInt8] = []

        // Initialize printer (ESC @)
        commands.append(contentsOf: [0x1B, 0x40])

        // Set text alignment center (ESC a 1)
        commands.append(contentsOf: [0x1B, 0x61, 0x01])

        // Bank name (bold)
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: bankName.data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Set text alignment left (ESC a 0)
        commands.append(contentsOf: [0x1B, 0x61, 0x00])

        // Date and cheque number
        commands.append(contentsOf: "Date: \(date)".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: "Cheque #: \(chequeNumber)".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Horizontal line (using dash characters)
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "--------------------------------".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Pay to the order of section
        commands.append(contentsOf: "Pay to the order of:".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Payee name (bold)
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: payeeName.data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Amount
        commands.append(contentsOf: "Amount: $\(amount)".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Account number
        commands.append(contentsOf: "Account: \(accountNumber)".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed

        // Horizontal line
        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
        commands.append(contentsOf: "--------------------------------".data(using: .utf8) ?? Data())
        commands.append(contentsOf: [0x0A]) // Line feed
        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

        // Additional info
        if !additionalInfo.isEmpty {
            commands.append(contentsOf: additionalInfo.data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
        }

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
