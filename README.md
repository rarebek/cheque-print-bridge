# XPrinter Demo App

A Flutter application that demonstrates how to connect to XPrinter thermal printers via Bluetooth and print a test receipt.

## Setup Instructions

### iOS Setup

1. Add the XPrinter SDK files to your project:

   - Create a directory in your iOS project: `ios/Runner/PrinterSDK`
   - Copy the XPrinter SDK files from the PrinterDemo project:
     - Copy `PrinterSDK/Headers/*.h` files to `ios/Runner/PrinterSDK/Headers/`
     - Copy `PrinterSDK/libPrinterSDK.a` to `ios/Runner/PrinterSDK/`

2. Update your `ios/Runner.xcodeproj/project.pbxproj`:
   - Add the library search path: `$(PROJECT_DIR)/Runner/PrinterSDK`
   - Add the header search path: `$(PROJECT_DIR)/Runner/PrinterSDK/Headers`
   - Link against the static library: `libPrinterSDK.a`

3. Update your Info.plist to include Bluetooth permissions:
   ```xml
   <key>NSBluetoothAlwaysUsageDescription</key>
   <string>This app needs Bluetooth access to connect to thermal printers</string>
   <key>NSBluetoothPeripheralUsageDescription</key>
   <string>This app needs Bluetooth access to connect to thermal printers</string>
   ```

### Usage

1. Run the app on your iOS device (simulator won't work as it needs Bluetooth)
2. Tap "Scan" to discover nearby Bluetooth printers
3. Tap on a printer to connect to it
4. Once connected, tap "Print Test Receipt" to print a sample receipt

## Customizing The Receipt

You can customize the receipt in the `printTestReceipt` method in the `AppDelegate.swift` file. The receipt uses TSC commands to format text, add lines, and print QR codes.

## Troubleshooting

- Make sure the printer is turned on and in Bluetooth discovery mode
- Verify that Bluetooth is enabled on your device
- Check the printer's paper roll is properly inserted
- If the printer doesn't appear in the scan, try resetting the printer
