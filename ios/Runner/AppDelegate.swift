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

        // Build TSPL command buffer
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = df.string(from: Date())

        let cmds = [
            "SIZE 80 mm, 60 mm",
            "GAP 2 mm, 0 mm",
            "CLS",
            "TEXT 10,10,\"TSS24.BF2\",0,1,1,\"STORE NAME\"",
            "TEXT 10,40,\"TSS24.BF2\",0,1,1,\"TEST RECEIPT\"",
            "TEXT 10,70,\"TSS24.BF2\",0,1,1,\"\(now)\"",
            "BAR 10,100,400,3",
            "TEXT 10,120,\"TSS24.BF2\",0,1,1,\"Item 1\"",
            "TEXT 300,120,\"TSS24.BF2\",0,1,1,\"$10.00\"",
            "TEXT 10,150,\"TSS24.BF2\",0,1,1,\"Item 2\"",
            "TEXT 300,150,\"TSS24.BF2\",0,1,1,\"$15.00\"",
            "BAR 10,180,400,3",
            "TEXT 10,200,\"TSS24.BF2\",0,1,1,\"TOTAL\"",
            "TEXT 300,200,\"TSS24.BF2\",0,1,1,\"$25.00\"",
            "QRCODE 150,240,M,8,A,0,\"https://example.com/receipt/12345\"",
            "TEXT 10,380,\"TSS24.BF2\",0,1,1,\"Thank you for your purchase!\"",
            "PRINT 1"
        ]
        let payload = cmds.joined(separator: "\r\n") + "\r\n"
        guard let data = payload.data(using: .utf8) else {
            return result(FlutterError(
                code: "ENCODING_ERROR",
                message: "Failed to encode commands",
                details: nil
            ))
        }

        // 🔑 Use the renamed API:
        bleManager.writeCommand(with: data)
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

        // Build TSPL command buffer for cheque printing
        // Adjust these commands according to your cheque format requirements
        let cmds = [
            "SIZE 80 mm, 60 mm",
            "GAP 2 mm, 0 mm",
            "CLS",
            "TEXT 10,10,\"TSS24.BF2\",0,1,1,\"\(bankName)\"",
            "TEXT 350,10,\"TSS24.BF2\",0,1,1,\"Date: \(date)\"",
            "TEXT 350,40,\"TSS24.BF2\",0,1,1,\"Cheque #: \(chequeNumber)\"",
            "BAR 10,70,400,1",
            "TEXT 10,90,\"TSS24.BF2\",0,1,1,\"Pay to the order of:\"",
            "TEXT 10,120,\"TSS24.BF2\",0,1,1,\"\(payeeName)\"",
            "TEXT 10,150,\"TSS24.BF2\",0,1,1,\"Amount: $\(amount)\"",
            "TEXT 10,180,\"TSS24.BF2\",0,1,1,\"Account: \(accountNumber)\"",
            "BAR 10,210,400,1",
            "TEXT 10,230,\"TSS24.BF2\",0,1,1,\"\(additionalInfo)\"",
            "PRINT 1"
        ]

        let payload = cmds.joined(separator: "\r\n") + "\r\n"
        guard let data = payload.data(using: .utf8) else {
            return result(FlutterError(
                code: "ENCODING_ERROR",
                message: "Failed to encode commands",
                details: nil
            ))
        }

        // Use the renamed API to send data to printer
        bleManager.writeCommand(with: data)
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
