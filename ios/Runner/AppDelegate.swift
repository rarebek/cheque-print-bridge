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

        // Accept receipt template settings from Flutter
        let templateSettings = chequeDetails["templateSettings"] as? [String: Any] ?? [:]
        let pageWidth = templateSettings["pageWidth"] as? Int ?? 32
        let useAutoCut = templateSettings["useAutoCut"] as? Bool ?? true
        let feedLineCount = templateSettings["feedLineCount"] as? Int ?? 4

        // Check if receipt elements are explicitly provided
        let receiptElements = chequeDetails["receiptElements"] as? [[String: Any]] ?? []

        // Setup number formatter for currency
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "

        // ESC/POS commands for the receipt
        var commands: [UInt8] = []

        // Initialize printer (ESC @)
        commands.append(contentsOf: [0x1B, 0x40])

        // Set character encoding to handle special characters correctly
        commands.append(contentsOf: [0x1B, 0x74, 0x02]) // ESC t 2 - Set character code table to PC437 (most compatible)

        if !receiptElements.isEmpty {
            // Use the explicitly provided template from Flutter
            for element in receiptElements {
                let type = element["type"] as? String ?? ""
                let text = element["text"] as? String ?? ""
                let alignment = element["alignment"] as? String ?? "left"
                let isBold = element["bold"] as? Bool ?? false
                let isUnderline = element["underline"] as? Bool ?? false
                let leftPadding = element["leftPadding"] as? Int ?? 0
                let rightValue = element["rightValue"] as? String

                // Apply alignment
                if alignment == "center" {
                    let padding = (pageWidth - text.count) / 2
                    let centeredText = String(repeating: " ", count: max(0, padding)) + text
                    commands.append(contentsOf: centeredText.data(using: .utf8) ?? Data())
                    commands.append(contentsOf: [0x0A]) // Line feed
                } else if alignment == "right" {
                    let padding = pageWidth - text.count
                    let rightText = String(repeating: " ", count: max(0, padding)) + text
                    commands.append(contentsOf: rightText.data(using: .utf8) ?? Data())
                    commands.append(contentsOf: [0x0A]) // Line feed
                } else if alignment == "justified" && rightValue != nil {
                    // Handle left-right justified text
                    let padding = pageWidth - text.count - (rightValue?.count ?? 0)
                    let justifiedText = text + String(repeating: " ", count: max(0, padding)) + (rightValue ?? "")

                    // Apply bold if needed
                    if isBold {
                        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
                    }

                    // Apply underline if needed
                    if isUnderline {
                        commands.append(contentsOf: [0x1B, 0x2D, 0x01]) // Underline on
                    }

                    commands.append(contentsOf: justifiedText.data(using: .utf8) ?? Data())
                    commands.append(contentsOf: [0x0A]) // Line feed

                    // Reset formatting
                    if isBold {
                        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off
                    }

                    if isUnderline {
                        commands.append(contentsOf: [0x1B, 0x2D, 0x00]) // Underline off
                    }
                } else {
                    // Handle left alignment with optional padding
                    let paddedText = String(repeating: " ", count: leftPadding) + text

                    // Apply bold if needed
                    if isBold {
                        commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
                    }

                    // Apply underline if needed
                    if isUnderline {
                        commands.append(contentsOf: [0x1B, 0x2D, 0x01]) // Underline on
                    }

                    commands.append(contentsOf: paddedText.data(using: .utf8) ?? Data())
                    commands.append(contentsOf: [0x0A]) // Line feed

                    // Reset formatting
                    if isBold {
                        commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off
                    }

                    if isUnderline {
                        commands.append(contentsOf: [0x1B, 0x2D, 0x00]) // Underline off
                    }
                }
            }
        } else {
            // Use the default template if no explicit elements are provided
            // (Keep your existing code here as a fallback)
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

            // Determine receipt type - purchase or sale based on if we have supplier data
            let isPurchaseReceipt = !supplierName.isEmpty

            // Center the company name - truly centered with slightly larger font
            commands.append(contentsOf: [0x1D, 0x21, 0x01]) // GS ! 01 - only slightly larger font (height doubled)
            let companyPadding = (pageWidth - companyName.count) / 2
            let centeredCompany = String(repeating: " ", count: max(0, companyPadding)) + sanitizeText(companyName)
            commands.append(contentsOf: centeredCompany.data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
            commands.append(contentsOf: [0x1D, 0x21, 0x00]) // Reset font size

            // Helper function to wrap text with 8-character limit and dash-based word splitting
            func wrapTextWithDash(_ string: String, maxLength: Int = 8) -> [String] {
                var result: [String] = []
                var currentLine = ""

                // Split text into words
                let words = string.split(separator: " ")

                for word in words {
                    let wordStr = String(word)

                    // If word is longer than maxLength, split with dashes
                    if wordStr.count > maxLength {
                        if !currentLine.isEmpty {
                            // Add current line to result and process long word separately
                            result.append(currentLine)
                            currentLine = ""
                        }

                        // Split long word with dashes
                        var remainingWord = wordStr
                        while remainingWord.count > maxLength {
                            let index = remainingWord.index(remainingWord.startIndex, offsetBy: maxLength - 1)
                            let lineWithDash = String(remainingWord[...index]) + "-"
                            result.append(lineWithDash)

                            // Move to next part of the word
                            remainingWord = String(remainingWord[remainingWord.index(after: index)...])
                        }

                        // Add any remaining part of the word
                        if !remainingWord.isEmpty {
                            currentLine = remainingWord
                        }
                    }
                    // If adding this word exceeds maxLength
                    else if currentLine.count + wordStr.count + (currentLine.isEmpty ? 0 : 1) > maxLength {
                        // Add current line to result and start new line with current word
                        result.append(currentLine)
                        currentLine = wordStr
                    }
                    else {
                        // Add space if not at beginning of line
                        if !currentLine.isEmpty {
                            currentLine += " "
                        }
                        currentLine += wordStr
                    }
                }

                // Add the last line if not empty
                if !currentLine.isEmpty {
                    result.append(currentLine)
                }

                return result.isEmpty ? [string] : result
            }

            // Helper function to right-align values with wrapping
            func appendLabelWithRightAlignedValue(label: String, value: String) {
                let maxLabelWidth = 13 // Adjust to fit your receipt width
                let maxValueWidth = pageWidth - maxLabelWidth - 1

                // Wrap the value if needed
                let wrappedValues = wrapTextWithDash(sanitizeText(value), maxLength: maxValueWidth)

                // First line includes the label
                if let firstLine = wrappedValues.first {
                    let padding = String(repeating: " ", count: max(1, pageWidth - label.count - firstLine.count))
                    commands.append(contentsOf: "\(label)\(padding)\(firstLine)".data(using: .utf8) ?? Data())
                    commands.append(contentsOf: [0x0A]) // Line feed
                }

                // Remaining lines (if any)
                if wrappedValues.count > 1 {
                    let labelSpace = String(repeating: " ", count: maxLabelWidth)
                    for i in 1..<wrappedValues.count {
                        let padding = String(repeating: " ", count: max(1, pageWidth - labelSpace.count - wrappedValues[i].count))
                        commands.append(contentsOf: "\(labelSpace)\(padding)\(wrappedValues[i])".data(using: .utf8) ?? Data())
                        commands.append(contentsOf: [0x0A]) // Line feed
                    }
                }
            }

            // Date and time (left and right aligned)
            let dateText = "Sana:\(formattedDate)"
            let timeText = "Vaqti:\(formattedTime)"
            let spacePadding = String(repeating: " ", count: max(1, pageWidth - dateText.count - timeText.count))
            commands.append(contentsOf: "\(dateText)\(spacePadding)\(timeText)".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed

            // Transaction ID with right alignment - wrapped if needed
            let transactionIdLabel = "Chek raqami: "
            let wrappedIds = wrapTextWithDash(sanitizeText(transactionId), maxLength: pageWidth - transactionIdLabel.count - 1)

            if let firstLine = wrappedIds.first {
                let idPadding = String(repeating: " ", count: max(1, pageWidth - transactionIdLabel.count - firstLine.count))
                commands.append(contentsOf: "\(transactionIdLabel)\(idPadding)\(firstLine)".data(using: .utf8) ?? Data())
                commands.append(contentsOf: [0x0A]) // Line feed

                // Print additional lines if wrapped
                if wrappedIds.count > 1 {
                    let labelSpace = String(repeating: " ", count: transactionIdLabel.count)
                    for i in 1..<wrappedIds.count {
                        let linePadding = String(repeating: " ", count: max(1, pageWidth - labelSpace.count - wrappedIds[i].count))
                        commands.append(contentsOf: "\(labelSpace)\(linePadding)\(wrappedIds[i])".data(using: .utf8) ?? Data())
                        commands.append(contentsOf: [0x0A]) // Line feed
                    }
                }
            }

            // Personnel information based on receipt type
            if isPurchaseReceipt {
                // Purchase receipt: supplier and receiver
                if !supplierName.isEmpty {
                    appendLabelWithRightAlignedValue(label: "Ta'minotchi:", value: supplierName)
                }

                if !receiver.isEmpty {
                    appendLabelWithRightAlignedValue(label: "Qabul qiluvchi:", value: receiver)
                }
            } else {
                // Sales receipt: cashier
                if !seller.isEmpty {
                    appendLabelWithRightAlignedValue(label: "Kassir:", value: seller)
                }
            }

            // Status (if not 1)
            if status != 1 && !statusName.isEmpty {
                commands.append(contentsOf: "Holati: \(statusName)".data(using: .utf8) ?? Data())
                commands.append(contentsOf: [0x0A]) // Line feed
            }

            // Horizontal line
            commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
            commands.append(contentsOf: String(repeating: "-", count: pageWidth).data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
            commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

            // Products - with improved column layout and wrapping for product names
            for product in products {
                let name = product["name"] as? String ?? "Unknown Product"
                let quantity = product["quantity"] as? Double ?? 0.0
                let unitName = product["unitName"] as? String ?? "dona"
                let price = product["currentPrice"] as? Double ?? 0.0
                let productStatus = product["status"] as? Int ?? 1

                let statusLabel = productStatus == 1 ? "" : "(Qaytarilgan)"
                let total = price * quantity

                // Format price to show commas for thousands
                let formattedPrice = formatter.string(from: NSNumber(value: total)) ?? "\(total)"
                let priceText = "\(formattedPrice) so'm"
                let quantityText = "(\(quantity) \(unitName))"

                // Calculate maximum name length based on paper width
                let maxNameLength = pageWidth - 2 // Leave some margin
                let fullProductName = sanitizeText("\(name) \(statusLabel)")

                // Product name (bold) - wrap if too long with 8-char limit and dash splitting
                commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on

                // Wrap product name to fit the width with our custom wrapping
                let wrappedProductName = wrapTextWithDash(fullProductName)

                // Print each line of the product name
                for line in wrappedProductName {
                    commands.append(contentsOf: line.data(using: .utf8) ?? Data())
                    commands.append(contentsOf: [0x0A]) // Line feed
                }

                commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

                // Always print quantity and price on separate lines

                // Print quantity centered in its own line
                commands.append(contentsOf: [0x1B, 0x61, 0x01]) // ESC a 1 - Center alignment
                commands.append(contentsOf: quantityText.data(using: .utf8) ?? Data())
                commands.append(contentsOf: [0x0A]) // Line feed

                // Print price right-aligned
                commands.append(contentsOf: [0x1B, 0x61, 0x02]) // ESC a 2 - Right alignment
                commands.append(contentsOf: priceText.data(using: .utf8) ?? Data())
                commands.append(contentsOf: [0x0A]) // Line feed

                // Reset alignment to left
                commands.append(contentsOf: [0x1B, 0x61, 0x00]) // ESC a 0 - Left alignment

                // Add space between products
                commands.append(contentsOf: [0x0A]) // Empty line after each product
            }

            // Horizontal line
            commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
            commands.append(contentsOf: String(repeating: "-", count: pageWidth).data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed

            // Format total amount - Bold both label and value
            let formattedTotal = formatter.string(from: NSNumber(value: finalAmount)) ?? "\(finalAmount)"
            let totalLabel = "Umumiy summa"
            let totalValue = "\(formattedTotal) so'm"
            let totalPadding = String(repeating: " ", count: max(1, pageWidth - totalLabel.count - totalValue.count))
            commands.append(contentsOf: "\(totalLabel)\(totalPadding)\(totalValue)".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed

            // Tax (15%)
            let tax = finalAmount * 0.15
            let formattedTax = formatter.string(from: NSNumber(value: tax)) ?? "\(tax)"
            let taxLabel = "QQS 15%"
            let taxValue = "\(formattedTax) so'm"
            let taxPadding = String(repeating: " ", count: max(1, pageWidth - taxLabel.count - taxValue.count))
            commands.append(contentsOf: "\(taxLabel)\(taxPadding)\(taxValue)".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
            commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

            // Payment methods section (only for sales receipts)
            if !isPurchaseReceipt && !paymentMethods.isEmpty {
                // Horizontal line
                commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
                commands.append(contentsOf: String(repeating: "-", count: pageWidth).data(using: .utf8) ?? Data())
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

                    // Align payment method and amount
                    let methodValue = "\(formattedAmount) so'm"
                    let methodPadding = String(repeating: " ", count: max(1, pageWidth - methodName.count - methodValue.count))
                    commands.append(contentsOf: "\(methodName)\(methodPadding)\(methodValue)".data(using: .utf8) ?? Data())
                    commands.append(contentsOf: [0x0A]) // Line feed
                }
            }

            // Change amount (always 0 in the example)
            let qaytimLabel = "Qaytim"
            let qaytimValue = "0 so'm"
            let qaytimPadding = String(repeating: " ", count: max(1, pageWidth - qaytimLabel.count - qaytimValue.count))
            commands.append(contentsOf: "\(qaytimLabel)\(qaytimPadding)\(qaytimValue)".data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed

            // Horizontal line
            commands.append(contentsOf: [0x1B, 0x45, 0x01]) // Bold on
            commands.append(contentsOf: String(repeating: "-", count: pageWidth).data(using: .utf8) ?? Data())
            commands.append(contentsOf: [0x0A]) // Line feed
            commands.append(contentsOf: [0x1B, 0x45, 0x00]) // Bold off

            // Thank you message - properly centered with larger font
            if !isPurchaseReceipt {
                // Thank you message - truly centered with larger font
                commands.append(contentsOf: [0x1D, 0x21, 0x01]) // GS ! 01 - Slightly larger font (just height doubled)
                let thankYouMsg = sanitizeText("Xaridingiz uchun rahmat!")
                let leftPadding = (pageWidth - thankYouMsg.count) / 2
                let rightPadding = pageWidth - thankYouMsg.count - leftPadding
                let paddedThankYou = String(repeating: " ", count: leftPadding) + thankYouMsg + String(repeating: " ", count: rightPadding)
                commands.append(contentsOf: paddedThankYou.data(using: .utf8) ?? Data())
                commands.append(contentsOf: [0x0A]) // Line feed
                commands.append(contentsOf: [0x1D, 0x21, 0x00]) // Reset font size
            }
        }

        // Add feed lines based on template settings
        for _ in 0..<feedLineCount {
            commands.append(contentsOf: [0x0A]) // Line feed
        }

        // Add cut command if auto-cut is enabled
        if useAutoCut {
            commands.append(contentsOf: [0x1D, 0x56, 0x01]) // Cut paper (partial cut)
        }

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

    // Add a helper function for text encoding to handle special characters
    func sanitizeText(_ text: String) -> String {
        // Replace problematic characters with similar ASCII alternatives
        return text.replacingOccurrences(of: "ʻ", with: "'")
                   .replacingOccurrences(of: "ʼ", with: "'")
                   .replacingOccurrences(of: "ҳ", with: "x")
                   .replacingOccurrences(of: "қ", with: "q")
                   .replacingOccurrences(of: "ғ", with: "g")
                   .replacingOccurrences(of: "ў", with: "u")
    }
}
