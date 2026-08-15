import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

class GtfsSource {
  const GtfsSource({required this.name, required this.city, required this.url});

  final String name;
  final String city;
  final String url;
}

class GtfsImportResult {
  const GtfsImportResult({
    required this.source,
    required this.stopCount,
    required this.stationCount,
    required this.routeCount,
  });

  final GtfsSource source;
  final int stopCount;
  final int stationCount;
  final int routeCount;
}

const gtfsSources = <GtfsSource>[
  GtfsSource(
    name: 'Pražská integrovaná doprava (PID)',
    city: 'Praha a Středočeský kraj',
    url: 'https://data.pid.cz/PID_GTFS.zip',
  ),
];

class GtfsImporter {
  Future<GtfsImportResult> import(GtfsSource source) async {
    final response = await http.get(Uri.parse(source.url));
    if (response.statusCode != 200) {
      throw Exception('Stažení selhalo (HTTP ${response.statusCode}).');
    }

    final archive = ZipDecoder().decodeBytes(response.bodyBytes);
    final stops = _readCsv(archive, 'stops.txt');
    final routes = _readCsv(archive, 'routes.txt');
    if (stops.isEmpty || routes.isEmpty) {
      throw Exception('Balíček neobsahuje platná GTFS data.');
    }

    final stopHeader = stops.first.map((value) => '$value').toList();
    final locationTypeIndex = stopHeader.indexOf('location_type');
    var stationCount = 0;
    if (locationTypeIndex >= 0) {
      for (final row in stops.skip(1)) {
        if (row.length > locationTypeIndex &&
            '${row[locationTypeIndex]}' == '1') {
          stationCount++;
        }
      }
    }

    return GtfsImportResult(
      source: source,
      stopCount: stops.length - 1,
      stationCount: stationCount,
      routeCount: routes.length - 1,
    );
  }

  List<List<dynamic>> _readCsv(Archive archive, String name) {
    final file = archive.files.cast<ArchiveFile?>().firstWhere(
          (item) => item?.name == name,
          orElse: () => null,
        );
    if (file == null || !file.isFile || file.content is! List<int>) return [];
    final text = utf8.decode(file.content as List<int>, allowMalformed: true);
    return const CsvToListConverter(shouldParseNumbers: false).convert(text);
  }
}
