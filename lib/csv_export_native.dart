// lib/csv_export_native.dart
// Android / iOS 實作
// Android → 用 downloadsfolder 套件寫入公開 Downloads（API 29+ 透過 MediaStore）
// iOS    → 存至 app Documents 資料夾（可透過「檔案」App 存取）

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:downloadsfolder/downloadsfolder.dart';

Future<String> exportCsvFile(String filename, String content) async {
  // 先把內容寫到 app 私有暫存目錄
  final tempDir  = await getTemporaryDirectory();
  final tempFile = File('${tempDir.path}/$filename');
  await tempFile.writeAsString(content, encoding: utf8);

  if (Platform.isAndroid) {
    // copyFileIntoDownloadFolder 在 API 29+ 用 MediaStore，不需要 WRITE 權限
    final bool? success = await copyFileIntoDownloadFolder(
      tempFile.path,
      filename,
    );
    await tempFile.delete();
    if (success == true) {
      return '已儲存至 Downloads/$filename';
    } else {
      throw Exception('寫入 Downloads 失敗，請確認儲存空間是否足夠');
    }
  } else {
    // iOS：移到 Documents 目錄
    final docsDir = await getApplicationDocumentsDirectory();
    final dest    = File('${docsDir.path}/$filename');
    await tempFile.copy(dest.path);
    await tempFile.delete();
    return '已儲存至：${dest.path}';
  }
}
