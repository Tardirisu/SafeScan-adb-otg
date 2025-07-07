// lib/services/csv_utils.dart

import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

// Holds both the CSV rows *and* whether
// they were loaded from the network.
class CSVFetchResult {
  final List<List<dynamic>> data;
  final bool isRemote;  // true = online, false = local fallback

  CSVFetchResult(this.data, this.isRemote);
}

// Remote CSV URL
const String _csvUrl =
    'https://raw.githubusercontent.com/stopipv/isdi/main/static_data/app-flags.csv';

// Timeout for network fetch
const Duration _fetchTimeout = Duration(seconds: 5);

// Primary entrypoint: try remote first, fallback to local asset
Future<CSVFetchResult> fetchCSVData() async {
  try {
    final rows = await _fetchRemoteCSVData();
    return CSVFetchResult(rows, true);
  } catch (e) {
    // remote failed or timed out
    print('Remote CSV fetch failed: $e\nFalling back to local asset.');
    final rows = await _loadLocalCSVData();
    return CSVFetchResult(rows, false);
  }
}

// Fetch CSV data from the network
Future<List<List<dynamic>>> _fetchRemoteCSVData() async {
  final response = await http
      .get(Uri.parse(_csvUrl))
      .timeout(_fetchTimeout, onTimeout: () {
    throw Exception('Remote CSV fetch timed out');
  });

  if (response.statusCode == 200) {
    final raw = utf8.decode(response.bodyBytes);
    return const CsvToListConverter().convert(raw);
  } else {
    throw Exception(
        'Remote CSV error: ${response.statusCode} ${response.reasonPhrase}');
  }
}

// Load CSV data from a bundled asset
Future<List<List<dynamic>>> _loadLocalCSVData() async {
  // Make sure you've declared this asset in pubspec.yaml:
  // flutter:
  //   assets:
  //     - assets/app-flags.csv
  final csvString = await rootBundle.loadString('assets/app-flags.csv');
  return const CsvToListConverter().convert(csvString);
}
