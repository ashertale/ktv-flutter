// lib/csv_export_web.dart
// Web 實作：透過 Blob + <a download> 觸發瀏覽器下載

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<String> exportCsvFile(String filename, String content) async {
  // 加 BOM (\uFEFF) 讓 Excel / Numbers 正確識別 UTF-8 中文
  // Blob 傳字串陣列，瀏覽器依 charset 參數解碼，不會亂碼
  const bom = '\uFEFF';
  final blob = html.Blob([bom + content], 'text/csv;charset=utf-8');
  final url  = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return '已下載：$filename';
}
