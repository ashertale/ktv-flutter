// lib/csv_export_stub.dart
// 平台無關的介面定義，供條件匯入使用

Future<String> exportCsvFile(String filename, String content) async {
  throw UnsupportedError('No CSV export implementation for this platform');
}
