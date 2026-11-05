// The camera reads a device's QR label (…/#/claim/<identifier>/<code>) and returns both.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_state.dart';

/// The label's identifier and code from its QR text, or null when it is not a label.
(String, String)? parseLabel(String text) {
  final m = RegExp(r'#/claim/([^/\s?#]+)/([^/\s?#]+)').firstMatch(text);
  return m == null ? null : (Uri.decodeComponent(m[1]!), Uri.decodeComponent(m[2]!));
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _message;

  void _found(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final label = parseLabel(code.rawValue ?? '');
      if (label != null) {
        _done = true;
        Navigator.pop(context, label);
        return;
      }
    }
    setState(() => _message = widget.state.t('add.not_a_label'));
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('add.scan'))),
      body: Stack(children: [
        MobileScanner(
          controller: _camera,
          onDetect: _found,
          errorBuilder: (_, __) => Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(s.t('add.scan_unavailable'), textAlign: TextAlign.center),
          )),
        ),
        Center(
          child: Container(
            width: 240, height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        Positioned(
          left: 20, right: 20, bottom: 40,
          child: Text(_message ?? s.t('add.scan_title'), textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
        ),
      ]),
    );
  }
}
