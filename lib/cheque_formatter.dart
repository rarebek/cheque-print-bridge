import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dart:convert';

class ChequeFormatter {
  static const int defaultPageWidth = 32;

  /// Formats a cheque receipt and returns raw printer commands
  static Uint8List formatCheque({
    required Map<String, dynamic> chequeDetails,
    int pageWidth = defaultPageWidth,
    bool useAutoCut = true,
    int feedLineCount = 4,
  }) {
    List<int> commands = [];

    // Initialize printer (ESC @)
    commands.addAll([0x1B, 0x40]);

    // Set character encoding to handle special characters correctly
    commands.addAll([0x1B, 0x74, 0x02]); // ESC t 2 - Set character code table to PC437 (most compatible)

    // Check if receipt elements are explicitly provided
    final receiptElements = chequeDetails['receiptElements'] as List<Map<String, dynamic>>? ?? [];

    if (receiptElements.isNotEmpty) {
      // Use the explicitly provided template
      for (var element in receiptElements) {
        final type = element['type'] as String? ?? '';
        final text = element['text'] as String? ?? '';
        final alignment = element['alignment'] as String? ?? 'left';
        final isBold = element['bold'] as bool? ?? false;
        final isUnderline = element['underline'] as bool? ?? false;
        final leftPadding = element['leftPadding'] as int? ?? 0;
        final rightValue = element['rightValue'] as String?;

        // Apply alignment
        if (alignment == 'center') {
          final padding = (pageWidth - text.length) ~/ 2;
          final centeredText = ' ' * padding + text;
          commands.addAll(utf8.encode(centeredText));
          commands.add(0x0A); // Line feed
        } else if (alignment == 'right') {
          final padding = pageWidth - text.length;
          final rightText = ' ' * padding + text;
          commands.addAll(utf8.encode(rightText));
          commands.add(0x0A); // Line feed
        } else if (alignment == 'justified' && rightValue != null) {
          // Handle left-right justified text
          final padding = pageWidth - text.length - rightValue.length;
          final justifiedText = text + ' ' * padding + rightValue;

          // Apply bold if needed
          if (isBold) {
            commands.addAll([0x1B, 0x45, 0x01]); // Bold on
          }

          // Apply underline if needed
          if (isUnderline) {
            commands.addAll([0x1B, 0x2D, 0x01]); // Underline on
          }

          commands.addAll(utf8.encode(justifiedText));
          commands.add(0x0A); // Line feed

          // Reset formatting
          if (isBold) {
            commands.addAll([0x1B, 0x45, 0x00]); // Bold off
          }

          if (isUnderline) {
            commands.addAll([0x1B, 0x2D, 0x00]); // Underline off
          }
        } else {
          // Handle left alignment with optional padding
          final paddedText = ' ' * leftPadding + text;

          // Apply bold if needed
          if (isBold) {
            commands.addAll([0x1B, 0x45, 0x01]); // Bold on
          }

          // Apply underline if needed
          if (isUnderline) {
            commands.addAll([0x1B, 0x2D, 0x01]); // Underline on
          }

          commands.addAll(utf8.encode(paddedText));
          commands.add(0x0A); // Line feed

          // Reset formatting
          if (isBold) {
            commands.addAll([0x1B, 0x45, 0x00]); // Bold off
          }

          if (isUnderline) {
            commands.addAll([0x1B, 0x2D, 0x00]); // Underline off
          }
        }
      }
    } else {
      // Use the default template
      _formatDefaultTemplate(commands, chequeDetails, pageWidth);
    }

    // Add feed lines
    for (int i = 0; i < feedLineCount; i++) {
      commands.add(0x0A); // Line feed
    }

    // Add cut command if auto-cut is enabled
    if (useAutoCut) {
      commands.addAll([0x1D, 0x56, 0x01]); // Cut paper (partial cut)
    }

    return Uint8List.fromList(commands);
  }

  // Default template moved from Swift code
  static void _formatDefaultTemplate(List<int> commands, Map<String, dynamic> chequeDetails, int pageWidth) {
    // Extract all possible fields from the received arguments
    final companyName = chequeDetails['companyName'] as String? ?? 'My Company';
    final transactionId = chequeDetails['transactionId'] as String? ?? '0000000';
    final status = chequeDetails['status'] as int? ?? 1;
    final statusName = chequeDetails['statusName'] as String? ?? '';

    // Persons involved
    final seller = chequeDetails['seller'] as String? ?? '';
    final receiver = chequeDetails['receiver'] as String? ?? '';
    final supplierName = chequeDetails['supplierName'] as String? ?? '';

    // Financial details
    final totalAmount = chequeDetails['totalAmount'] as double? ?? 0.0;
    final finalAmount = chequeDetails['finalAmount'] as double? ?? totalAmount;

    // Payment method details
    final paymentMethods = chequeDetails['paymentMethods'] as List<dynamic>? ?? [];

    // Products list
    final products = chequeDetails['products'] as List<dynamic>? ?? [];

    // Date details
    final createdDate = chequeDetails['createdAt'] as String? ?? DateTime.now().toString();

    // Format the date for display
    DateTime date;
    try {
      date = DateTime.parse(createdDate);
    } catch (e) {
      date = DateTime.now();
    }

    final formattedDate = '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
    final formattedTime = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    // Determine receipt type - purchase or sale based on if we have supplier data
    final isPurchaseReceipt = supplierName.isNotEmpty;

    // Center the company name - with normal font and condensed wrapping
    commands.addAll([0x1B, 0x61, 0x01]); // ESC a 1 - Center align
    final safeCompanyName = _sanitizeText(companyName);

    // Use standard width for company name to reduce height while maintaining readability
    final wrappedCompanyName = _wrapTextWithDash(safeCompanyName, maxLength: 16);

    for (var line in wrappedCompanyName) {
      commands.addAll(utf8.encode(line));
      commands.add(0x0A); // Line feed
    }

    commands.addAll([0x1B, 0x61, 0x00]); // Reset alignment to left

    // Date and time (left and right aligned)
    final dateText = 'Sana:$formattedDate';
    final timeText = 'Vaqti:$formattedTime';
    final spacePadding = ' ' * (pageWidth - dateText.length - timeText.length);
    commands.addAll(utf8.encode('$dateText$spacePadding$timeText'));
    commands.add(0x0A); // Line feed

    // Transaction ID with right alignment - wrapped if needed
    final transactionIdLabel = 'Chek raqami: ';
    final wrappedIds = _wrapTextWithDash(_sanitizeText(transactionId), maxLength: pageWidth - transactionIdLabel.length - 1);

    if (wrappedIds.isNotEmpty) {
      final firstLine = wrappedIds[0];
      final idPadding = ' ' * (pageWidth - transactionIdLabel.length - firstLine.length);
      commands.addAll(utf8.encode('$transactionIdLabel$idPadding$firstLine'));
      commands.add(0x0A); // Line feed

      // Print additional lines if wrapped
      if (wrappedIds.length > 1) {
        final labelSpace = ' ' * transactionIdLabel.length;
        for (int i = 1; i < wrappedIds.length; i++) {
          final linePadding = ' ' * (pageWidth - labelSpace.length - wrappedIds[i].length);
          commands.addAll(utf8.encode('$labelSpace$linePadding${wrappedIds[i]}'));
          commands.add(0x0A); // Line feed
        }
      }
    }

    // Personnel information based on receipt type
    if (isPurchaseReceipt) {
      // Purchase receipt: supplier and receiver
      if (supplierName.isNotEmpty) {
        _appendLabelWithRightAlignedValue(commands, 'Ta\'minotchi:', supplierName, pageWidth);
      }

      if (receiver.isNotEmpty) {
        _appendLabelWithRightAlignedValue(commands, 'Qabul qiluvchi:', receiver, pageWidth);
      }
    } else {
      // Sales receipt: cashier
      if (seller.isNotEmpty) {
        _appendLabelWithRightAlignedValue(commands, 'Kassir:', seller, pageWidth);
      }
    }

    // Status (if not 1)
    if (status != 1 && statusName.isNotEmpty) {
      commands.addAll(utf8.encode('Holati: $statusName'));
      commands.add(0x0A); // Line feed
    }

    // Horizontal line
    commands.addAll([0x1B, 0x45, 0x01]); // Bold on
    commands.addAll(utf8.encode('-' * pageWidth));
    commands.add(0x0A); // Line feed
    commands.addAll([0x1B, 0x45, 0x00]); // Bold off

    // Define column widths for products section
    final nameColWidth = (pageWidth * 0.5).toInt(); // 50% for name
    final qtyColWidth = (pageWidth * 0.25).toInt(); // 25% for quantity
    final priceColWidth = pageWidth - nameColWidth - qtyColWidth; // remaining space for price

    // Add column headers for products
    commands.addAll([0x1B, 0x45, 0x01]); // Bold on
    final nameHeader = 'Mahsulot';
    final qtyHeader = 'Miqdori';
    final priceHeader = 'Narxi';

    final paddedNameHeader = nameHeader + ' ' * (nameColWidth - nameHeader.length);
    final paddedQtyHeader = qtyHeader + ' ' * (qtyColWidth - qtyHeader.length);

    final headerLine = '$paddedNameHeader$paddedQtyHeader$priceHeader';
    commands.addAll(utf8.encode(headerLine));
    commands.add(0x0A); // Line feed
    commands.addAll([0x1B, 0x45, 0x00]); // Bold off

    // Another divider line
    commands.addAll(utf8.encode('-' * pageWidth));
    commands.add(0x0A); // Line feed

    // Products - in 3-column layout
    for (var product in products) {
      final name = product['name'] as String? ?? 'Unknown Product';
      final quantity = product['quantity'] as double? ?? 0.0;
      final unitName = product['unitName'] as String? ?? 'dona';
      final price = product['currentPrice'] as double? ?? 0.0;
      final productStatus = product['status'] as int? ?? 1;

      final statusLabel = productStatus == 1 ? '' : '(Qaytarilgan)';
      final total = price * quantity;

      // Format price to show commas for thousands
      final formattedPrice = _formatNumber(total);
      final priceText = '$formattedPrice so\'m';
      final quantityText = '($quantity $unitName)';

      // Calculate maximum name length based on paper width
      final maxNameLength = pageWidth - 2; // Leave some margin
      final fullProductName = _sanitizeText('$name $statusLabel');

      // Wrap product name to fit in first column
      final wrappedProductName = _wrapTextWithDash(fullProductName, maxLength: nameColWidth - 1);

      // First line with all three columns
      if (wrappedProductName.isNotEmpty) {
        final firstLine = wrappedProductName[0];
        // Ensure name doesn't overflow its column
        final displayName = firstLine.length > nameColWidth - 1
            ? firstLine.substring(0, nameColWidth - 1)
            : firstLine;

        // Create padded columns
        final paddedName = displayName + ' ' * (nameColWidth - displayName.length);
        final paddedQty = quantityText + ' ' * (qtyColWidth - quantityText.length);

        // Combine all columns
        final fullLine = '$paddedName$paddedQty$priceText';
        commands.addAll(utf8.encode(fullLine));
        commands.add(0x0A); // Line feed

        // Print remaining lines of product name if any
        if (wrappedProductName.length > 1) {
          for (int i = 1; i < wrappedProductName.length; i++) {
            final line = wrappedProductName[i];
            final displayLine = line.length > nameColWidth - 1
                ? line.substring(0, nameColWidth - 1)
                : line;
            commands.addAll(utf8.encode(displayLine));
            commands.add(0x0A); // Line feed
          }
        }
      }

      // Add space between products
      commands.add(0x0A); // Empty line after each product
    }

    // Horizontal line
    commands.addAll([0x1B, 0x45, 0x01]); // Bold on
    commands.addAll(utf8.encode('-' * pageWidth));
    commands.add(0x0A); // Line feed

    // Format total amount - Bold both label and value
    final formattedTotal = _formatNumber(finalAmount);
    final totalLabel = 'Umumiy summa';
    final totalValue = '$formattedTotal so\'m';
    final totalPadding = ' ' * (pageWidth - totalLabel.length - totalValue.length);
    commands.addAll(utf8.encode('$totalLabel$totalPadding$totalValue'));
    commands.add(0x0A); // Line feed

    // Tax (15%)
    final tax = finalAmount * 0.15;
    final formattedTax = _formatNumber(tax);
    final taxLabel = 'QQS 15%';
    final taxValue = '$formattedTax so\'m';
    final taxPadding = ' ' * (pageWidth - taxLabel.length - taxValue.length);
    commands.addAll(utf8.encode('$taxLabel$taxPadding$taxValue'));
    commands.add(0x0A); // Line feed
    commands.addAll([0x1B, 0x45, 0x00]); // Bold off

    // Payment methods section (only for sales receipts)
    if (!isPurchaseReceipt && paymentMethods.isNotEmpty) {
      // Horizontal line
      commands.addAll([0x1B, 0x45, 0x01]); // Bold on
      commands.addAll(utf8.encode('-' * pageWidth));
      commands.add(0x0A); // Line feed
      commands.addAll([0x1B, 0x45, 0x00]); // Bold off

      commands.addAll([0x1B, 0x45, 0x01]); // Bold on
      commands.addAll(utf8.encode('To\'lov turi:'));
      commands.add(0x0A); // Line feed
      commands.addAll([0x1B, 0x45, 0x00]); // Bold off

      for (var method in paymentMethods) {
        final methodId = method['methodId'] as int? ?? 0;
        final amount = method['amount'] as double? ?? 0.0;
        final methodName = methodId == 1 ? 'Naqd' : 'Plastik';
        final formattedAmount = _formatNumber(amount);

        // Align payment method and amount
        final methodValue = '$formattedAmount so\'m';
        final methodPadding = ' ' * (pageWidth - methodName.length - methodValue.length);
        commands.addAll(utf8.encode('$methodName$methodPadding$methodValue'));
        commands.add(0x0A); // Line feed
      }
    }

    // Change amount (always 0 in the example)
    final qaytimLabel = 'Qaytim';
    final qaytimValue = '0 so\'m';
    final qaytimPadding = ' ' * (pageWidth - qaytimLabel.length - qaytimValue.length);
    commands.addAll(utf8.encode('$qaytimLabel$qaytimPadding$qaytimValue'));
    commands.add(0x0A); // Line feed

    // Horizontal line
    commands.addAll([0x1B, 0x45, 0x01]); // Bold on
    commands.addAll(utf8.encode('-' * pageWidth));
    commands.add(0x0A); // Line feed
    commands.addAll([0x1B, 0x45, 0x00]); // Bold off

    // Thank you message - properly centered with larger font
    if (!isPurchaseReceipt) {
      // Thank you message - truly centered with larger font
      commands.addAll([0x1D, 0x21, 0x01]); // GS ! 01 - Slightly larger font (just height doubled)
      final thankYouMsg = _sanitizeText('Xaridingiz uchun rahmat!');
      final leftPadding = (pageWidth - thankYouMsg.length) ~/ 2;
      final rightPadding = pageWidth - thankYouMsg.length - leftPadding;
      final paddedThankYou = ' ' * leftPadding + thankYouMsg + ' ' * rightPadding;
      commands.addAll(utf8.encode(paddedThankYou));
      commands.add(0x0A); // Line feed
      commands.addAll([0x1D, 0x21, 0x00]); // Reset font size
    }
  }

  // Helper functions
  static List<String> _wrapTextWithDash(String string, {int maxLength = 8}) {
    List<String> result = [];
    String currentLine = '';

    // Split text into words
    List<String> words = string.split(' ');

    for (var word in words) {
      // If word is longer than maxLength, split with dashes
      if (word.length > maxLength) {
        if (currentLine.isNotEmpty) {
          // Add current line to result and process long word separately
          result.add(currentLine);
          currentLine = '';
        }

        // Split long word with dashes - always put dash at 8th character
        String remainingWord = word;
        while (remainingWord.length > 8) {
          // Always split at 8 characters with dash
          String lineWithDash = remainingWord.substring(0, 7) + '-';
          result.add(lineWithDash);

          // Move to next part of the word
          remainingWord = remainingWord.substring(7);
        }

        // Add any remaining part of the word
        if (remainingWord.isNotEmpty) {
          currentLine = remainingWord;
        }
      }
      // If adding this word exceeds maxLength
      else if (currentLine.length + word.length + (currentLine.isEmpty ? 0 : 1) > maxLength) {
        // Add current line to result and start new line with current word
        result.add(currentLine);
        currentLine = word;
      }
      else {
        // Add space if not at beginning of line
        if (currentLine.isNotEmpty) {
          currentLine += ' ';
        }
        currentLine += word;
      }
    }

    // Add the last line if not empty
    if (currentLine.isNotEmpty) {
      result.add(currentLine);
    }

    return result.isEmpty ? [string] : result;
  }

  static void _appendLabelWithRightAlignedValue(List<int> commands, String label, String value, int pageWidth) {
    final maxLabelWidth = 13; // Adjust to fit your receipt width
    final maxValueWidth = pageWidth - maxLabelWidth - 1;

    // Wrap the value if needed
    final wrappedValues = _wrapTextWithDash(_sanitizeText(value), maxLength: maxValueWidth);

    // First line includes the label
    if (wrappedValues.isNotEmpty) {
      final firstLine = wrappedValues[0];
      final padding = ' ' * (pageWidth - label.length - firstLine.length);
      commands.addAll(utf8.encode('$label$padding$firstLine'));
      commands.add(0x0A); // Line feed
    }

    // Remaining lines (if any)
    if (wrappedValues.length > 1) {
      final labelSpace = ' ' * maxLabelWidth;
      for (int i = 1; i < wrappedValues.length; i++) {
        final padding = ' ' * (pageWidth - labelSpace.length - wrappedValues[i].length);
        commands.addAll(utf8.encode('$labelSpace$padding${wrappedValues[i]}'));
        commands.add(0x0A); // Line feed
      }
    }
  }

  static String _sanitizeText(String text) {
    // Replace problematic characters with better alternatives
    return text.replaceAll('ʻ', '\'')
               .replaceAll('ʼ', '\'')
               .replaceAll('Oʻ', 'O\'')
               .replaceAll('oʻ', 'o\'')
               .replaceAll('Gʻ', 'G\'')
               .replaceAll('gʻ', 'g\'')
               .replaceAll('ҳ', 'h')
               .replaceAll('қ', 'q')
               .replaceAll('ғ', 'g\'')
               .replaceAll('ў', 'u');
  }

  static String _formatNumber(double number) {
    // Format number with thousands separator
    String result = number.toString();
    try {
      // Simple formatting: add spaces for thousands
      int decimalIndex = result.indexOf('.');
      if (decimalIndex == -1) decimalIndex = result.length;

      String integerPart = result.substring(0, decimalIndex);
      String decimalPart = decimalIndex < result.length ? result.substring(decimalIndex) : '';

      String formattedInt = '';
      for (int i = 0; i < integerPart.length; i++) {
        if (i > 0 && (integerPart.length - i) % 3 == 0) {
          formattedInt += ' ';
        }
        formattedInt += integerPart[i];
      }

      return formattedInt + decimalPart;
    } catch (e) {
      return result;
    }
  }
}
