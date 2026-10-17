import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef RemoteTripHandler = void Function({
  required String lineNumber,
  required int stopIndex,
  required int startStopIndex,
  required int endStopIndex,
  required bool running,
  required String direction,
  required int delayMinutes,
  required String occupancy,
  required bool stopRequested,
  String? alertText,
  String? driverId,
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
    required int startStopIndex,
    required int endStopIndex,
    required bool running,
    required String direction,
    required int delayMinutes,
    required String occupancy,
    required bool stopRequested,
    String? alertText,
    String? driverId,
  }) async {
    if (!_initialized) return;
    await _client.from('active_trips').upsert({
      'id': 'main',
      'line_number': lineNumber,
      'stop_index': stopIndex,
      'start_stop_index': startStopIndex,
      'end_stop_index': endStopIndex,
      'running': running,
      'direction': direction,
      'delay_minutes': delayMinutes,
      'occupancy': occupancy,
      'stop_requested': stopRequested,
      'alert_text': alertText,
      'driver_id': driverId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> requestStop(bool requested) async {
    if (!_initialized) return;
    await _client.from('active_trips').update({
      'stop_requested': requested,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', 'main');
  }

  Future<List<Map<String, dynamic>>> fetchStops() async {
    if (!_initialized) return [];
    final rows = await _client.from('stops').select().order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> fetchLines() async {
    if (!_initialized) return [];
    final rows = await _client.from('lines').select().order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> fetchDepartures() async {
    if (!_initialized) return [];
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 5))
        .toIso8601String();
    final scheduled = await _client
        .from('scheduled_departures')
        .select()
        .gte('departure_time', cutoff)
        .order('departure_time')
        .limit(500);
    final shifts = await _client
        .from('shifts')
        .select()
        .inFilter('status', const ['active', 'scheduled'])
        .order('start_time')
        .limit(500);
    return [
      ...List<Map<String, dynamic>>.from(scheduled)
          .map((row) => {...row, '_source': 'scheduled_departures'}),
      ...List<Map<String, dynamic>>.from(shifts)
          .map((row) => {...row, '_source': 'shifts'}),
    ];
  }

  Future<void> saveStop(Map<String, dynamic> stop) async {
    if (!_initialized) return;
    await _client.from('stops').upsert(stop);
  }

  Future<void> deleteStop(String id) async {
    if (!_initialized) return;
    await _client.from('stops').delete().eq('id', id);
  }

  Future<void> saveLine(Map<String, dynamic> line) async {
    if (!_initialized) return;
    await _client.from('lines').upsert(line);
  }

  Future<void> deleteLine(String id) async {
    if (!_initialized) return;
    await _client.from('lines').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchDrivers() async {
    if (!_initialized) return [];
    final rows = await _client.from('drivers').select().order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> saveDriver(Map<String, dynamic> driver) async {
    if (!_initialized) return;
    await _client.from('drivers').upsert(driver);
  }

  Future<void> deleteDriver(String id) async {
    if (!_initialized) return;
    await _client.from('drivers').delete().eq('id', id);
  }

  Future<Map<String, String>> fetchLineGongs() async {
    if (!_initialized) return {};
    final rows = await _client.from('line_gongs').select();
    return {for (final row in rows) '${row['line_id']}': '${row['audio_url']}'};
  }

  Future<void> saveLineGong(String lineId, String audioUrl) async {
    if (!_initialized) return;
    await _client.from('line_gongs').upsert({
      'line_id': lineId,
      'audio_url': audioUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> importPragueData({
    required List<Map<String, dynamic>> stops,
    required List<Map<String, dynamic>> routes,
  }) async {
    if (!_initialized) return;
    await _client.from('prague_stops').delete().neq('id', '');
    await _client.from('prague_lines').delete().neq('id', '');
    for (var index = 0; index < stops.length; index += 500) {
      final chunk = stops.skip(index).take(500).map(
            (row) => {
              'id': row['stop_id'],
              'name': row['stop_name'],
              'latitude': double.tryParse('${row['stop_lat']}'),
              'longitude': double.tryParse('${row['stop_lon']}'),
              'zone': row['zone_id'],
              'location_type': int.tryParse('${row['location_type']}') ?? 0,
              'parent_station': '${row['parent_station']}'.isEmpty
                  ? null
                  : row['parent_station'],
            },
          );
      await _client.from('prague_stops').upsert(chunk.toList());
    }
    for (var index = 0; index < routes.length; index += 500) {
      final chunk = routes.skip(index).take(500).map(
            (row) => {
              'id': row['route_id'],
              'short_name': row['route_short_name'],
              'long_name': row['route_long_name'] ?? '',
              'route_type': int.tryParse('${row['route_type']}'),
              'color': row['route_color'],
              'text_color': row['route_text_color'],
            },
          );
      await _client.from('prague_lines').upsert(chunk.toList());
    }
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
            startStopIndex: row['start_stop_index'] as int? ?? 0,
            endStopIndex: row['end_stop_index'] as int? ?? 0,
            running: row['running'] as bool,
            direction: row['direction'] as String? ?? 'forward',
            delayMinutes: row['delay_minutes'] as int? ?? 0,
            occupancy: row['occupancy'] as String? ?? 'low',
            stopRequested: row['stop_requested'] as bool? ?? false,
            alertText: row['alert_text'] as String?,
            driverId: row['driver_id'] as String?,
          );
        });
  }

  Future<void> dispose() async {
    await _tripSubscription?.cancel();
  }
}

final serverSync = ServerSyncService();
