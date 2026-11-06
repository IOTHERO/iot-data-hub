// Adding a device with the identifier and claim code of its label (POST /api/platform/claim):
// scanned with the camera, typed, or a pasted label link (…/#/claim/<identifier>/<code>).

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import 'scan.dart';
import 'edge_add.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key, required this.state});

  final AppState state;

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _identifier = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  void _fromLink(String text) {
    final label = parseLabel(text);
    if (label == null) return;
    _identifier.text = label.$1;
    _code.text = label.$2;
  }

  Future<void> _scan() async {
    final label = await Navigator.push<(String, String)>(context,
        MaterialPageRoute(builder: (_) => ScanScreen(state: widget.state)));
    if (label == null) return;
    setState(() { _identifier.text = label.$1; _code.text = label.$2; });
  }

  Future<void> _submit() async {
    final s = widget.state;
    setState(() { _busy = true; _error = null; });
    try {
      final owned = s.homes.where((h) => h['role_id'] == 'customer_owner' && h['personal'] != true);
      final target = s.home != null ? owned.where((h) => h['org_id'] == s.home).firstOrNull : null;
      await s.api.call('POST', '/api/platform/claim', {
        'identifier': _identifier.text.trim(),
        'code': _code.text.trim(),
        if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
        if (target != null) 'organization': target['org_id'],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('add.added'))));
      Navigator.pop(context, true);
      return;
    } on ApiError catch (e) {
      _error = s.i18n.has('errors.${e.code}') ? s.t('errors.${e.code}') : e.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    final code = TextStyle(letterSpacing: 1, color: tk.text);
    return WebPage(title: s.t('nav.add'), children: [
      // .scan: the camera frame - a touch opens the scanner
      Material(
        color: tk.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32), side: BorderSide(color: tk.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _scan,
          child: SizedBox(
            height: 290,
            child: Stack(alignment: Alignment.center, children: [
              Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: tk.accent.withValues(alpha: 0.10), blurRadius: 60, spreadRadius: 30)])),
              Semantics(label: s.t('add.scan'), button: true,
                  child: CustomPaint(size: const Size(190, 190), painter: _ScanFrame(tk.accent))),
            ]),
          ),
        ),
      ),
      Column(children: [
        Text(s.t('add.scan_title'), style: TextStyle(fontWeight: FontWeight.w700, color: tk.text)),
        const SizedBox(height: 4),
        Text(s.t('add.hint'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.8, color: tk.muted)),
        Text(s.t('add.tap_to_scan'), style: TextStyle(fontSize: 13, color: tk.muted)),
      ]),
      Row(children: [           // .divider
        Expanded(child: Container(height: 1, color: tk.line)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(s.t('add.or_manual'), style: TextStyle(fontSize: 12, color: tk.faint))),
        Expanded(child: Container(height: 1, color: tk.line)),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        WebField(label: s.t('add.identifier'), child: TextField(controller: _identifier, textDirection: TextDirection.ltr,
            onChanged: _fromLink, textCapitalization: TextCapitalization.characters, style: code,
            decoration: const InputDecoration(hintText: 'CTRL-8R-0001', hintTextDirection: TextDirection.ltr))),
        const SizedBox(height: 12),
        WebField(label: s.t('add.code'), child: TextField(controller: _code, textDirection: TextDirection.ltr,
            onChanged: _fromLink, textCapitalization: TextCapitalization.characters, style: code.copyWith(letterSpacing: 2),
            decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX', hintTextDirection: TextDirection.ltr))),
        const SizedBox(height: 12),
        WebField(label: s.t('add.name'), child: TextField(controller: _name)),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: tk.warn))),
        const SizedBox(height: 16),
        WebButton(s.t('add.submit'), kind: BtnKind.primary, block: true, onTap: _busy ? null : _submit),
      ]),
      WebCard(
        tight: true,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EdgeAddScreen(state: s))),
        child: Row(children: [
          Container(width: 42, height: 42,
              decoration: BoxDecoration(color: tk.ok.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.hub_rounded, color: tk.ok)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('edge.link'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tk.text)),
            Text('Modbus · OPC UA · SNMP · S7', textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 11, color: tk.muted)),
          ])),
          Icon(Icons.chevron_left_rounded, color: tk.muted),
        ]),
      ),
    ]);
  }
}

/// The web app's scanFrame(): rounded corners, a laser line across and a few QR dots (190 px).
class _ScanFrame extends CustomPainter {
  _ScanFrame(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 190;
    canvas.scale(k);
    final corners = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(4, 40)..lineTo(4, 16)..arcToPoint(const Offset(16, 4), radius: const Radius.circular(12))..lineTo(40, 4)
      ..moveTo(150, 4)..lineTo(174, 4)..arcToPoint(const Offset(186, 16), radius: const Radius.circular(12))..lineTo(186, 40)
      ..moveTo(186, 150)..lineTo(186, 174)..arcToPoint(const Offset(174, 186), radius: const Radius.circular(12))..lineTo(150, 186)
      ..moveTo(40, 186)..lineTo(16, 186)..arcToPoint(const Offset(4, 174), radius: const Radius.circular(12))..lineTo(4, 150);
    canvas.drawPath(path, corners);
    canvas.drawLine(const Offset(20, 95), const Offset(170, 95), Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..strokeWidth = 2);
    final dots = Paint()
      ..color = const Color(0xFF3A3F4B)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.square;
    for (final (a, b) in const [((52.0, 52.0), (72.0, 52.0)), ((52.0, 62.0), (52.0, 62.0)), ((118.0, 52.0), (138.0, 52.0)),
        ((138.0, 62.0), (138.0, 62.0)), ((52.0, 128.0), (72.0, 128.0)), ((52.0, 118.0), (52.0, 118.0)),
        ((100.0, 100.0), (100.0, 100.0)), ((118.0, 128.0), (138.0, 128.0)), ((88.0, 52.0), (98.0, 52.0)),
        ((88.0, 138.0), (98.0, 138.0)), ((128.0, 100.0), (138.0, 100.0))]) {
      canvas.drawLine(Offset(a.$1, a.$2), Offset(b.$1, b.$2), dots);
    }
  }

  @override
  bool shouldRepaint(_ScanFrame old) => old.accent != accent;
}
