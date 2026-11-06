// Live updates, as the web app's live(): server-sent events from /api/platform/my/stream with
// the bearer token in a header; "samples" (tag, value, ts, quality) and "status" (online,
// offline). Reconnects after an error or when the server ends the stream (every five minutes).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

class LiveEvent {
  LiveEvent(this.type, this.data);

  final String type;      // samples | status | alert
  final dynamic data;
}

class Live {
  Live(this.api);

  final Api api;
  final _events = StreamController<LiveEvent>.broadcast();
  bool _running = false;
  http.Client? _client;

  Stream<LiveEvent> get events => _events.stream;

  void start() {
    if (_running) return;
    _running = true;
    _loop();
  }

  void stop() {
    _running = false;
    _client?.close();
  }

  Future<void> _loop() async {
    var renew = false;
    while (_running) {
      try {
        final token = await api.accessToken(renew: renew);
        if (token == null || api.server.isEmpty) {
          await Future<void>.delayed(const Duration(seconds: 10));
          continue;
        }
        _client = http.Client();
        final req = http.Request('GET', Uri.parse('${api.server}/api/platform/my/stream'))
          ..headers['Authorization'] = 'Bearer $token'
          ..headers['Accept'] = 'text/event-stream';
        final r = await _client!.send(req);
        if (r.statusCode == 401) {
          renew = true;
          continue;
        }
        renew = false;
        if (r.statusCode != 200) throw Exception('stream ${r.statusCode}');
        var buffer = '';
        await for (final chunk in r.stream.transform(utf8.decoder)) {
          if (!_running) break;
          buffer += chunk;
          int cut;
          while ((cut = buffer.indexOf('\n\n')) >= 0) {
            final block = buffer.substring(0, cut);
            buffer = buffer.substring(cut + 2);
            String? type;
            String? data;
            for (final line in block.split('\n')) {
              if (line.startsWith('event: ')) type = line.substring(7).trim();
              if (line.startsWith('data: ')) data = line.substring(6);
            }
            if (type != null && data != null) {
              try {
                _events.add(LiveEvent(type, json.decode(data)));
              } catch (_) {
                // a broken frame is skipped
              }
            }
          }
        }
      } catch (_) {
        // offline or closed: try again shortly
      } finally {
        _client?.close();
      }
      if (_running) await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
}

/// Apply a "samples" event to views (/my/views entries); true when anything changed.
bool applySamples(List<Map<String, dynamic>> views, dynamic samples) {
  if (samples is! List) return false;
  var changed = false;
  for (final s in samples) {
    final parts = '${s['tag']}'.split('.');      // platform.devices.<id>.<key>
    if (parts.length != 4) continue;
    for (final v in views) {
      if (v['device']['device_id'] != parts[2]) continue;
      for (final t in (v['tags'] as List)) {
        if (t['key'] == parts[3]) {
          t['value'] = s['value'];
          t['quality'] = s['quality'];
          changed = true;
        }
      }
    }
  }
  return changed;
}

/// Apply a "status" event (a device went online or offline).
bool applyStatus(List<Map<String, dynamic>> views, dynamic status) {
  if (status is! Map || status['state'] == null) return false;
  for (final v in views) {
    if (v['device']['device_id'] == status['device_id']) {
      v['device']['state'] = status['state'];
      return true;
    }
  }
  return false;
}
