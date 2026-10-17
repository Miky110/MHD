import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mhd_mikylov/database.dart';
import 'package:mhd_mikylov/gtfs_importer.dart';
import 'package:mhd_mikylov/server_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appDatabase.initialize();
  await serverSync.initialize();
  await transitData.loadFromServer();
  await activeTrip.restore();
  activeTrip.connectServer();
  runApp(const MikylovApp());
}

final transitData = TransitDataController();
final activeTrip = ActiveTripController();

class Stop {
  const Stop(
    this.name,
    this.minutes, [
    this.latitude,
    this.longitude,
    this.id,
    this.zone,
    this.type,
  ]);
  final String name;
  final int minutes;
  final double? latitude;
  final double? longitude;
  final String? id;
  final String? zone;
  final String? type;
}

class TransitLine {
  const TransitLine(
    this.number,
    this.destination,
    this.color,
    this.stops, [
    this.id,
    this.type,
    this.carrier,
    this.reverseStops = const [],
  ]);
  final String number;
  final String destination;
  final Color color;
  final List<Stop> stops;
  final String? id;
  final String? type;
  final String? carrier;
  final List<Stop> reverseStops;
}

class DriverInfo {
  const DriverInfo({
    required this.id,
    required this.name,
    required this.pin,
    this.phone,
  });
  final String id;
  final String name;
  final String pin;
  final String? phone;
}

class DepartureInfo {
  const DepartureInfo({
    required this.line,
    required this.departureTime,
    required this.destination,
    required this.status,
  });

  final TransitLine line;
  final DateTime departureTime;
  final String destination;
  final String status;
}

const demoLines = <TransitLine>[
  TransitLine('1', 'Sokolov, terminál', Color(0xFFE53935), [
    Stop('Bukovany, sídliště', 0, 50.1666, 12.5728),
    Stop('Bukovany, škola', 3, 50.1660, 12.5705),
    Stop('Citice', 8, 50.1622, 12.6148),
    Stop('Sokolov, nemocnice', 14, 50.1777, 12.6408),
    Stop('Sokolov, terminál', 18, 50.1810, 12.6402),
  ]),
  TransitLine('3', 'Habartov, náměstí', Color(0xFF1565C0), [
    Stop('Sokolov, terminál', 0, 50.1810, 12.6402),
    Stop('Citice', 9, 50.1622, 12.6148),
    Stop('Bukovany, rozcestí', 14, 50.1668, 12.5750),
    Stop('Habartov, KLU', 19, 50.1826, 12.5520),
    Stop('Habartov, náměstí', 23, 50.1829, 12.5507),
  ]),
  TransitLine('7', 'Kynšperk nad Ohří', Color(0xFF2E7D32), [
    Stop('Bukovany, sídliště', 0, 50.1666, 12.5728),
    Stop('Dasnice', 10, 50.1450, 12.5660),
    Stop('Chlum Svaté Maří', 16, 50.1511, 12.5351),
    Stop('Kynšperk, škola', 23, 50.1187, 12.5311),
    Stop('Kynšperk, aut. stanice', 27, 50.1180, 12.5300),
  ]),
];

List<TransitLine> get lines => transitData.lines;

class TransitDataController extends ChangeNotifier {
  List<TransitLine> lines = List.of(demoLines);
  List<Stop> stops = demoLines.expand((line) => line.stops).toSet().toList();
  bool loadedFromServer = false;
  List<DriverInfo> drivers = const [];
  Map<String, String> lineGongs = const {};

  Future<void> loadFromServer() async {
    if (!serverSync.isReady) return;
    List<Map<String, dynamic>> stopRows;
    List<Map<String, dynamic>> lineRows;
    List<Map<String, dynamic>> driverRows;
    try {
      stopRows = await serverSync.fetchStops();
      lineRows = await serverSync.fetchLines();
      driverRows = await serverSync.fetchDrivers();
      lineGongs = await serverSync.fetchLineGongs();
      await appDatabase.saveCache('stops', stopRows);
      await appDatabase.saveCache('lines', lineRows);
      await appDatabase.saveCache('drivers', driverRows);
      await appDatabase.saveCache('line_gongs', lineGongs);
    } catch (_) {
      stopRows =
          (await appDatabase.loadCache<List<dynamic>>('stops') ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
      lineRows =
          (await appDatabase.loadCache<List<dynamic>>('lines') ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
      driverRows =
          (await appDatabase.loadCache<List<dynamic>>('drivers') ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
      lineGongs = Map<String, String>.from(
        await appDatabase.loadCache<Map<String, dynamic>>('line_gongs') ??
            const {},
      );
    }
    final byId = <String, Stop>{};
    for (final row in stopRows) {
      final types = row['type'];
      final stop = Stop(
        row['name'] as String? ?? 'Bez názvu',
        0,
        (row['lat'] as num?)?.toDouble(),
        (row['lng'] as num?)?.toDouble(),
        '${row['id']}',
        row['zone'] as String?,
        types is List && types.isNotEmpty ? '${types.first}' : null,
      );
      byId[stop.id!] = stop;
    }

    final loadedLines = <TransitLine>[];
    for (final row in lineRows) {
      final routeIds =
          (row['route'] as List? ?? const []).map((value) => '$value').toList();
      final routeStops = routeIds
          .map((id) => byId[id])
          .whereType<Stop>()
          .toList(growable: false);
      if (routeStops.isEmpty) continue;
      final reverseIds = (row['routeReverse'] as List? ?? const [])
          .map((value) => '$value')
          .toList();
      final reverseStops = reverseIds
          .map((id) => byId[id])
          .whereType<Stop>()
          .toList(growable: false);
      loadedLines.add(
        TransitLine(
          row['name'] as String? ?? '?',
          routeStops.last.name,
          _parseColor(row['color'] as String?),
          routeStops,
          '${row['id']}',
          row['type'] as String?,
          row['carrier'] as String?,
          reverseStops,
        ),
      );
    }
    stops = byId.values.toList(growable: false);
    if (loadedLines.isNotEmpty) lines = loadedLines;
    drivers = driverRows
        .map(
          (row) => DriverInfo(
            id: '${row['id']}',
            name: row['name'] as String? ?? 'Neznámý řidič',
            pin: '${row['pin'] ?? ''}',
            phone: row['phone'] as String?,
          ),
        )
        .toList(growable: false);
    loadedFromServer = true;
    notifyListeners();
  }

  static Color _parseColor(String? value) {
    final clean = (value ?? '').replaceFirst('#', '');
    final parsed = int.tryParse(clean, radix: 16);
    return parsed == null
        ? const Color(0xFF1565C0)
        : Color(0xFF000000 | parsed);
  }
}

class ActiveTripController extends ChangeNotifier {
  TransitLine line = lines.first;
  int stopIndex = 0;
  int startStopIndex = 0;
  int endStopIndex = lines.first.stops.length - 1;
  bool running = false;
  String direction = 'forward';
  int delayMinutes = 0;
  String occupancy = 'low';
  bool stopRequested = false;
  String? alertText;
  bool _applyingRemoteState = false;
  DriverInfo? driver;

  List<Stop> get routeStops =>
      direction == 'reverse' && line.reverseStops.isNotEmpty
          ? line.reverseStops
          : line.stops;
  Stop get current => routeStops[stopIndex];
  Stop? get next =>
      stopIndex + 1 <= endStopIndex && stopIndex + 1 < routeStops.length
          ? routeStops[stopIndex + 1]
          : null;

  Future<void> restore() async {
    final saved = await appDatabase.loadActiveTrip();
    if (saved == null) return;
    final lineNumber = saved['line_number'] as String?;
    line = lines.firstWhere(
      (item) => item.number == lineNumber,
      orElse: () => lines.first,
    );
    final savedIndex = saved['stop_index'] as int? ?? 0;
    stopIndex = savedIndex.clamp(0, line.stops.length - 1);
    startStopIndex = 0;
    endStopIndex = line.stops.length - 1;
    running = saved['running'] == 1;
  }

  void connectServer() {
    serverSync.watchTrip(({
      required lineNumber,
      required stopIndex,
      required startStopIndex,
      required endStopIndex,
      required running,
      required direction,
      required delayMinutes,
      required occupancy,
      required stopRequested,
      String? alertText,
      String? driverId,
    }) {
      final remoteLine = lines.firstWhere(
        (item) => item.number == lineNumber,
        orElse: () => line,
      );
      _applyingRemoteState = true;
      line = remoteLine;
      this.direction = direction;
      final routeLength = routeStops.length;
      this.stopIndex = stopIndex.clamp(0, routeLength - 1);
      this.startStopIndex = startStopIndex.clamp(0, routeLength - 1);
      this.endStopIndex = endStopIndex <= 0
          ? routeLength - 1
          : endStopIndex.clamp(this.startStopIndex, routeLength - 1);
      this.running = running;
      this.delayMinutes = delayMinutes;
      this.occupancy = occupancy;
      this.stopRequested = stopRequested;
      this.alertText = alertText;
      driver = null;
      for (final item in transitData.drivers) {
        if (item.id == driverId) driver = item;
      }
      notifyListeners();
      appDatabase.saveActiveTrip(
        lineNumber: line.number,
        stopIndex: this.stopIndex,
        running: this.running,
      );
      _applyingRemoteState = false;
    });
  }

  void update(
    TransitLine newLine,
    int newStopIndex,
    bool isRunning, {
    int? startStopIndex,
    int? endStopIndex,
    String? direction,
    int? delayMinutes,
    String? occupancy,
    bool? stopRequested,
    String? alertText,
  }) {
    line = newLine;
    stopIndex = newStopIndex;
    this.startStopIndex = startStopIndex ?? this.startStopIndex;
    this.endStopIndex = endStopIndex ?? this.endStopIndex;
    this.direction = direction ?? this.direction;
    this.delayMinutes = delayMinutes ?? this.delayMinutes;
    this.occupancy = occupancy ?? this.occupancy;
    this.stopRequested = stopRequested ?? this.stopRequested;
    this.alertText = alertText;
    running = isRunning;
    notifyListeners();
    appDatabase.saveActiveTrip(
      lineNumber: line.number,
      stopIndex: stopIndex,
      running: running,
    );
    if (!_applyingRemoteState) {
      serverSync.publishTrip(
        lineNumber: line.number,
        stopIndex: stopIndex,
        startStopIndex: this.startStopIndex,
        endStopIndex: this.endStopIndex,
        running: running,
        direction: this.direction,
        delayMinutes: this.delayMinutes,
        occupancy: this.occupancy,
        stopRequested: this.stopRequested,
        alertText: this.alertText,
        driverId: driver?.id,
      );
    }
  }

  void selectDriver(DriverInfo selectedDriver) {
    driver = selectedDriver;
    notifyListeners();
  }
}

class MikylovApp extends StatelessWidget {
  const MikylovApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MHD Mikylov',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005BBB),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ModeSelectionScreen(),
      routes: {
        '/driver': (_) => const DriverLoginScreen(),
        '/passenger': (_) => const PassengerScreen(),
        // Skrytá systémová trasa. Otevírá ji integrace vozidla nebo Nastoupit.
        '/onboard': (_) => const OnboardScreen(),
      },
    );
  }
}

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(title: const Text('MHD MIKYLOV')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              const Text(
                'Vyberte režim',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Palubní obrazovka se v autě spouští automaticky.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 28),
              _ModeCard(
                icon: Icons.badge_outlined,
                title: 'Řidič',
                subtitle: 'Výběr spoje, GPS, zastávky a hlášení',
                onTap: () => Navigator.pushNamed(context, '/driver'),
              ),
              const SizedBox(height: 16),
              _ModeCard(
                icon: Icons.directions_bus_outlined,
                title: 'Cestující',
                subtitle: 'Odjezdy, vyhledání spojení a Nastoupit',
                onTap: () => Navigator.pushNamed(context, '/passenger'),
              ),
              const SizedBox(height: 16),
              _ModeCard(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Administrátor',
                subtitle: 'Správa systému a automatický import dopravních dat',
                onTap: () => _openAdmin(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAdmin(BuildContext context) async {
    final password = TextEditingController();
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Přihlášení administrátora'),
        content: TextField(
          controller: password,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Heslo'),
          onSubmitted: (_) =>
              Navigator.pop(dialogContext, password.text == 'Mikolasek080523'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              password.text == 'Mikolasek080523',
            ),
            child: const Text('Přihlásit'),
          ),
        ],
      ),
    );
    password.dispose();
    if (!context.mounted) return;
    if (allowed == true) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      );
    } else if (allowed == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nesprávné administrátorské heslo.')),
      );
    }
  }
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _importer = GtfsImporter();
  final Map<String, GtfsImportResult> _results = {};
  String? _importing;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedImports();
  }

  Future<void> _loadSavedImports() async {
    final saved = await appDatabase.loadGtfsImports();
    if (!mounted) return;
    setState(() {
      for (final row in saved) {
        final url = row['source_url']! as String;
        final source = gtfsSources.firstWhere(
          (item) => item.url == url,
          orElse: () => GtfsSource(
            name: row['source_name']! as String,
            city: row['city']! as String,
            url: url,
          ),
        );
        _results[url] = GtfsImportResult(
          source: source,
          stopCount: row['stop_count']! as int,
          stationCount: row['station_count']! as int,
          routeCount: row['route_count']! as int,
        );
      }
    });
  }

  Future<void> _refreshTransit() async {
    setState(() => _error = null);
    try {
      await transitData.loadFromServer();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _editStop([Stop? stop]) async {
    final name = TextEditingController(text: stop?.name ?? '');
    final latitude = TextEditingController(
      text: stop?.latitude?.toString() ?? '',
    );
    final longitude = TextEditingController(
      text: stop?.longitude?.toString() ?? '',
    );
    final zone = TextEditingController(text: stop?.zone ?? 'P');
    final type = TextEditingController(text: stop?.type ?? 'bus');
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(stop == null ? 'Přidat zastávku' : 'Upravit zastávku'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Název'),
              ),
              TextField(
                controller: latitude,
                decoration: const InputDecoration(labelText: 'Zeměpisná šířka'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: longitude,
                decoration: const InputDecoration(labelText: 'Zeměpisná délka'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: zone,
                decoration: const InputDecoration(labelText: 'Pásmo'),
              ),
              TextField(
                controller: type,
                decoration: const InputDecoration(
                  labelText: 'Typ (bus, tram, metro...)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Uložit'),
          ),
        ],
      ),
    );
    if (save == true && name.text.trim().isNotEmpty) {
      final data = <String, dynamic>{
        if (stop?.id != null) 'id': stop!.id,
        'name': name.text.trim(),
        'lat': double.tryParse(latitude.text.replaceAll(',', '.')),
        'lng': double.tryParse(longitude.text.replaceAll(',', '.')),
        'zone': zone.text.trim(),
        'type': [type.text.trim().isEmpty ? 'bus' : type.text.trim()],
        'is_terminal': false,
      };
      try {
        await serverSync.saveStop(data);
        await _refreshTransit();
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
    }
    name.dispose();
    latitude.dispose();
    longitude.dispose();
    zone.dispose();
    type.dispose();
  }

  Future<void> _deleteStop(Stop stop) async {
    if (stop.id == null) return;
    try {
      await serverSync.deleteStop(stop.id!);
      await _refreshTransit();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _editLine([TransitLine? line]) async {
    final number = TextEditingController(text: line?.number ?? '');
    final carrier = TextEditingController(
      text: line?.carrier ?? 'Dopravní podnik Mikylov',
    );
    final color = TextEditingController(
      text:
          '#${line?.color.toARGB32().toRadixString(16).substring(2) ?? '1565c0'}',
    );
    String? firstStopId = line != null && line.stops.isNotEmpty
        ? line.stops.first.id
        : (transitData.stops.isEmpty ? null : transitData.stops.first.id);
    String? lastStopId = line != null && line.stops.isNotEmpty
        ? line.stops.last.id
        : (transitData.stops.isEmpty ? null : transitData.stops.last.id);
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(line == null ? 'Přidat linku' : 'Upravit linku'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: number,
                  decoration: const InputDecoration(
                    labelText: 'Číslo / označení linky',
                  ),
                ),
                TextField(
                  controller: carrier,
                  decoration: const InputDecoration(labelText: 'Dopravce'),
                ),
                TextField(
                  controller: color,
                  decoration: const InputDecoration(labelText: 'Barva #RRGGBB'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: firstStopId,
                  decoration: const InputDecoration(
                    labelText: 'Výchozí zastávka',
                  ),
                  items: transitData.stops
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => firstStopId = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: lastStopId,
                  decoration: const InputDecoration(
                    labelText: 'Konečná zastávka',
                  ),
                  items: transitData.stops
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => lastStopId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Zrušit'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Uložit'),
            ),
          ],
        ),
      ),
    );
    if (save == true &&
        number.text.trim().isNotEmpty &&
        firstStopId != null &&
        lastStopId != null) {
      final route = line == null
          ? [firstStopId, lastStopId]
          : line.stops.map((item) => item.id).whereType<String>().toList();
      final data = <String, dynamic>{
        if (line?.id != null) 'id': line!.id,
        'name': number.text.trim(),
        'type': line?.type ?? 'bus',
        'carrier': carrier.text.trim(),
        'color': color.text.trim(),
        'route': route,
        'routeReverse': route.reversed.toList(),
      };
      try {
        await serverSync.saveLine(data);
        await _refreshTransit();
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
    }
    number.dispose();
    carrier.dispose();
    color.dispose();
  }

  Future<void> _deleteLine(TransitLine line) async {
    if (line.id == null) return;
    try {
      await serverSync.deleteLine(line.id!);
      await _refreshTransit();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _editDriver([DriverInfo? driver]) async {
    final name = TextEditingController(text: driver?.name ?? '');
    final phone = TextEditingController(text: driver?.phone ?? '');
    final pin = TextEditingController(text: driver?.pin ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(driver == null ? 'Přidat řidiče' : 'Upravit řidiče'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Jméno a příjmení'),
            ),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefon'),
            ),
            TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Uložit'),
          ),
        ],
      ),
    );
    if (save == true && name.text.trim().isNotEmpty && pin.text.isNotEmpty) {
      try {
        await serverSync.saveDriver({
          if (driver != null) 'id': driver.id,
          'name': name.text.trim(),
          'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
          'pin': pin.text,
        });
        await _refreshTransit();
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
    }
    name.dispose();
    phone.dispose();
    pin.dispose();
  }

  Future<void> _deleteDriver(DriverInfo driver) async {
    try {
      await serverSync.deleteDriver(driver.id);
      await _refreshTransit();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _editGong(TransitLine line) async {
    if (line.id == null) return;
    final url = TextEditingController(
      text: transitData.lineGongs[line.id] ?? '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Gong linky ${line.number}'),
        content: TextField(
          controller: url,
          decoration: const InputDecoration(labelText: 'Veřejná URL MP3 gongu'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Uložit'),
          ),
        ],
      ),
    );
    if (save == true && url.text.trim().isNotEmpty) {
      try {
        await serverSync.saveLineGong(line.id!, url.text.trim());
        await _refreshTransit();
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
    }
    url.dispose();
  }

  Future<void> _import(GtfsSource source) async {
    setState(() {
      _importing = source.url;
      _error = null;
    });
    try {
      final result = await _importer.import(source);
      if (source.url.contains('data.pid.cz')) {
        await serverSync.importPragueData(
          stops: result.stops,
          routes: result.routes,
        );
      }
      await appDatabase.saveGtfsImport(
        sourceUrl: source.url,
        sourceName: source.name,
        city: source.city,
        stopCount: result.stopCount,
        stationCount: result.stationCount,
        routeCount: result.routeCount,
      );
      if (!mounted) return;
      setState(() => _results[source.url] = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _importing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administrace MHD Mikylov')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Linky v databázi',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: _refreshTransit,
                icon: const Icon(Icons.refresh),
              ),
              FilledButton.icon(
                onPressed:
                    transitData.stops.length >= 2 ? () => _editLine() : null,
                icon: const Icon(Icons.add),
                label: const Text('Linka'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...transitData.lines.map(
            (line) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: line.color,
                  child: Text(line.number),
                ),
                title: Text('${line.number} → ${line.destination}'),
                subtitle: Text(
                  '${line.stops.length} zastávek • ${line.carrier ?? 'bez dopravce'}',
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      onPressed: () => _editGong(line),
                      icon: const Icon(Icons.audiotrack_outlined),
                    ),
                    IconButton(
                      onPressed: () => _editLine(line),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () => _deleteLine(line),
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.redAccent,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Zastávky v databázi',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _editStop(),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Zastávka'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...transitData.stops.map(
            (stop) => Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(stop.name),
                subtitle: Text(
                  '${stop.type ?? 'zastávka'} • pásmo ${stop.zone ?? '-'}',
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      onPressed: () => _editStop(stop),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () => _deleteStop(stop),
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.redAccent,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Řidiči a PINy',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _editDriver(),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Řidič'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...transitData.drivers.map(
            (driver) => Card(
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(driver.name),
                subtitle: Text(
                  driver.phone?.isNotEmpty == true
                      ? '${driver.phone} • PIN nastaven'
                      : 'Bez telefonu • PIN nastaven',
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      onPressed: () => _editDriver(driver),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () => _deleteDriver(driver),
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.redAccent,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 42),
          const Text(
            'Import veřejných dopravních dat',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'GTFS se automaticky stáhne z oficiálního zdroje a načte linky, '
            'zastávky, stanice a jízdní řády.',
            style: TextStyle(color: Colors.white60),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          const SizedBox(height: 18),
          ...gtfsSources.map((source) {
            final result = _results[source.url];
            final loading = _importing == source.url;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      source.city,
                      style: const TextStyle(color: Colors.white60),
                    ),
                    if (result != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Importováno: ${result.stopCount} zastávek a bodů, '
                        '${result.stationCount} stanic, ${result.routeCount} linek.',
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed:
                          _importing == null ? () => _import(source) : null,
                      icon: loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_outlined),
                      label: Text(
                        result == null
                            ? 'STÁHNOUT A IMPORTOVAT'
                            : 'AKTUALIZOVAT',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minVerticalPadding: 24,
        leading: Icon(icon, size: 42, color: Colors.lightBlueAccent),
        title: Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class PassengerScreen extends StatelessWidget {
  const PassengerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _NearbyDeparturesScreen();
  }
}

class _NearbyDeparturesScreen extends StatefulWidget {
  const _NearbyDeparturesScreen();

  @override
  State<_NearbyDeparturesScreen> createState() =>
      _NearbyDeparturesScreenState();
}

class _NearbyDeparturesScreenState extends State<_NearbyDeparturesScreen> {
  Stop? _nearestStop;
  double? _distanceMetres;
  String? _locationError;
  String? _departuresError;
  List<DepartureInfo> _departures = const [];
  Set<String> _favoriteStopIds = {};
  List<Map<String, Object?>> _history = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPassengerData();
    _findNearestStop();
  }

  Future<void> _loadPassengerData() async {
    final favorites =
        await appDatabase.loadSetting<List<dynamic>>('favorite_stops') ??
            const [];
    final history = await appDatabase.loadTripHistory('passenger');
    if (!mounted) return;
    setState(() {
      _favoriteStopIds = favorites.map((value) => '$value').toSet();
      _history = history;
    });
  }

  Future<void> _toggleFavorite() async {
    final id = _nearestStop?.id;
    if (id == null) return;
    setState(() {
      if (!_favoriteStopIds.add(id)) _favoriteStopIds.remove(id);
    });
    await appDatabase.saveSetting('favorite_stops', _favoriteStopIds.toList());
  }

  Future<void> _boardCurrentTrip() async {
    await appDatabase.addTripHistory(
      role: 'passenger',
      lineNumber: activeTrip.line.number,
      originName: _nearestStop?.name ?? activeTrip.current.name,
      destinationName: activeTrip.routeStops[activeTrip.endStopIndex].name,
      startedAt: DateTime.now(),
      delayMinutes: activeTrip.delayMinutes,
      direction: activeTrip.direction,
    );
    if (!mounted) return;
    Navigator.pushNamed(context, '/onboard');
  }

  Future<void> _findNearestStop() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Zapněte polohové služby.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Povolte aplikaci přístup k poloze.');
      }

      final position = await Geolocator.getCurrentPosition();
      final uniqueStops = <String, Stop>{};
      for (final line in lines) {
        for (final stop in line.stops) {
          if (stop.latitude != null &&
              stop.longitude != null &&
              (stop.latitude != 0 || stop.longitude != 0)) {
            uniqueStops[stop.id ?? stop.name] = stop;
          }
        }
      }
      Stop? nearest;
      var nearestDistance = double.infinity;
      for (final stop in uniqueStops.values) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          stop.latitude!,
          stop.longitude!,
        );
        if (distance < nearestDistance) {
          nearest = stop;
          nearestDistance = distance;
        }
      }
      if (nearest == null) throw Exception('V databázi nejsou zastávky s GPS.');
      final departures = await _loadDepartures(nearest);
      if (!mounted) return;
      setState(() {
        _nearestStop = nearest;
        _distanceMetres = nearestDistance;
        _departures = departures;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationError = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<List<DepartureInfo>> _loadDepartures(Stop stop) async {
    try {
      final rows = await serverSync.fetchDepartures();
      await appDatabase.saveCache('departures', rows);
      return _mapDepartures(rows, stop);
    } catch (error) {
      final cached =
          await appDatabase.loadCache<List<dynamic>>('departures') ?? const [];
      final rows = cached
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (rows.isNotEmpty) {
        _departuresError = 'Offline režim – zobrazuji naposledy uložená data.';
        return _mapDepartures(rows, stop);
      }
      _departuresError =
          'Odjezdy se nepodařilo načíst z databáze: ${error.toString()}';
      return const [];
    }
  }

  List<DepartureInfo> _mapDepartures(
    List<Map<String, dynamic>> rows,
    Stop stop,
  ) {
    final departures = <DepartureInfo>[];
    for (final row in rows) {
      final lineId = '${row['line_id'] ?? ''}';
      TransitLine? line;
      for (final candidate in lines) {
        if (candidate.id == lineId) line = candidate;
      }
      if (line == null) continue;

      final reversed = row['is_reversed'] == true;
      final route = reversed ? line.stops.reversed.toList() : line.stops;
      final stopIndex = route.indexWhere(
        (item) => item.id == stop.id || item.name == stop.name,
      );
      if (stopIndex < 0) continue;
      final startIndex = (row['start_stop_index'] as num?)?.toInt() ?? 0;
      final endIndex =
          (row['end_stop_index'] as num?)?.toInt() ?? route.length - 1;
      if (stopIndex < startIndex || stopIndex > endIndex) continue;

      final rawTime = row['_source'] == 'scheduled_departures'
          ? row['departure_time']
          : row['start_time'];
      final departureTime = DateTime.tryParse('$rawTime')?.toLocal();
      if (departureTime == null) continue;
      departures.add(
        DepartureInfo(
          line: line,
          departureTime: departureTime,
          destination: route[endIndex.clamp(0, route.length - 1)].name,
          status: '${row['status'] ?? 'scheduled'}',
        ),
      );
    }
    departures.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    return departures;
  }

  String _departureLabel(DepartureInfo departure) {
    if (departure.status == 'active') return 'v provozu';
    final time = departure.departureTime;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Odjezdy v okolí')),
      body: AnimatedBuilder(
        animation: activeTrip,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_locationError != null) ...[
                Text(
                  _locationError!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                OutlinedButton.icon(
                  onPressed: _findNearestStop,
                  icon: const Icon(Icons.my_location),
                  label: const Text('ZKUSIT ZNOVU'),
                ),
              ],
              if (_nearestStop != null) ...[
                const Text(
                  'Nejbližší zastávka',
                  style: TextStyle(color: Colors.white60),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _nearestStop!.name,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Oblíbená zastávka',
                      onPressed: _toggleFavorite,
                      icon: Icon(
                        _favoriteStopIds.contains(_nearestStop!.id)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                Text('${math.max(0, _distanceMetres!.round())} m od vás'),
                const SizedBox(height: 20),
                const Text(
                  'Odjezdy z této zastávky',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                if (_favoriteStopIds.contains(_nearestStop!.id) &&
                    _departures.any(
                      (departure) =>
                          departure.departureTime
                              .difference(DateTime.now())
                              .inMinutes <=
                          10,
                    ))
                  const Card(
                    color: Color(0xFF174A2C),
                    child: ListTile(
                      leading: Icon(Icons.notifications_active),
                      title: Text('Blíží se odjezd z oblíbené zastávky'),
                      subtitle: Text('Nejbližší spoj odjíždí do 10 minut.'),
                    ),
                  ),
                if (_departuresError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _departuresError!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                if (!_loading &&
                    _departures.isEmpty &&
                    _departuresError == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: Text(
                      'Pro tuto zastávku nejsou v databázi žádné spoje.',
                    ),
                  ),
                ..._departures.map(
                  (departure) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: departure.line.color,
                        child: Text(departure.line.number),
                      ),
                      title: Text(departure.destination),
                      subtitle: Text(
                        activeTrip.running &&
                                activeTrip.line.id == departure.line.id &&
                                activeTrip.delayMinutes != 0
                            ? 'Zpoždění ${activeTrip.delayMinutes} min'
                            : 'Data z databáze',
                      ),
                      trailing: Text(
                        _departureLabel(departure),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (activeTrip.driver != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(activeTrip.driver!.name),
                    subtitle: Text(
                      activeTrip.driver!.phone?.isNotEmpty == true
                          ? 'Řidič spoje • ${activeTrip.driver!.phone}'
                          : 'Řidič spoje',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: activeTrip.running ? _boardCurrentTrip : null,
                icon: const Icon(Icons.login),
                label: Text('NASTOUPIT DO LINKY ${activeTrip.line.number}'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(58),
                ),
              ),
              if (!activeTrip.running)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Nastoupit se aktivuje po zahájení spoje řidičem.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 18),
                ExpansionTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Historie cest'),
                  children: _history
                      .map(
                        (trip) => ListTile(
                          title: Text('Linka ${trip['line_number']}'),
                          subtitle: Text(
                            '${trip['origin_name']} → ${trip['destination_name']}',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class OnboardScreen extends StatelessWidget {
  const OnboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B12),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: activeTrip,
          builder: (context, _) {
            final trip = activeTrip;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 82,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: trip.line.color,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          trip.line.number,
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          trip.routeStops[trip.endStopIndex].name,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  if (trip.alertText?.isNotEmpty == true)
                    Card(
                      color: Colors.red.shade900,
                      child: ListTile(
                        leading: const Icon(Icons.warning_amber),
                        title: Text(trip.alertText!),
                      ),
                    ),
                  _StopCard(
                    label: 'AKTUÁLNÍ ZASTÁVKA',
                    stop: trip.current.name,
                  ),
                  const SizedBox(height: 12),
                  _StopCard(
                    label: 'NÁSLEDUJE',
                    stop: trip.next?.name ?? 'Konečná zastávka',
                    accent: true,
                  ),
                  const SizedBox(height: 24),
                  LinearProgressIndicator(
                    value: (trip.stopIndex - trip.startStopIndex) /
                        math.max(1, trip.endStopIndex - trip.startStopIndex),
                    minHeight: 10,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Zpoždění: ${trip.delayMinutes} min • Obsazenost: ${_occupancyLabel(trip.occupancy)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: trip.next != null && !trip.stopRequested
                        ? () => serverSync.requestStop(true)
                        : null,
                    icon: const Icon(Icons.touch_app),
                    label: Text(
                      trip.stopRequested
                          ? 'ZASTÁVKA NA ZNAMENÍ POŽADOVÁNA'
                          : 'ZASTÁVKA NA ZNAMENÍ',
                    ),
                  ),
                  if (trip.driver != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Řidič: ${trip.driver!.name}${trip.driver!.phone?.isNotEmpty == true ? ' • ${trip.driver!.phone}' : ''}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: trip.endStopIndex - trip.startStopIndex + 1,
                      itemBuilder: (_, offset) {
                        final index = trip.startStopIndex + offset;
                        return ListTile(
                          leading: Icon(
                            index == trip.stopIndex
                                ? Icons.radio_button_checked
                                : Icons.circle_outlined,
                          ),
                          title: Text(trip.routeStops[index].name),
                          enabled: index >= trip.stopIndex,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _occupancyLabel(String value) {
  switch (value) {
    case 'medium':
      return 'střední';
    case 'full':
      return 'plno';
    default:
      return 'volno';
  }
}

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  DriverInfo? _driver;
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _login() {
    if (_driver == null || _pin.text != _driver!.pin) {
      setState(() => _error = 'Nesprávný řidič nebo PIN.');
      return;
    }
    activeTrip.selectDriver(_driver!);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Přihlášení řidiče')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<DriverInfo>(
            decoration: const InputDecoration(
              labelText: 'Řidič',
              border: OutlineInputBorder(),
            ),
            items: transitData.drivers
                .map(
                  (driver) =>
                      DropdownMenuItem(value: driver, child: Text(driver.name)),
                )
                .toList(),
            onChanged: (value) => setState(() => _driver = value),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'PIN',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _login, child: const Text('PŘIHLÁSIT')),
        ],
      ),
    );
  }
}

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _gongPlayer = AudioPlayer();
  TransitLine? _line;
  int _stopIndex = 0;
  int _startStopIndex = 0;
  int _endStopIndex = 0;
  bool _running = false;
  String _direction = 'forward';
  int _delayMinutes = 0;
  String _occupancy = 'low';
  String? _alertText;
  DateTime? _tripStartedAt;
  StreamSubscription<Position>? _positionSubscription;
  int? _lastAutomaticArrival;
  int? _lastNextAnnouncement;
  List<Map<String, Object?>> _history = const [];

  List<Stop> get _route =>
      _direction == 'reverse' && _line?.reverseStops.isNotEmpty == true
          ? _line!.reverseStops
          : _line!.stops;
  Stop get _current => _route[_stopIndex];
  Stop? get _next =>
      _stopIndex + 1 <= _endStopIndex ? _route[_stopIndex + 1] : null;

  @override
  void initState() {
    super.initState();
    _configureAnnouncements();
    _loadDriverHistory();
  }

  Future<void> _loadDriverHistory() async {
    final history = await appDatabase.loadTripHistory('driver');
    if (mounted) setState(() => _history = history);
  }

  Future<void> _startGpsAutomation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(_handlePosition);
  }

  Future<void> _handlePosition(Position position) async {
    if (!_running || _line == null) return;
    final next = _next;
    if (next?.latitude != null && next?.longitude != null) {
      final nextDistance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        next!.latitude!,
        next.longitude!,
      );
      final nextIndex = _stopIndex + 1;
      if (nextDistance <= 65 && _lastAutomaticArrival != nextIndex) {
        _lastAutomaticArrival = nextIndex;
        if (!mounted) return;
        setState(() => _stopIndex = nextIndex);
        activeTrip.update(
          _line!,
          _stopIndex,
          true,
          startStopIndex: _startStopIndex,
          endStopIndex: _endStopIndex,
          direction: _direction,
          delayMinutes: _delayMinutes,
          occupancy: _occupancy,
          stopRequested: false,
          alertText: _alertText,
        );
        await _announceArrival();
        return;
      }
    }

    final current = _current;
    if (current.latitude != null &&
        current.longitude != null &&
        _next != null) {
      final currentDistance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        current.latitude!,
        current.longitude!,
      );
      if (currentDistance >= 100 && _lastNextAnnouncement != _stopIndex + 1) {
        _lastNextAnnouncement = _stopIndex + 1;
        await _speak('Příští zastávka ${_next!.name}.');
      }
    }
  }

  Future<void> _configureAnnouncements() async {
    await _tts.setLanguage('cs-CZ');
    await _tts.setSpeechRate(0.43);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ],
          IosTextToSpeechAudioMode.spokenAudio);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      await _tts.setAudioAttributesForNavigation();
    }
    final audioSession = await AudioSession.instance;
    await audioSession.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers |
                AVAudioSessionCategoryOptions.duckOthers |
                AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.assistanceNavigationGuidance,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ),
    );
    await _selectBestCzechSystemVoice();
  }

  Future<void> _selectBestCzechSystemVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return;
      final czechVoices = voices.whereType<Map>().where((voice) {
        final locale =
            '${voice['locale'] ?? ''}'.replaceAll('_', '-').toLowerCase();
        return locale == 'cs-cz' || locale.startsWith('cs-');
      }).toList();
      if (czechVoices.isEmpty) return;

      int voiceScore(Map voice) {
        final description = voice.values.join(' ').toLowerCase();
        var score = 0;
        if (description.contains('natural')) score += 100;
        if (description.contains('premium')) score += 90;
        if (description.contains('enhanced')) score += 80;
        if (description.contains('network')) score += 60;
        if (description.contains('google')) score += 50;
        if (description.contains('zuzana') || description.contains('iveta')) {
          score += 40;
        }
        if (description.contains('compact')) score -= 20;
        if (description.contains('espeak') || description.contains('robot')) {
          score -= 100;
        }
        return score;
      }

      czechVoices.sort((a, b) => voiceScore(b).compareTo(voiceScore(a)));
      final selected = czechVoices.first;
      final name = selected['name'];
      final locale = selected['locale'];
      if (name != null && locale != null) {
        await _tts.setVoice({'name': '$name', 'locale': '$locale'});
      }
    } catch (_) {
      // Když přístroj nenabízí seznam hlasů, použije se výchozí český hlas OS.
    }
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _announceArrival() async {
    final lineId = _line?.id;
    final gongUrl = lineId == null ? null : transitData.lineGongs[lineId];
    if (gongUrl != null && gongUrl.isNotEmpty) {
      try {
        await _gongPlayer.setUrl(gongUrl);
        await _gongPlayer.play();
      } catch (_) {
        // Hlášení názvu zastávky pokračuje i při nedostupném gongu.
      }
    }
    final isSelectedTerminal = _stopIndex == _endStopIndex;
    final isShortenedTrip =
        isSelectedTerminal && _endStopIndex < _route.length - 1;
    if (isShortenedTrip) {
      await _speak(
        '${_current.name}. Upozorňujeme cestující, že tento spoj končí jízdu v zastávce ${_current.name}.',
      );
    } else if (isSelectedTerminal) {
      await _speak(
        '${_current.name}. Konečná zastávka, prosíme, vystupte.',
      );
    } else {
      await _speak('${_current.name}.');
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _gongPlayer.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _depart() async {
    if (_next == null) {
      setState(() => _running = false);
      _positionSubscription?.cancel();
      activeTrip.update(
        _line!,
        _stopIndex,
        false,
        startStopIndex: _startStopIndex,
        endStopIndex: _endStopIndex,
        direction: _direction,
        delayMinutes: _delayMinutes,
        occupancy: _occupancy,
        stopRequested: false,
        alertText: _alertText,
      );
      if (_tripStartedAt != null) {
        await appDatabase.addTripHistory(
          role: 'driver',
          lineNumber: _line!.number,
          originName: _route[_startStopIndex].name,
          destinationName: _route[_endStopIndex].name,
          startedAt: _tripStartedAt!,
          endedAt: DateTime.now(),
          delayMinutes: _delayMinutes,
          direction: _direction,
        );
        await _loadDriverHistory();
      }
      return;
    }
    final nextName = _next!.name;
    setState(() {
      _stopIndex++;
      _running = true;
    });
    activeTrip.update(
      _line!,
      _stopIndex,
      _running,
      startStopIndex: _startStopIndex,
      endStopIndex: _endStopIndex,
      direction: _direction,
      delayMinutes: _delayMinutes,
      occupancy: _occupancy,
      stopRequested: false,
      alertText: _alertText,
    );
    await _speak('Příští zastávka $nextName.');
  }

  void _selectLine(TransitLine? line) {
    if (line == null) return;
    setState(() {
      _line = line;
      _direction = 'forward';
      _stopIndex = 0;
      _startStopIndex = 0;
      _endStopIndex = _route.length - 1;
      _running = false;
    });
  }

  void _selectStart(int? index) {
    if (index == null) return;
    setState(() {
      _startStopIndex = index;
      _stopIndex = index;
      if (_endStopIndex < index) _endStopIndex = _route.length - 1;
    });
  }

  void _selectDirection(String? value) {
    if (value == null || _running) return;
    setState(() {
      _direction = value;
      _startStopIndex = 0;
      _stopIndex = 0;
      _endStopIndex = _route.length - 1;
    });
  }

  void _syncOperationalState() {
    if (!_running || _line == null) return;
    activeTrip.update(
      _line!,
      _stopIndex,
      true,
      startStopIndex: _startStopIndex,
      endStopIndex: _endStopIndex,
      direction: _direction,
      delayMinutes: _delayMinutes,
      occupancy: _occupancy,
      stopRequested: activeTrip.stopRequested,
      alertText: _alertText,
    );
  }

  Future<void> _announceServiceAlert(String? text) async {
    setState(() => _alertText = text);
    _syncOperationalState();
    if (text != null) await _speak(text);
  }

  void _startTrip() {
    final line = _line;
    if (line == null) return;
    setState(() {
      _stopIndex = _startStopIndex;
      _running = true;
      _tripStartedAt = DateTime.now();
    });
    activeTrip.update(
      line,
      _stopIndex,
      true,
      startStopIndex: _startStopIndex,
      endStopIndex: _endStopIndex,
      direction: _direction,
      delayMinutes: _delayMinutes,
      occupancy: _occupancy,
      stopRequested: false,
      alertText: _alertText,
    );
    _startGpsAutomation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        title: const Text('MHD MIKYLOV • PALUBNÍ REŽIM'),
        backgroundColor: const Color(0xFF0C1D32),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TransitLine>(
                    decoration: const InputDecoration(
                      labelText: 'Nejprve vyberte linku',
                      border: OutlineInputBorder(),
                    ),
                    items: lines
                        .map(
                          (line) => DropdownMenuItem(
                            value: line,
                            child: Text(
                              '${line.number}  →  ${line.destination}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _selectLine,
                  ),
                ),
                if (_line != null) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 74,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _line!.color,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _line!.number,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_line == null)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text(
                  'Po přihlášení není spuštěný žádný spoj. Vyberte linku a úsek trasy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.white70),
                ),
              )
            else ...[
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _direction,
                decoration: const InputDecoration(
                  labelText: 'Směr linky',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'forward', child: Text('Tam')),
                  DropdownMenuItem(value: 'reverse', child: Text('Zpět')),
                ],
                onChanged: _running ? null : _selectDirection,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _startStopIndex,
                      decoration: const InputDecoration(
                        labelText: 'Začátek trasy',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(
                        _route.length,
                        (index) => DropdownMenuItem(
                          value: index,
                          child: Text(_route[index].name),
                        ),
                      ),
                      onChanged: _running ? null : _selectStart,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('end-${_line!.id}-$_startStopIndex'),
                      initialValue: _endStopIndex,
                      decoration: const InputDecoration(
                        labelText: 'Konec trasy',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var index = _startStopIndex;
                            index < _route.length;
                            index++)
                          DropdownMenuItem(
                            value: index,
                            child: Text(_route[index].name),
                          ),
                      ],
                      onChanged: _running
                          ? null
                          : (index) => setState(() => _endStopIndex = index!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!_running)
                FilledButton.icon(
                  onPressed: _startTrip,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('ZAHÁJIT SPOJ'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                    backgroundColor: Colors.green,
                  ),
                ),
              if (_running) ...[
                AnimatedBuilder(
                  animation: activeTrip,
                  builder: (context, _) => activeTrip.stopRequested
                      ? Card(
                          color: Colors.orange.shade900,
                          child: const ListTile(
                            leading: Icon(Icons.notifications_active),
                            title: Text('ZASTÁVKA NA ZNAMENÍ'),
                            subtitle: Text('Cestující požádal o zastavení.'),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 18),
                _StopCard(label: 'AKTUÁLNÍ ZASTÁVKA', stop: _current.name),
                const SizedBox(height: 12),
                _StopCard(
                  label: 'NÁSLEDUJE',
                  stop: _next?.name ?? 'Konečná zastávka',
                  accent: true,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _announceArrival,
                        icon: const Icon(Icons.volume_up),
                        label: const Text('PŘÍJEZD'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(64),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _depart,
                        icon: const Icon(Icons.directions_bus),
                        label: Text(_next == null ? 'UKONČIT' : 'ODJEZD'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF9A825),
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(64),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: (_stopIndex - _startStopIndex) /
                      math.max(1, _endStopIndex - _startStopIndex),
                  minHeight: 9,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Spoj je v provozu',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() => _delayMinutes--);
                        _syncOperationalState();
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Expanded(
                      child: Text(
                        'Zpoždění $_delayMinutes min',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() => _delayMinutes++);
                        _syncOperationalState();
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  initialValue: _occupancy,
                  decoration: const InputDecoration(
                    labelText: 'Obsazenost pro cestující',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Volno')),
                    DropdownMenuItem(
                      value: 'medium',
                      child: Text('Středně obsazeno'),
                    ),
                    DropdownMenuItem(value: 'full', child: Text('Plno')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _occupancy = value);
                    _syncOperationalState();
                  },
                ),
                const SizedBox(height: 14),
                ExpansionTile(
                  leading: const Icon(Icons.campaign),
                  title: const Text('Mimořádná hlášení'),
                  children: [
                    ListTile(
                      title: const Text('Výluka nebo změna trasy'),
                      onTap: () => _announceServiceAlert(
                        'Upozorňujeme cestující na mimořádnou změnu trasy. Sledujte prosím pokyny řidiče.',
                      ),
                    ),
                    ListTile(
                      title: const Text('Technická porucha'),
                      onTap: () => _announceServiceAlert(
                        'Upozorňujeme cestující, že z důvodu technické poruchy může dojít ke zdržení spoje.',
                      ),
                    ),
                    ListTile(
                      title: const Text('Uvolněte dveře'),
                      onTap: () => _announceServiceAlert(
                        'Prosíme cestující, aby uvolnili prostor dveří.',
                      ),
                    ),
                    if (_alertText != null)
                      ListTile(
                        title: const Text('Ukončit mimořádné hlášení'),
                        onTap: () => _announceServiceAlert(null),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              ...List.generate(_route.length, (index) {
                final stop = _route[index];
                final outside =
                    index < _startStopIndex || index > _endStopIndex;
                final passed = _running && index < _stopIndex;
                final active = index == _stopIndex;
                return ListTile(
                  leading: Icon(
                    active ? Icons.radio_button_checked : Icons.circle_outlined,
                    color: outside || passed
                        ? Colors.white30
                        : (active ? Colors.amber : Colors.white70),
                  ),
                  title: Text(stop.name),
                  trailing: Text('+${stop.minutes} min'),
                  textColor: outside || passed ? Colors.white38 : Colors.white,
                );
              }),
              if (_history.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Historie jízd řidiče'),
                  children: _history
                      .map(
                        (trip) => ListTile(
                          title: Text('Linka ${trip['line_number']}'),
                          subtitle: Text(
                            '${trip['origin_name']} → ${trip['destination_name']}',
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.label,
    required this.stop,
    this.accent = false,
  });
  final String label;
  final String stop;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent ? const Color(0xFF123B63) : const Color(0xFF0C1D32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent ? Colors.lightBlueAccent : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            stop,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
