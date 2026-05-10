// lib/read_file_stub.dart
// Web 編譯用的空實作，實際上在 Web 不會被呼叫

Future<List<int>> readFileBytesImpl(String path) async {
  throw UnsupportedError('File path reading is not supported on web');
}
