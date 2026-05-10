// lib/read_file_native.dart
// Android / iOS 實作：直接用 dart:io 讀取位元組

import 'dart:io';

Future<List<int>> readFileBytesImpl(String path) async {
  return await File(path).readAsBytes();
}
