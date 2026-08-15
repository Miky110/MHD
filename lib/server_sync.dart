import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef RemoteTripHandler = void Function({
  required String lineNumber,
  required int stopIndex,
  required bool running,
});

class ServerSyncService {
  static const _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wxmbpkfbdyvgbzkprcdj.supabase.co',
  );
  static const _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_7eSkcp95UcpbHnzoz5P7hA_vxxrtdnR',
  );

  bool _initialized = false;
  StreamSubscription<List<Map<String, dynamic>>>? _tripSubscription;

  bool get isConfigured => _url.isNotEmpty && _publishableKey.isNotEmpty;
  bool get isReady => _initialized;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> initialize() async {
    if (!isConfigured || _initialized) return;
    await Supabase.initialize(url: _url, publishableKey: _publishableKey);
    _initialized = true;
  }

  Future<void> publishTrip({
    required String lineNumber,
    required int stopIndex,
    required bool running,
  }) async {
    if (!_initialized) return;
    await _client.from('active_trips').upsert({
      'id': 'main',
      'line_number': lineNumber,
      'stop_index': stopIndex,
      'running': running,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void watchTrip(RemoteTripHandler onTrip) {
    if (!_initialized) return;
    _tripSubscription?.cancel();
    _tripSubscription = _client
        .from('active_trips')
        .stream(primaryKey: ['id'])
        .eq('id', 'main')
        .listen((rows) {
          if (rows.isEmpty) return;
          final row = rows.first;
          onTrip(
            lineNumber: row['line_number'] as String,
            stopIndex: row['stop_index'] as int,
            running: row['running'] as bool,
          );
        });
  }

  Future<void> dispose() async {
    await _tripSubscription?.cancel();
  }
}

final serverSync = ServerSyncService();
