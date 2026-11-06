// A home's settings, as the web app's (more.js homeSettings): its name, its place (for sunrise /
// sunset and arriving / leaving), the electricity tariff and the holidays of this Jalali year
// (the SMS / call contacts and the SMS PIN are on the home's access page, members.dart). Only
// the owner changes them; the rest only see.
// Last, how this phone reaches the home's devices (connection.dart; kept on the phone).

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/connection.dart';
import '../core/i18n.dart';
import '../ui/kit.dart';

class HomeSettingsScreen extends StatefulWidget {
  const HomeSettingsScreen({super.key, required this.state, required this.home});

  final AppState state;
  final Map<String, dynamic> home;      // a row of /api/account/organizations

  @override
  State<HomeSettingsScreen> createState() => _HomeSettingsScreenState();
}

class _Tier {
  _Tier(Object? upTo, Object? price)
      : upTo = TextEditingController(text: upTo == null ? '' : '$upTo'),
        price = TextEditingController(text: price == null ? '' : '$price');

  final TextEditingController upTo;
  final TextEditingController price;
}

class _HomeSettingsScreenState extends State<HomeSettingsScreen> {
  Map<String, dynamic>? settings;
  List<Map<String, dynamic>> holidays = [];
  String? error;
  final _name = TextEditingController();
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  final _radius = TextEditingController();
  final _peakFrom = TextEditingController();
  final _peakTo = TextEditingController();
  final _factor = TextEditingController();
  final _fixed = TextEditingController();
  final _tax = TextEditingController();
  final List<_Tier> tiers = [];
  late Connection way = Connection.of(widget.state.store, _org);
  late final _localHub = TextEditingController(text: way.local);

  String get _org => widget.home['org_id'] as String;
  bool get _owner => widget.home['role_id'] == 'customer_owner';
  bool get _personal => widget.home['personal'] == true;
  int get _year => I18n.jalali(DateTime.now().year, DateTime.now().month, DateTime.now().day)[0];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.state.api;
    try {
      final s = await api.call('GET', '/api/platform/organizations/$_org/settings') as Map<String, dynamic>;
      _name.text = _personal ? widget.state.t('me.my_home') : '${widget.home['name'] ?? ''}';
      _lat.text = '${s['latitude'] ?? ''}';
      _lon.text = '${s['longitude'] ?? ''}';
      _radius.text = '${s['radius_m'] ?? 150}';
      final tariff = (s['tariff'] as Map?) ?? const {};
      final list = ((tariff['tiers'] as List?) ?? const []).cast<Map>();
      tiers
        ..clear()
        ..addAll(list.isEmpty ? [_Tier(100, null), _Tier(null, null)] : [for (final x in list) _Tier(x['up_to_kwh'], x['price'])]);
      _peakFrom.text = '${tariff['peak_from'] ?? ''}';
      _peakTo.text = '${tariff['peak_to'] ?? ''}';
      _factor.text = '${tariff['peak_factor'] ?? 1}';
      _fixed.text = '${tariff['fixed'] ?? 0}';
      _tax.text = '${tariff['tax_percent'] ?? 0}';
      settings = s;
    } on ApiError catch (e) {
      error = e.message;
    }
    if (mounted) setState(() {});
    _loadHolidays();
  }

  Future<void> _loadHolidays() async {
    try {
      holidays = (await widget.state.api.call('GET', '/api/platform/organizations/$_org/holidays?year=$_year') as List)
          .cast<Map<String, dynamic>>();
    } on ApiError {
      holidays = [];
    }
    if (mounted) setState(() {});
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  double? _number(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  Future<void> _here() async {
    final s = widget.state;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw Exception();
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(5);
        _lon.text = pos.longitude.toStringAsFixed(5);
      });
    } catch (_) {
      _toast(s.t('homeset.no_location'));
    }
  }

  Future<void> _save() async {
    final s = widget.state;
    try {
      final name = _name.text.trim();
      if (!_personal && name.isNotEmpty && name != widget.home['name']) {
        await s.api.call('PATCH', '/api/account/homes/$_org', {'name': name});
      }
      await s.api.call('PUT', '/api/platform/organizations/$_org/settings', {
        'latitude': _number(_lat),
        'longitude': _number(_lon),
        'radius_m': (_number(_radius) ?? 150).round(),
        'tariff': {
          'tiers': [
            for (final x in tiers)
              if (_number(x.price) != null) {'up_to_kwh': _number(x.upTo), 'price': _number(x.price)},
          ],
          'peak_from': _peakFrom.text.trim().isEmpty ? null : _peakFrom.text.trim(),
          'peak_to': _peakTo.text.trim().isEmpty ? null : _peakTo.text.trim(),
          'peak_factor': _number(_factor) ?? 1,
          'fixed': _number(_fixed) ?? 0,
          'tax_percent': _number(_tax) ?? 0,
          'currency': s.i18n.lang == 'fa' ? 'ریال' : 'IRR',
        },
      });
      await s.load();
      _toast(s.t('common.saved'));
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _time(TextEditingController c) async {
    final parts = c.text.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: parts.length == 2
          ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 18, minute: int.tryParse(parts[1]) ?? 0)
          : const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked != null) {
      setState(() => c.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _addHoliday() async {
    final s = widget.state;
    final date = TextEditingController(text: '$_year/');
    final name = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(s.t('mobile.holiday_add')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: date, textDirection: TextDirection.ltr, keyboardType: TextInputType.datetime,
            decoration: InputDecoration(labelText: s.t('mobile.holiday_date'), hintText: '1405/07/13')),
        TextField(controller: name, maxLength: 80, decoration: InputDecoration(labelText: s.t('contacts.name'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('common.save'))),
      ],
    ));
    if (ok != true) return;
    try {
      await s.api.call('POST', '/api/platform/organizations/$_org/holidays',
          {'date': date.text.trim(), 'name': name.text.trim().isEmpty ? s.t('auto.holidays') : name.text.trim()});
      _loadHolidays();
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  Widget _card(String title, List<Widget> children, {String? help}) {
    final tk = Tk.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tk.text)),
        if (help != null) Padding(padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(help, style: TextStyle(fontSize: 12, height: 1.6, color: tk.muted))),
        const SizedBox(height: 6),
        ...children,
      ])),
    );
  }

  Widget _field(TextEditingController c, String label, {bool number = true, VoidCallback? tap}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: TextField(controller: c, enabled: _owner, readOnly: tap != null, onTap: tap,
              textDirection: TextDirection.ltr,
              keyboardType: number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
              decoration: InputDecoration(labelText: label)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tk = Tk.of(context);
    final title = _personal ? s.t('me.my_home') : '${widget.home['name'] ?? ''}';
    if (settings == null) {
      return Scaffold(appBar: AppBar(title: Text(s.t('homeset.title'))),
          body: Center(child: error == null ? const CircularProgressIndicator() : Text(error!)));
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.t('homeset.title')), bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18), child: Text(title, style: TextStyle(color: tk.muted)))),
      body: GlowPage(child: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), children: [
        _card(s.t('homeset.name'), [
          TextField(controller: _name, enabled: _owner && !_personal),
        ]),
        _card(s.t('homeset.place'), help: s.t('homeset.place_help'), [
          Row(children: [_field(_lat, s.t('homeset.lat')), _field(_lon, s.t('homeset.lon'))]),
          Row(children: [_field(_radius, s.t('homeset.radius'))]),
          OutlinedButton.icon(onPressed: _owner ? _here : null, icon: const Icon(Icons.my_location_rounded),
              label: Text(s.t('homeset.here'))),
        ]),
        _card(s.t('homeset.tariff'), help: s.t('homeset.tariff_help'), [
          for (final x in tiers)
            Row(children: [
              _field(x.upTo, '${s.t('homeset.up_to')} (${s.t('homeset.last_tier')} = —)'),
              _field(x.price, s.t('homeset.price')),
              IconButton(icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: _owner ? () => setState(() => tiers.remove(x)) : null),
            ]),
          OutlinedButton.icon(onPressed: _owner ? () => setState(() => tiers.add(_Tier(null, null))) : null,
              icon: const Icon(Icons.add_rounded), label: Text(s.t('homeset.add_tier'))),
          Row(children: [
            _field(_peakFrom, s.t('homeset.peak_from'), number: false, tap: () => _time(_peakFrom)),
            _field(_peakTo, s.t('homeset.peak_to'), number: false, tap: () => _time(_peakTo)),
          ]),
          Row(children: [_field(_factor, s.t('homeset.factor')), _field(_tax, s.t('homeset.tax'))]),
          Row(children: [_field(_fixed, s.t('homeset.fixed'))]),
        ]),
        FilledButton(onPressed: _owner ? _save : null, child: Text(s.t('common.save'))),
        const SizedBox(height: 18),
        _card(s.t('auto.holidays'), [
          for (final h in holidays)
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: Icon(h['source'] == 'organization' ? Icons.home_rounded : Icons.event_rounded,
                  color: h['source'] == 'organization' ? tk.accent : tk.muted),
              title: Text('${h['name']}'),
              trailing: Text(s.i18n.num(h['date']), textDirection: TextDirection.ltr),
            ),
          OutlinedButton.icon(onPressed: _owner ? _addHoliday : null, icon: const Icon(Icons.add_rounded),
              label: Text(s.t('mobile.holiday_add'))),
        ]),
        _connectionCard(),
      ])),
    );
  }

  /// Kept on this phone: anyone of the home may choose it, not only the owner.
  Widget _connectionCard() {
    final s = widget.state;
    final tk = Tk.of(context);
    return _card(s.t('connect.title'), help: s.t('connect.help'), [
      for (final (i, (icon, label)) in [
        (Icons.public_rounded, s.t('connect.step_cloud')),
        (Icons.router_rounded, s.t('connect.step_local')),
        (Icons.sms_rounded, s.t('connect.step_sms')),
      ].indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Text(s.i18n.num(i + 1), style: TextStyle(color: tk.accent, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Icon(icon, size: 18, color: tk.muted),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13, color: tk.text)),
          ]),
        ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: way.order,
        decoration: InputDecoration(labelText: s.t('connect.order')),
        isExpanded: true,
        items: [for (final o in Connection.orders) DropdownMenuItem(value: o, child: Text(s.t('connect.$o')))],
        onChanged: (v) => setState(() => way = Connection(order: v ?? 'auto', local: way.local)),
      ),
      const SizedBox(height: 10),
      TextField(controller: _localHub, keyboardType: TextInputType.url, textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: s.t('connect.local'), hintText: s.t('connect.local_hint'))),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: () async {
          final url = _localHub.text.trim();
          if (!Connection.validLocal(url)) {
            _toast(s.t('connect.bad_url'));
            return;
          }
          way = Connection(order: way.order, local: url);
          await way.save(s.store, _org);
          _toast(s.t('common.saved'));
        },
        child: Text(s.t('common.save')),
      ),
    ]);
  }
}
