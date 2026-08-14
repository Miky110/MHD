import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() => runApp(const MikylovApp());

class Stop {
  const Stop(this.name, this.minutes);
  final String name;
  final int minutes;
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
    Stop('Bukovany, sídliště', 0),
    Stop('Bukovany, škola', 3),
    Stop('Citice', 8),
    Stop('Sokolov, nemocnice', 14),
    Stop('Sokolov, terminál', 18),
  ]),
  TransitLine('3', 'Habartov, náměstí', Color(0xFF1565C0), [
    Stop('Sokolov, terminál', 0),
    Stop('Citice', 9),
    Stop('Bukovany, rozcestí', 14),
    Stop('Habartov, KLU', 19),
    Stop('Habartov, náměstí', 23),
  ]),
  TransitLine('7', 'Kynšperk nad Ohří', Color(0xFF2E7D32), [
    Stop('Bukovany, sídliště', 0),
    Stop('Dasnice', 10),
    Stop('Chlum Svaté Maří', 16),
    Stop('Kynšperk, škola', 23),
    Stop('Kynšperk, aut. stanice', 27),
  ]),
];

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
      home: const DriverScreen(),
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
  Stop? get _next => _stopIndex + 1 < _line.stops.length
      ? _line.stops[_stopIndex + 1]
      : null;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('cs-CZ');
    _tts.setSpeechRate(0.46);
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
    await _speak('Příští zastávka $nextName.');
  }

  void _selectLine(TransitLine? line) {
    if (line == null) return;
    setState(() {
      _line = line;
      _stopIndex = 0;
      _running = false;
    });
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
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<TransitLine>(
                  value: _line,
                  decoration: const InputDecoration(
                    labelText: 'Linka / odjezd',
                    border: OutlineInputBorder(),
                  ),
                  items: lines.map((line) => DropdownMenuItem(
                    value: line,
                    child: Text('${line.number}  →  ${line.destination}'),
                  )).toList(),
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
                child: Text(_line.number,
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
              ),
            ]),
            const SizedBox(height: 18),
            _StopCard(label: 'AKTUÁLNÍ ZASTÁVKA', stop: _current.name),
            const SizedBox(height: 12),
            _StopCard(
              label: 'NÁSLEDUJE',
              stop: _next?.name ?? 'Konečná zastávka',
              accent: true,
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _announceArrival,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('PŘÍJEZD'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
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
            ]),
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
                  color: passed ? Colors.white30 : (active ? Colors.amber : Colors.white70),
                ),
                title: Text(stop.name),
                trailing: Text('+${stop.minutes} min'),
                textColor: passed ? Colors.white38 : Colors.white,
                onTap: () => setState(() => _stopIndex = index),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({required this.label, required this.stop, this.accent = false});
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
        border: Border.all(color: accent ? Colors.lightBlueAccent : Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white60, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Text(stop, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
