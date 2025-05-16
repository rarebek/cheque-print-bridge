import 'package:flutter/material.dart';
import 'dart:convert';
import 'cheque_formatter.dart';

class ChequeDesignerPage extends StatefulWidget {
  const ChequeDesignerPage({Key? key}) : super(key: key);

  @override
  State<ChequeDesignerPage> createState() => _ChequeDesignerPageState();
}

class _ChequeDesignerPageState extends State<ChequeDesignerPage> {
  List<Map<String, dynamic>> _receiptElements = [];
  final TextEditingController _textController = TextEditingController();
  String _alignment = 'left';
  bool _isBold = false;
  bool _isUnderline = false;
  int _leftPadding = 0;
  String? _rightValue;
  final TextEditingController _rightValueController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController(text: 'My Company');

  // Preview options
  int _pageWidth = 32;
  bool _useAutoCut = true;
  int _feedLineCount = 4;

  @override
  void dispose() {
    _textController.dispose();
    _rightValueController.dispose();
    _companyNameController.dispose();
    super.dispose();
  }

  void _addElement() {
    if (_textController.text.isEmpty) return;

    final element = {
      'type': 'text',
      'text': _textController.text,
      'alignment': _alignment,
      'bold': _isBold,
      'underline': _isUnderline,
      'leftPadding': _leftPadding,
    };

    if (_alignment == 'justified' && _rightValueController.text.isNotEmpty) {
      element['rightValue'] = _rightValueController.text;
    }

    setState(() {
      _receiptElements.add(element);
      _textController.clear();
      _rightValueController.clear();
    });
  }

  void _removeElement(int index) {
    setState(() {
      _receiptElements.removeAt(index);
    });
  }

  void _moveElementUp(int index) {
    if (index <= 0) return;
    setState(() {
      final element = _receiptElements.removeAt(index);
      _receiptElements.insert(index - 1, element);
    });
  }

  void _moveElementDown(int index) {
    if (index >= _receiptElements.length - 1) return;
    setState(() {
      final element = _receiptElements.removeAt(index);
      _receiptElements.insert(index + 1, element);
    });
  }

  Map<String, dynamic> _buildChequeData() {
    // Create sample data for preview
    final products = [
      {
        "name": "Sample Product 1",
        "quantity": 2.0,
        "unitName": "pcs",
        "currentPrice": 15000.0,
        "status": 1
      },
      {
        "name": "Sample Product with a very long name that will wrap",
        "quantity": 1.0,
        "unitName": "kg",
        "currentPrice": 25000.0,
        "status": 1
      }
    ];

    // Calculate total
    double totalAmount = 0.0;
    for (final product in products) {
      totalAmount += (product["currentPrice"] as double) * (product["quantity"] as double);
    }

    return {
      "companyName": _companyNameController.text,
      "transactionId": "SAMPLE-12345",
      "createdAt": DateTime.now().toIso8601String(),
      "status": 1,
      "statusName": "",
      "seller": "Demo Seller",
      "receiver": "",
      "supplierName": "",
      "totalAmount": totalAmount,
      "finalAmount": totalAmount,
      "products": products,
      "paymentMethods": [
        {"methodId": 1, "amount": totalAmount}
      ],
      "receiptElements": _receiptElements
    };
  }

  String _getPreviewText() {
    final chequeData = _buildChequeData();
    final commands = ChequeFormatter.formatCheque(
      chequeDetails: chequeData,
      pageWidth: _pageWidth,
      useAutoCut: _useAutoCut,
      feedLineCount: _feedLineCount,
    );

    // Convert ESC/POS commands to printable ASCII text for preview
    List<String> lines = [];
    List<int> currentLine = [];

    for (int i = 0; i < commands.length; i++) {
      final byte = commands[i];

      // Skip ESC/POS command sequences
      if (byte == 0x1B || byte == 0x1D) {
        // ESC or GS command, skip sequence
        if (i + 1 < commands.length) {
          final nextByte = commands[i + 1];
          if (byte == 0x1B && nextByte == 0x40) {
            // ESC @ (init) - skip 2 bytes
            i += 1;
            continue;
          } else if (byte == 0x1B && nextByte == 0x61) {
            // ESC a (alignment) - skip 3 bytes
            i += 2;
            continue;
          } else if (byte == 0x1B && (nextByte == 0x45 || nextByte == 0x2D)) {
            // ESC E (bold) or ESC - (underline) - skip 3 bytes
            i += 2;
            continue;
          } else if (byte == 0x1B && nextByte == 0x74) {
            // ESC t (codepage) - skip 3 bytes
            i += 2;
            continue;
          } else if (byte == 0x1D && nextByte == 0x21) {
            // GS ! (font size) - skip 3 bytes
            i += 2;
            continue;
          } else if (byte == 0x1D && nextByte == 0x56) {
            // GS V (cut) - skip 3 bytes
            i += 2;
            continue;
          }
        }
      } else if (byte == 0x0A) {
        // Line feed
        if (currentLine.isNotEmpty) {
          try {
            lines.add(utf8.decode(currentLine));
          } catch (e) {
            lines.add(""); // Add empty line if decode fails
          }
          currentLine = [];
        } else {
          lines.add("");
        }
        continue;
      } else {
        // Regular character
        currentLine.add(byte);
      }
    }

    // Add last line if exists
    if (currentLine.isNotEmpty) {
      try {
        lines.add(utf8.decode(currentLine));
      } catch (e) {
        // Ignore decode error
      }
    }

    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cheque Designer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              // Return formatted data back to main screen
              Navigator.pop(context, _buildChequeData());
            },
          )
        ],
      ),
      body: Row(
        children: [
          // Left panel - cheque element editor
          Expanded(
            flex: 2,
            child: Card(
              margin: const EdgeInsets.all(8.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Company name
                    TextField(
                      controller: _companyNameController,
                      decoration: const InputDecoration(
                        labelText: 'Company Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),

                    // Page width settings
                    Row(
                      children: [
                        const Text('Page Width:'),
                        Expanded(
                          child: Slider(
                            value: _pageWidth.toDouble(),
                            min: 20,
                            max: 48,
                            divisions: 28,
                            label: _pageWidth.toString(),
                            onChanged: (value) => setState(() {
                              _pageWidth = value.toInt();
                            }),
                          ),
                        ),
                        Text(_pageWidth.toString()),
                      ],
                    ),

                    const Divider(),
                    const Text(
                      'Add Custom Elements',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    // Text input
                    TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        labelText: 'Element Text',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Alignment options
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'left', icon: Icon(Icons.format_align_left)),
                        ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center)),
                        ButtonSegment(value: 'right', icon: Icon(Icons.format_align_right)),
                        ButtonSegment(value: 'justified', icon: Icon(Icons.format_align_justify)),
                      ],
                      selected: {_alignment},
                      onSelectionChanged: (Set<String> selection) {
                        setState(() {
                          _alignment = selection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Text formatting
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Bold'),
                          selected: _isBold,
                          onSelected: (selected) {
                            setState(() {
                              _isBold = selected;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Underline'),
                          selected: _isUnderline,
                          onSelected: (selected) {
                            setState(() {
                              _isUnderline = selected;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Left Padding',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setState(() {
                                _leftPadding = int.tryParse(value) ?? 0;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Right value for justified alignment
                    if (_alignment == 'justified')
                      TextField(
                        controller: _rightValueController,
                        decoration: const InputDecoration(
                          labelText: 'Right Value',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Add button
                    ElevatedButton(
                      onPressed: _addElement,
                      child: const Text('Add Element'),
                    ),

                    const Divider(),
                    const Text(
                      'Elements',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    // Elements list
                    Expanded(
                      child: ListView.builder(
                        itemCount: _receiptElements.length,
                        itemBuilder: (context, index) {
                          final element = _receiptElements[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(
                                element['text'] as String,
                                style: TextStyle(
                                  fontWeight: (element['bold'] as bool) ? FontWeight.bold : FontWeight.normal,
                                  decoration: (element['underline'] as bool) ? TextDecoration.underline : null,
                                ),
                              ),
                              subtitle: Text('Alignment: ${element['alignment']}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_upward),
                                    onPressed: () => _moveElementUp(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.arrow_downward),
                                    onPressed: () => _moveElementDown(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _removeElement(index),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Right panel - preview
          Expanded(
            flex: 1,
            child: Card(
              margin: const EdgeInsets.all(8.0),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Preview',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        color: Colors.grey.shade200,
                        padding: const EdgeInsets.all(8.0),
                        child: SingleChildScrollView(
                          child: Text(
                            _getPreviewText(),
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
