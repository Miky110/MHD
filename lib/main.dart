import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mhd_mikylov/database.dart';
import 'package:mhd_mikylov/gtfs_importer.dart';
import 'package:mhd_mikylov/server_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appDatabase.initialize();
  await activeTrip.restore();
  await serverSync.initialize();
  activeTrip.connectServer();
  runApp(const MikylovApp());
}

final activeTrip = ActiveTripController();

class Stop {
  const Stop(this.name, this.minutes, [this.latitude, this.longitude]);
  final String name;
  final int minutes;
  final double? latitude;
  final double? longitude;
}

class TransitLine {
  const TransitLine(this.number, this.destination, this.color, this.stops);
  final String number;
  final String destination;
  final Color color;
  final List<Stop> stops;
}

const lines = <TransitLine>[
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

class ActiveTripController extends ChangeNotifier {
  TransitLine line = lines.first;
  int stopIndex = 0;
  bool running = false;
  bool _applyingRemoteState = false;

  Stop get current => line.stops[stopIndex];
  Stop? get next =>
      stopIndex + 1 < line.stops.length ? line.stops[stopIndex + 1] : null;

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
    running = saved['running'] == 1;
  }

  void connectServer() {
    serverSync.watchTrip(({
      required lineNumber,
      required stopIndex,
      required running,
    }) {
      final remoteLine = lines.firstWhere(
        (item) => item.number == lineNumber,
        orElse: () => line,
      );
      _applyingRemoteState = true;
      line = remoteLine;
      this.stopIndex = stopIndex.clamp(0, line.stops.length - 1);
      this.running = running;
      notifyListeners();
      appDatabase.saveActiveTrip(
        lineNumber: line.number,
        stopIndex: this.stopIndex,
        running: this.running,
      );
      _applyingRemoteState = false;
    });
  }

  void update(TransitLine newLine, int newStopIndex, bool isRunning) {
    line = newLine;
    stopIndex = newStopIndex;
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
        running: running,
      );
    }
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
        '/driver': (_) => const DriverScreen(),
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
          onSubmitted: (_) => Navigator.pop(
            dialogContext,
            password.text == 'Mikolasek080523',
          ),
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

  Future<void> _import(GtfsSource source) async {
    setState(() {
      _importing = source.url;
      _error = null;
    });
    try {
      final result = await _importer.import(source);
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
          const Text('Import veřejných dopravních dat',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'GTFS se automaticky stáhne z oficiálního zdroje a načte linky, '
            'zastávky, stanice a jízdní řády.',
            style: TextStyle(color: Colors.white60),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
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
                    Text(source.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(source.city,
                        style: const TextStyle(color: Colors.white60)),
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
                      label: Text(result == null
                          ? 'STÁHNOUT A IMPORTOVAT'
                          : 'AKTUALIZOVAT'),
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _findNearestStop();
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
          if (stop.latitude != null && stop.longitude != null) {
            uniqueStops[stop.name] = stop;
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
      if (!mounted) return;
      setState(() {
        _nearestStop = nearest;
        _distanceMetres = nearestDistance;
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

  List<(TransitLine, int)> get _departures {
    final stop = _nearestStop;
    if (stop == null) return [];
    final now = DateTime.now();
    final rows = <(TransitLine, int)>[];
    for (final line in lines) {
      final index = line.stops.indexWhere((item) => item.name == stop.name);
      if (index >= 0) {
        final nextQuarter = ((now.minute ~/ 15) + 1) * 15;
        rows.add((line, nextQuarter - now.minute + line.stops[index].minutes));
      }
    }
    rows.sort((a, b) => a.$2.compareTo(b.$2));
    return rows;
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
                Text(_locationError!,
                    style: const TextStyle(color: Colors.redAccent)),
                OutlinedButton.icon(
                  onPressed: _findNearestStop,
                  icon: const Icon(Icons.my_location),
                  label: const Text('ZKUSIT ZNOVU'),
                ),
              ],
              if (_nearestStop != null) ...[
                const Text('Nejbližší zastávka',
                    style: TextStyle(color: Colors.white60)),
                Text(_nearestStop!.name,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800)),
                Text('${math.max(0, _distanceMetres!.round())} m od vás'),
                const SizedBox(height: 20),
                const Text('Odjezdy z této zastávky',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ..._departures.map((departure) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: departure.$1.color,
                          child: Text(departure.$1.number),
                        ),
                        title: Text(departure.$1.destination),
                        trailing: Text('${departure.$2} min',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                    )),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: activeTrip.running
                    ? () => Navigator.pushNamed(context, '/onboard')
                    : null,
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
                          trip.line.destination,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
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
                    value: trip.stopIndex / (trip.line.stops.length - 1),
                    minHeight: 10,
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: trip.line.stops.length,
                      itemBuilder: (_, index) => ListTile(
                        leading: Icon(
                          index == trip.stopIndex
                              ? Icons.radio_button_checked
                              : Icons.circle_outlined,
                        ),
                        title: Text(trip.line.stops[index].name),
                        enabled: index >= trip.stopIndex,
                      ),
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

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  final FlutterTts _tts = FlutterTts();
  TransitLine _line = lines.first;
  int _stopIndex = 0;
  bool _running = false;

  Stop get _current => _line.stops[_stopIndex];
  Stop? get _next =>
      _stopIndex + 1 < _line.stops.length ? _line.stops[_stopIndex + 1] : null;

  @override
  void initState() {
    super.initState();
    _line = activeTrip.line;
    _stopIndex = activeTrip.stopIndex;
    _running = activeTrip.running;
    _configureAnnouncements();
  }

  Future<void> _configureAnnouncements() async {
    await _tts.setLanguage('cs-CZ');
    await _tts.setSpeechRate(0.46);
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
        IosTextToSpeechAudioMode.spokenAudio,
      );
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      await _tts.setAudioAttributesForNavigation();
    }
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _announceArrival() =>
      _speak('Aktuální zastávka ${_current.name}.');

  Future<void> _depart() async {
    if (_next == null) {
      await _speak('Konečná zastávka. Prosíme, vystupte.');
      setState(() => _running = false);
      return;
    }
    final nextName = _next!.name;
    setState(() {
      _stopIndex++;
      _running = true;
    });
    activeTrip.update(_line, _stopIndex, _running);
    await _speak('Příští zastávka $nextName.');
  }

  void _selectLine(TransitLine? line) {
    if (line == null) return;
    setState(() {
      _line = line;
      _stopIndex = 0;
      _running = false;
    });
    activeTrip.update(_line, _stopIndex, _running);
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
                    initialValue: _line,
                    decoration: const InputDecoration(
                      labelText: 'Linka / odjezd',
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
                const SizedBox(width: 12),
                Container(
                  width: 74,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _line.color,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _line.number,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
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
              value: _stopIndex / (_line.stops.length - 1),
              minHeight: 9,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 10),
            Text(
              _running ? 'Spoj je v provozu' : 'Připraven k odjezdu',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _running ? Colors.greenAccent : Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            ...List.generate(_line.stops.length, (index) {
              final stop = _line.stops[index];
              final passed = index < _stopIndex;
              final active = index == _stopIndex;
              return ListTile(
                leading: Icon(
                  active ? Icons.radio_button_checked : Icons.circle_outlined,
                  color: passed
                      ? Colors.white30
                      : (active ? Colors.amber : Colors.white70),
                ),
                title: Text(stop.name),
                trailing: Text('+${stop.minutes} min'),
                textColor: passed ? Colors.white38 : Colors.white,
                onTap: () {
                  setState(() => _stopIndex = index);
                  activeTrip.update(_line, _stopIndex, _running);
                },
              );
            }),
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
