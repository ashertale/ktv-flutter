import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

// ── 條件匯入：編譯時自動選擇正確平台實作 ─────────────────────────────────────
//  CSV 匯出：
//    Web  → csv_export_web.dart    (dart:html Blob 下載)
//    原生 → csv_export_native.dart (path_provider 寫檔)
//  檔案讀取（匯入 path fallback）：
//    Web  → read_file_stub.dart    (空實作，Web 不呼叫)
//    原生 → read_file_native.dart  (dart:io readAsBytes)
import 'csv_export_stub.dart'
    if (dart.library.html) 'csv_export_web.dart'
    if (dart.library.io)   'csv_export_native.dart';

import 'read_file_stub.dart'
    if (dart.library.io) 'read_file_native.dart';

void main() async {
  // 等待字型載入完成再渲染，避免中文字符短暫顯示亂碼
  WidgetsFlutterBinding.ensureInitialized();
  await _loadFonts();
  runApp(const KtvApp());
}

Future<void> _loadFonts() async {
  // 告知引擎等待所有平台字型就緒後才開始繪製第一幀
  // 這樣可以避免 CJK 字符在首次渲染時出現方塊或亂碼
  if (kIsWeb) {
    await Future.delayed(Duration.zero); // 讓 Web font engine 完成初始化
  }
}

// ─── Model ────────────────────────────────────────────────────────────────────

// ─── 全域遞增計數器，確保同毫秒內產生的 ID 也不重複 ─────────────────────────
int _idCounter = 0;

class Song {
  final String id;
  final String name;
  final String artist;
  final String code;

  Song({
    required this.id,
    required this.name,
    required this.artist,
    required this.code,
  });

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id:     j['id']     as String? ?? _genId(),
        name:   j['name']   as String? ?? '',
        artist: j['artist'] as String? ?? '',
        code:   j['code']   as String? ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'artist': artist, 'code': code};

  static String _genId() {
    _idCounter++;
    final ts  = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final cnt = _idCounter.toRadixString(36).padLeft(4, '0');
    return '$ts-$cnt';
  }
}

String genId() => Song._genId();

// ─── App ──────────────────────────────────────────────────────────────────────

class KtvApp extends StatelessWidget {
  const KtvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '歌單',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.black, brightness: Brightness.light),
        // Noto Sans TC 完整覆蓋 CJK 字符，避免 Web 渲染時出現亂碼閃爍
        textTheme: GoogleFonts.notoSansTcTextTheme(),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ─── LongPressItem ────────────────────────────────────────────────────────────
// 自訂長按進度條動畫，Web & 原生都適用

class LongPressItem extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  const LongPressItem({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
  });

  @override
  State<LongPressItem> createState() => _LongPressItemState();
}

class _LongPressItemState extends State<LongPressItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _pressing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && _pressing && mounted) {
        _pressing = false;
        _ctrl.reset();
        widget.onLongPress?.call();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent _) {
    if (!widget.enabled) return;
    _ctrl.stop();   // 停掉上一次殘留的動畫（快速連點保護）
    _pressing = true;
    _ctrl.forward(from: 0);
  }

  void _onUp(PointerUpEvent _) {
    if (!_pressing) return;
    _pressing = false;
    final wasCompleted = _ctrl.value >= 0.99;
    _ctrl.reset();
    if (!wasCompleted && mounted) widget.onTap?.call();
  }

  void _onCancel(PointerCancelEvent _) {
    if (!_pressing) return;
    _pressing = false;
    _ctrl.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown:   _onDown,
      onPointerUp:     _onUp,
      onPointerCancel: _onCancel,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, child) {
          return Stack(children: [
            child!,
            if (widget.enabled && _ctrl.value > 0)
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(10)),
                  child: LinearProgressIndicator(
                    value: _ctrl.value,
                    minHeight: 3,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFc0392b)),
                  ),
                ),
              ),
          ]);
        },
        child: widget.child,
      ),
    );
  }
}

// ─── HomePage ─────────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ── data ──
  List<Song> songs = [];
  Set<String> starredSet = {};

  // ── ui state ──
  bool isClean = true;
  bool starOnly = false;
  bool showArtist = false;
  int currentTab = 0;
  int fontSize = 34;
  int itemSpacing = 8;

  // ── single fullscreen ──
  bool showSingle = false;
  List<String> singleList = [];
  int singlePos = 0;

  // ── search ──
  final TextEditingController searchCtrl = TextEditingController();
  String searchMode = 'song';

  // ── add ──
  final TextEditingController nameCtrl   = TextEditingController();
  final TextEditingController codeCtrl   = TextEditingController();
  final TextEditingController artistCtrl = TextEditingController();

  // ── scroll ──
  final ScrollController browseScrollCtrl = ScrollController();
  bool showTopBtn = false;

  // ── overlays ──
  Song? actionTarget;
  bool showActionSheet  = false;
  bool showClearConfirm = false;
  bool showPinOverlay   = false;
  String pinBuffer = '';
  bool pinError = false;

  // ── toast ──
  String toastMsg   = '';
  bool toastVisible = false;

  // ── info ──
  bool showInfo   = false;
  String infoTitle = '';
  String infoSub   = '';

  // ── dup ──
  bool showDup = false;
  String dupMsg = '';

  static const String _pinCode = '0000';

  static const List<Map<String, String>> _defaultSongs = [
    {'id': 'default-1', 'name': '青花瓷',         'artist': '周杰倫', 'code': '12345'},
    {'id': 'default-2', 'name': '告白氣球',        'artist': '周杰倫', 'code': '67890'},
    {'id': 'default-3', 'name': '月亮代表我的心',   'artist': '鄧麗君', 'code': '11111'},
    {'id': 'default-4', 'name': '甜蜜蜜',          'artist': '鄧麗君', 'code': '22222'},
  ];

  // ────────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadAll();
    browseScrollCtrl.addListener(() {
      final show = browseScrollCtrl.offset > 200;
      if (show != showTopBtn) setState(() => showTopBtn = show);
    });
  }

  @override
  void dispose() {
    browseScrollCtrl.dispose();
    searchCtrl.dispose();
    nameCtrl.dispose();
    codeCtrl.dispose();
    artistCtrl.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Persistence
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();

    List<Song> loadedSongs;
    final songsJson = prefs.getString('ktv_songs_v2');
    if (songsJson != null) {
      final list = jsonDecode(songsJson) as List;
      loadedSongs =
          list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      loadedSongs = _defaultSongs
          .map((e) => Song(
                id: e['id']!, name: e['name']!,
                artist: e['artist']!, code: e['code']!))
          .toList();
    }

    Set<String> starred = {};
    final starredJson = prefs.getString('ktv_starred_v2');
    if (starredJson != null) {
      starred =
          (jsonDecode(starredJson) as List).map((e) => e.toString()).toSet();
    }

    int font = 34, spacing = 8;
    bool sArtist = false, sOnly = false;
    final settingsJson = prefs.getString('ktv_settings_v1');
    if (settingsJson != null) {
      final m = jsonDecode(settingsJson) as Map<String, dynamic>;
      font    = m['font']       as int?  ?? 34;
      spacing = m['spacing']    as int?  ?? 8;
      sArtist = m['showArtist'] as bool? ?? false;
      sOnly   = m['starOnly']   as bool? ?? false;
    }

    setState(() {
      songs       = loadedSongs;
      starredSet  = starred;
      fontSize    = font;
      itemSpacing = spacing;
      showArtist  = sArtist;
      starOnly    = sOnly;
    });
  }

  Future<void> _saveSongs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'ktv_songs_v2', jsonEncode(songs.map((s) => s.toJson()).toList()));
  }

  Future<void> _saveStarred({List<Song>? currentSongs}) async {
    // 用傳入的 currentSongs（而非 this.songs）來過濾，
    // 避免 setState 尚未生效時 this.songs 仍是舊值的問題
    final validIds = (currentSongs ?? songs).map((s) => s.id).toSet();
    starredSet = starredSet.intersection(validIds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ktv_starred_v2', jsonEncode(starredSet.toList()));
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ktv_settings_v1', jsonEncode({
      'font': fontSize, 'spacing': itemSpacing,
      'showArtist': showArtist, 'starOnly': starOnly,
    }));
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────────

  List<Song> get _pinnedSongs =>
      songs.where((s) => starredSet.contains(s.id)).toList();
  List<Song> get _otherSongs =>
      songs.where((s) => !starredSet.contains(s.id)).toList();

  List<String> _buildSingleList() {
    final pinned = songs.where((s) =>  starredSet.contains(s.id)).map((s) => s.id);
    final others = songs.where((s) => !starredSet.contains(s.id)).map((s) => s.id);
    return [...pinned, ...others];
  }

  void _openSingle(String id) {
    final list = _buildSingleList();
    final pos  = list.indexOf(id);
    setState(() {
      singleList = list;
      singlePos  = pos < 0 ? 0 : pos;
      showSingle = true;
    });
  }

  void _navSingle(int delta) {
    final next = singlePos + delta;
    if (next < 0 || next >= singleList.length) return;
    setState(() => singlePos = next);
  }

  Song? get _currentSingleSong {
    if (singleList.isEmpty) return null;
    final id = singleList[singlePos];
    try {
      return songs.firstWhere((s) => s.id == id);
    } on StateError {
      return null;
    }
  }

  void _showToastMsg(String msg) {
    setState(() { toastMsg = msg; toastVisible = true; });
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => toastVisible = false);
    });
  }

  void _showInfoDialog(String title, String sub) {
    setState(() { infoTitle = title; infoSub = sub; showInfo = true; });
  }

  void _addSong() {
    final name   = nameCtrl.text.trim();
    final code   = codeCtrl.text.trim();
    final artist = artistCtrl.text.trim();
    if (name.isEmpty || code.isEmpty) {
      _showInfoDialog('請填寫必要資訊', '歌名和代號不能空白');
      return;
    }
    if (songs.any((s) => s.name == name && s.code == code)) {
      setState(() {
        dupMsg  = '「$name」（代號 $code）\n已在歌單中，不重複新增。';
        showDup = true;
      });
      return;
    }
    setState(() {
      songs.add(Song(id: genId(), name: name, artist: artist, code: code));
      nameCtrl.clear(); codeCtrl.clear(); artistCtrl.clear();
      currentTab = 0;
    });
    _saveSongs();
    _showToastMsg('✓ 已加入歌單');
  }

  void _toggleStar(String id) {
    setState(() {
      starredSet.contains(id) ? starredSet.remove(id) : starredSet.add(id);
    });
    _saveStarred();
  }

  void _deleteSong(String id) {
    final newSongs = songs.where((s) => s.id != id).toList();
    starredSet.remove(id);
    setState(() {
      songs = newSongs;
      showActionSheet = false;
      actionTarget    = null;
    });
    _saveSongs();
    _saveStarred(currentSongs: newSongs);
  }

  void _toggleClean() {
    setState(() {
      isClean = !isClean;
      if (isClean && currentTab != 0) currentTab = 0;
    });
  }

  void _toggleStarOnly()   { setState(() => starOnly   = !starOnly);   _saveSettings(); }
  void _toggleShowArtist() { setState(() => showArtist = !showArtist); _saveSettings(); }

  void _changeFont(int d) {
    setState(() => fontSize = (fontSize + d).clamp(22, 64));
    _saveSettings();
  }

  void _changeSpacing(int d) {
    setState(() => itemSpacing = (itemSpacing + d).clamp(4, 36));
    _saveSettings();
  }

  // ── PIN ──────────────────────────────────────────────────────────────────────

  void _pinInput(String digit) {
    if (pinBuffer.length >= 4) return;
    setState(() { pinBuffer += digit; pinError = false; });
    if (pinBuffer.length == 4) {
      if (pinBuffer == _pinCode) {
        setState(() {
          songs = []; starredSet = {};
          showPinOverlay = false; pinBuffer = '';
        });
        _saveSongs(); _saveStarred();
      } else {
        setState(() => pinError = true);
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() { pinBuffer = ''; pinError = false; });
        });
      }
    }
  }

  void _pinDelete() {
    if (pinBuffer.isEmpty) return;
    setState(() => pinBuffer = pinBuffer.substring(0, pinBuffer.length - 1));
  }

  // ── CSV ── 透過條件匯入的 exportCsvFile() 自動選擇平台實作 ──────────────────

  Future<void> _exportCSV() async {
    final sb = StringBuffer();
    sb.writeln('name,code,artist,pinned');
    for (final s in songs) {
      String esc(String v) => '"${v.replaceAll('"', '""')}"';
      final pinned = starredSet.contains(s.id) ? '1' : '0';
      sb.writeln('${esc(s.name)},${esc(s.code)},${esc(s.artist)},$pinned');
    }
    try {
      final date     = DateTime.now().toIso8601String().substring(0, 10);
      final filename = 'ktv_歌單_$date.csv';
      // exportCsvFile() 在 Web → Blob 下載；Android/iOS → 寫入 documents 目錄
      final resultMsg = await exportCsvFile(filename, sb.toString());
      _showInfoDialog('匯出完成', resultMsg);
    } catch (e) {
      _showInfoDialog('匯出失敗', e.toString());
    }
  }

  Future<void> _importCSV() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true, // Web 必須用 bytes；原生也可用，統一處理
      );
      if (result == null || result.files.isEmpty) return;

      // 統一用 bytes 讀取，Web / Android 都適用
      final fileBytes = result.files.single.bytes;
      if (fileBytes == null) {
        // Android fallback：bytes 為 null 時嘗試 path
        if (!kIsWeb) {
          final path = result.files.single.path;
          if (path != null) {
            await _importFromPath(path);
            return;
          }
        }
        _showInfoDialog('匯入失敗', '無法讀取檔案內容');
        return;
      }

      String text = utf8.decode(fileBytes, allowMalformed: true);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      await _processCSVText(text);
    } catch (e) {
      _showInfoDialog('匯入失敗', e.toString());
    }
  }

  Future<void> _importFromPath(String path) async {
    // 此方法只在原生平台執行，透過 csv_export_native 間接使用 dart:io
    // 避免在 Web 上直接 import dart:io 造成編譯失敗
    try {
      final bytes = await _readFileBytes(path);
      String text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      await _processCSVText(text);
    } catch (e) {
      _showInfoDialog('匯入失敗', e.toString());
    }
  }

  Future<void> _processCSVText(String text) async {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (lines.length < 2) {
      _showInfoDialog('格式有誤', 'CSV 內容為空或格式不正確');
      return;
    }

    final headers =
        _parseCSVLine(lines[0]).map((h) => h.toLowerCase().trim()).toList();
    final nameIdx   = headers.indexOf('name');
    final artistIdx = headers.indexOf('artist');
    final codeIdx   = headers.indexOf('code');
    final pinnedIdx = headers.indexOf('pinned');

    if (nameIdx < 0 || codeIdx < 0) {
      _showInfoDialog('格式有誤', 'CSV 必須包含 name 和 code 欄位');
      return;
    }

    int added = 0, skipped = 0, pinnedAdded = 0;
    final newSongs   = List<Song>.from(songs);
    final newStarred = Set<String>.from(starredSet);

    for (int i = 1; i < lines.length; i++) {
      final cols   = _parseCSVLine(lines[i]);
      final name   = cols.length > nameIdx   ? cols[nameIdx].trim()   : '';
      final code   = cols.length > codeIdx   ? cols[codeIdx].trim()   : '';
      final artist = artistIdx >= 0 && cols.length > artistIdx
          ? cols[artistIdx].trim() : '';
      final pinned = pinnedIdx >= 0 && cols.length > pinnedIdx
          ? cols[pinnedIdx].trim() : '0';
      if (name.isEmpty || code.isEmpty) continue;
      if (newSongs.any((s) => s.name == name && s.code == code)) {
        skipped++;
        continue;
      }
      final id = genId();
      newSongs.add(Song(id: id, name: name, artist: artist, code: code));
      if (pinned == '1') { newStarred.add(id); pinnedAdded++; }
      added++;
    }

    setState(() { songs = newSongs; starredSet = newStarred; });
    // 傳入 newSongs 確保 _saveStarred 用正確的 songs 過濾，不受 setState 時序影響
    _saveSongs();
    await _saveStarred(currentSongs: newSongs);
    final note = pinnedAdded > 0 ? '，其中 $pinnedAdded 首加入常用' : '';
    _showInfoDialog('匯入完成！', '新增 $added 首$note\n略過重複 $skipped 首');
  }

  List<String> _parseCSVLine(String line) {
    final result = <String>[];
    var cur = StringBuffer();
    bool inQ = false;
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQ) {
        if (c == '"' && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"'); i++;
        } else if (c == '"') {
          inQ = false;
        } else {
          cur.write(c);
        }
      } else {
        if (c == '"')      { inQ = true; }
        else if (c == ',') { result.add(cur.toString()); cur = StringBuffer(); }
        else               { cur.write(c); }
      }
    }
    result.add(cur.toString());
    return result;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(children: [
          Column(children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ]),
          if (showSingle)       _buildSingleOverlay(),
          if (showActionSheet)  _buildActionSheet(),
          if (showClearConfirm) _buildClearConfirm(),
          if (showPinOverlay)   _buildPinOverlay(),
          if (showDup)          _buildDupSheet(),
          if (showInfo)         _buildInfoSheet(),
          if (toastVisible)     _buildToast(),
          if (!isClean && currentTab == 0 && showTopBtn)
            Positioned(
              right: 16, bottom: 24,
              child: GestureDetector(
                onTap: () => browseScrollCtrl.animateTo(0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut),
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(
                    color: Colors.black, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: Colors.black26, blurRadius: 10,
                        offset: Offset(0, 2))],
                  ),
                  child: const Icon(Icons.arrow_upward,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final starCount = songs.where((s) => starredSet.contains(s.id)).length;
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.black, width: 2)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('歌單',
                  style: TextStyle(fontFamily: 'Georgia', fontSize: 22,
                      fontWeight: FontWeight.w700, letterSpacing: 3,
                      color: Color(0xFF111111))),
              const SizedBox(width: 10),
              if (!isClean)
                const Text('KTV',
                    style: TextStyle(fontSize: 13,
                        color: Color(0xFF888888), letterSpacing: 1)),
              const SizedBox(width: 4),
              Text('${songs.length} 首',
                  style: const TextStyle(fontSize: 13,
                      color: Color(0xFF888888), letterSpacing: 1)),
              const Spacer(),
              if (starCount > 0)
                Text('常用 $starCount 首',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF3d6fd4),
                        fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(width: 8),
              _viewToggleBtn(),
            ],
          ),
          if (!isClean) ...[
            const SizedBox(height: 4),
            _buildTabs(),
          ] else
            const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _viewToggleBtn() => GestureDetector(
        onTap: _toggleClean,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(
                color: isClean ? const Color(0xFF444444) : const Color(0xFFc8c8c8)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(isClean ? '鎖定' : '解鎖',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                  color: isClean
                      ? const Color(0xFF444444) : const Color(0xFF888888))),
        ),
      );

  Widget _buildTabs() {
    const tabs = [
      {'label': '歌曲列表', 'idx': 0},
      {'label': '搜　尋',   'idx': 1},
      {'label': '新　增',   'idx': 2},
      {'label': '設　定',   'idx': 3},
    ];
    return Row(
      children: tabs.map((t) {
        final idx    = t['idx'] as int;
        final active = currentTab == idx;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => currentTab = idx),
            child: Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(
                    color: active ? Colors.black : Colors.transparent, width: 3)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(t['label'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: active
                            ? const Color(0xFF111111) : const Color(0xFF444444))),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (isClean) return _buildBrowsePage();
    switch (currentTab) {
      case 0:  return _buildBrowsePage();
      case 1:  return _buildSearchPage();
      case 2:  return _buildAddPage();
      case 3:  return _buildSettingsPage();
      default: return _buildBrowsePage();
    }
  }

  // ── Browse ─────────────────────────────────────────────────────────────────

  Widget _buildBrowsePage() {
    return Column(children: [
      if (!isClean) _buildBrowseControls(),
      Expanded(
        child: songs.isEmpty
            ? _buildEmpty('歌單是空的', '前往新增頁面添加')
            : _buildSongList(),
      ),
    ]);
  }

  Widget _buildBrowseControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFe0e0e0)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _fontControl('字體', fontSize.toString(),
              () => _changeFont(-4), () => _changeFont(4)),
          const SizedBox(width: 10),
          _fontControl('間距', itemSpacing.toString(),
              () => _changeSpacing(-2), () => _changeSpacing(2)),
          const SizedBox(width: 10),
          _smallToggleBtn('歌手', showArtist, _toggleShowArtist),
        ],
      ),
    );
  }

  Widget _fontControl(
      String label, String val, VoidCallback onMinus, VoidCallback onPlus) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFc8c8c8)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF888888),
                fontWeight: FontWeight.w500, letterSpacing: 1)),
        const SizedBox(width: 5),
        _iconBtn('−', onMinus),
        SizedBox(
          width: 28,
          child: Text(val, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                  color: Color(0xFF444444))),
        ),
        _iconBtn('+', onPlus),
      ]),
    );
  }

  Widget _iconBtn(String ch, VoidCallback fn) => GestureDetector(
        onTap: fn,
        child: Container(
          width: 24, height: 24,
          decoration: BoxDecoration(color: const Color(0xFFf4f4f4),
              borderRadius: BorderRadius.circular(4)),
          alignment: Alignment.center,
          child: Text(ch,
              style: const TextStyle(fontSize: 17, color: Color(0xFF444444))),
        ),
      );

  Widget _smallToggleBtn(String label, bool active, VoidCallback fn) =>
      GestureDetector(
        onTap: fn,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(
                color: active ? const Color(0xFF444444) : const Color(0xFFc8c8c8)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                  color: active
                      ? const Color(0xFF444444) : const Color(0xFF888888))),
        ),
      );

  Widget _buildSongList() {
    final pinned     = _pinnedSongs;
    final others     = starOnly ? <Song>[] : _otherSongs;
    final hasDivider = pinned.isNotEmpty && others.isNotEmpty;
    final total      = 1 + pinned.length + (hasDivider ? 1 : 0) + others.length;

    return Scrollbar(
      controller: browseScrollCtrl,
      interactive: true,       // 可直接拖曳捲軸快速跳轉
      thumbVisibility: false,  // 平時隱藏，僅捲動時顯示
      thickness: 4,
      radius: const Radius.circular(4),
      child: ListView.builder(
        controller: browseScrollCtrl,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
        itemCount: total,
        itemBuilder: (ctx, i) {
          if (i == 0) return _columnHeader();

        final iPinned = i - 1;
        if (iPinned < pinned.length) return _buildSongItem(pinned[iPinned], true);

        if (hasDivider && i == 1 + pinned.length) return _buildDivider();

        final othersStart = 1 + pinned.length + (hasDivider ? 1 : 0);
        final iOther      = i - othersStart;
        if (iOther >= 0 && iOther < others.length) {
          return _buildSongItem(others[iOther], false);
        }
        return const SizedBox();
      },
    ),   // ListView.builder
    );   // Scrollbar
  }

  Widget _columnHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 7),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
          Text('歌曲名稱',
              style: TextStyle(fontSize: 10, letterSpacing: 2,
                  color: Color(0xFF888888), fontWeight: FontWeight.w700)),
          Text('代號',
              style: TextStyle(fontSize: 10, letterSpacing: 2,
                  color: Color(0xFF888888), fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _buildDivider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: const [
          Expanded(child: Divider(color: Color(0xFFe0e0e0), height: 1)),
          SizedBox(width: 8),
          Text('其他歌曲',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 2, color: Color(0xFF888888))),
          SizedBox(width: 8),
          Expanded(child: Divider(color: Color(0xFFe0e0e0), height: 1)),
        ]),
      );

  Widget _buildSongItem(Song song, bool isPinned) {
    final nameColor  = isPinned ? const Color(0xFF3d6fd4) : const Color(0xFF111111);
    final codeColor  = isPinned ? const Color(0xFF3d6fd4) : const Color(0xFF111111);
    final codeBorder = isPinned ? const Color(0xFF3d6fd4) : const Color(0xFFc8c8c8);
    final double fs  = fontSize.toDouble();
    final double pad = itemSpacing.toDouble();
    final double gap = (itemSpacing * 0.5).clamp(2.0, double.infinity);

    final itemBody = Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: pad),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFe0e0e0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(song.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700,
                    color: nameColor)),
            if (showArtist && !isClean && song.artist.isNotEmpty)
              Text(song.artist,
                  style: TextStyle(fontSize: fs * 0.42,
                      color: const Color(0xFF888888), fontWeight: FontWeight.w500)),
          ]),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFf4f4f4),
            border: Border.all(color: codeBorder, width: 1.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(song.code,
              style: TextStyle(fontSize: fs * 0.8, fontWeight: FontWeight.w700,
                  color: codeColor, letterSpacing: 2)),
        ),
      ]),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: LongPressItem(
        key: ValueKey(song.id), // ← 必要：防止 ListView rebuild 時 State 錯位
        enabled: !isClean,
        onTap: () => _openSingle(song.id),
        onLongPress: () => _showActionMenu(song),
        child: itemBody,
      ),
    );
  }

  void _showActionMenu(Song song) {
    setState(() { actionTarget = song; showActionSheet = true; });
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  Widget _buildSearchPage() {
    final q = searchCtrl.text.trim();
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFe0e0e0)))),
        child: Column(children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFf4f4f4),
              border: Border.all(color: const Color(0xFFe0e0e0), width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('搜',
                      style: TextStyle(color: Color(0xFF888888),
                          fontWeight: FontWeight.w700))),
              Expanded(
                child: TextField(
                  controller: searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 20, color: Color(0xFF111111)),
                  decoration: InputDecoration(
                    hintText: searchMode == 'artist' ? '搜尋歌手名稱' : '搜尋歌名或代號',
                    hintStyle: const TextStyle(color: Color(0xFF888888)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _searchModeBtn('歌曲 / 代號', 'song')),
            const SizedBox(width: 6),
            Expanded(child: _searchModeBtn('歌手', 'artist')),
          ]),
        ]),
      ),
      Expanded(child: _buildSearchResults(q)),
    ]);
  }

  Widget _searchModeBtn(String label, String mode) {
    final active = searchMode == mode;
    return GestureDetector(
      onTap: () => setState(() { searchMode = mode; searchCtrl.clear(); }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? Colors.black : const Color(0xFFf4f4f4),
          border: Border.all(
              color: active ? Colors.black : const Color(0xFFe0e0e0), width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: active ? Colors.white : const Color(0xFF444444))),
      ),
    );
  }

  Widget _buildSearchResults(String q) {
    if (searchMode == 'artist') {
      if (q.isEmpty) return _buildEmpty('輸入歌手名稱', '搜尋歌單中該歌手的所有歌曲');
      final filtered = songs.where((s) => s.artist.contains(q)).toList();
      if (filtered.isEmpty) return _buildEmpty('查無歌手', '「$q」不在歌單中');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
        itemCount: 1 + filtered.length,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
              child: Row(children: [
                const Text('歌手：',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        letterSpacing: 2, color: Color(0xFF888888))),
                Text(q,
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: Color(0xFF111111))),
                Text('　共 ${filtered.length} 首',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
              ]),
            );
          }
          return _buildSongItem(
              filtered[i - 1], starredSet.contains(filtered[i - 1].id));
        },
      );
    } else {
      if (q.isEmpty) return _buildEmpty('輸入關鍵字', '搜尋歌名或代號');
      final filtered = songs
          .where((s) => s.name.contains(q) || s.code.contains(q)).toList();
      if (filtered.isEmpty) return _buildEmpty('查無結果', '換個關鍵字試試');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
        itemCount: 1 + filtered.length,
        itemBuilder: (ctx, i) {
          if (i == 0) return _columnHeader();
          return _buildSongItem(
              filtered[i - 1], starredSet.contains(filtered[i - 1].id));
        },
      );
    }
  }

  // ── Add ────────────────────────────────────────────────────────────────────

  Widget _buildAddPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _addCard(),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _addSong,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.black, borderRadius: BorderRadius.circular(10)),
            child: const Text('加 入 歌 單',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Georgia', fontSize: 17,
                    fontWeight: FontWeight.w700, color: Colors.white,
                    letterSpacing: 4)),
          ),
        ),
        const SizedBox(height: 16),
        const Text('長按歌曲一秒可移除',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF888888),
                letterSpacing: 1, height: 1.8)),
      ]),
    );
  }

  Widget _addCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFe0e0e0), width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('新增一首歌',
            style: TextStyle(fontFamily: 'Georgia', fontSize: 14,
                fontWeight: FontWeight.w600, color: Color(0xFF444444),
                letterSpacing: 2)),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFe0e0e0)),
        const SizedBox(height: 14),
        _inputField('歌　曲　名　稱', nameCtrl, '請輸入歌名'),
        const SizedBox(height: 12),
        _inputField('點　歌　代　號', codeCtrl, '請輸入代號', numeric: true),
        const SizedBox(height: 12),
        _inputField('歌　手　／　演唱者', artistCtrl, '請輸入歌手（可留空）'),
      ]),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, String hint,
      {bool numeric = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(fontSize: 11, letterSpacing: 2,
              color: Color(0xFF888888), fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 20, color: Color(0xFF111111)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF888888)),
          filled: true, fillColor: const Color(0xFFf4f4f4),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFe0e0e0), width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.black, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFe0e0e0), width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    ]);
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  Widget _buildSettingsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFe0e0e0), width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('備份管理',
                style: TextStyle(fontFamily: 'Georgia', fontSize: 14,
                    fontWeight: FontWeight.w600, color: Color(0xFF444444),
                    letterSpacing: 2)),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFe0e0e0)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _backupBtn('匯　出 CSV', onTap: _exportCSV)),
              const SizedBox(width: 10),
              Expanded(child: _backupBtn('匯　入 CSV',
                  outlined: true, onTap: _importCSV)),
            ]),
            const SizedBox(height: 10),
            _backupBtn('清空歌單', danger: true,
                onTap: () => setState(() => showClearConfirm = true)),
          ]),
        ),
        const SizedBox(height: 12),
        Text(
          kIsWeb
              ? '匯出 CSV 將直接下載到瀏覽器；匯入可還原歌單'
              : '匯出 CSV 將儲存至裝置文件目錄；匯入可還原歌單',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Color(0xFF888888),
              letterSpacing: 1, height: 1.8),
        ),
      ]),
    );
  }

  Widget _backupBtn(String label,
      {bool danger = false, bool outlined = false, required VoidCallback onTap}) {
    final bgColor    = danger || outlined ? Colors.transparent : const Color(0xFFf4f4f4);
    final labelColor = danger ? const Color(0xFFc0392b) : const Color(0xFF111111);
    final border     = danger ? const Color(0xFFc0392b) : const Color(0xFFc8c8c8);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: border, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                letterSpacing: 1, color: labelColor)),
      ),
    );
  }

  // ── Single fullscreen ───────────────────────────────────────────────────────

  Widget _buildSingleOverlay() {
    final song = _currentSingleSong;
    if (song == null) return const SizedBox();
    final isStarred = starredSet.contains(song.id);
    final nameColor = isStarred ? const Color(0xFF3d6fd4) : const Color(0xFF111111);
    final codeColor = isStarred ? const Color(0xFF3d6fd4) : Colors.black;
    final sw = MediaQuery.of(context).size.width;

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) _navSingle(1);
        if (v > 200)  _navSingle(-1);
      },
      child: Container(
        color: Colors.white,
        child: Stack(children: [
          Positioned(top: 0, left: 0, right: 0,
              child: Container(height: 3, color: Colors.black)),
          SafeArea(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('NOW SINGING',
                  style: TextStyle(fontSize: 11, letterSpacing: 5,
                      color: Color(0xFF888888))),
              const SizedBox(height: 10),
              const Text('← 左右滑動可切換歌曲 →',
                  style: TextStyle(fontSize: 13, color: Color(0xFF888888),
                      letterSpacing: 1)),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(song.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Georgia',
                        fontSize: (sw * 0.12).clamp(44.0, 78.0),
                        fontWeight: FontWeight.w700, color: nameColor,
                        height: 1.15)),
              ),
              const SizedBox(height: 12),
              if (song.artist.isNotEmpty)
                Text(song.artist,
                    style: const TextStyle(fontSize: 22,
                        color: Color(0xFF888888), fontWeight: FontWeight.w500)),
              SizedBox(height: song.artist.isNotEmpty ? 28 : 14),
              Container(width: 40, height: 2, color: const Color(0xFFc8c8c8),
                  margin: const EdgeInsets.only(bottom: 24)),
              const Text('SONG CODE',
                  style: TextStyle(fontSize: 11, letterSpacing: 4,
                      color: Color(0xFF888888))),
              const SizedBox(height: 8),
              Text(song.code,
                  style: TextStyle(
                      fontSize: (sw * 0.16).clamp(56.0, 96.0),
                      fontWeight: FontWeight.w700, color: codeColor,
                      letterSpacing: 8)),
              const SizedBox(height: 40),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _navBtn('‹', singlePos > 0 ? () => _navSingle(-1) : null),
                const SizedBox(width: 24),
                Text('${singlePos + 1} / ${singleList.length}',
                    style: const TextStyle(fontSize: 11, letterSpacing: 3,
                        color: Color(0xFF888888))),
                const SizedBox(width: 24),
                _navBtn('›',
                    singlePos < singleList.length - 1 ? () => _navSingle(1) : null),
              ]),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () => setState(() => showSingle = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFc8c8c8), width: 1.5),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text('返回歌單',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                          letterSpacing: 2, color: Color(0xFF444444))),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _navBtn(String ch, VoidCallback? fn) => GestureDetector(
        onTap: fn,
        child: Opacity(
          opacity: fn == null ? 0.2 : 1.0,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFc8c8c8), width: 1.5),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(ch,
                style: const TextStyle(fontSize: 20, color: Color(0xFF444444))),
          ),
        ),
      );

  // ── Action Sheet ────────────────────────────────────────────────────────────

  Widget _buildActionSheet() {
    final song = actionTarget;
    if (song == null) return const SizedBox();
    final isPinned = starredSet.contains(song.id);
    return _buildOverlay(
      onDismiss: () => setState(() { showActionSheet = false; actionTarget = null; }),
      child: _sheet(
        title: '「${song.name}」',
        subtitle: '長按歌曲可進行以下操作',
        children: [
          _sheetBtn(
            isPinned ? '從常用中移出' : '⭐  加入常用（置頂顯示）',
            textColor: isPinned ? const Color(0xFF3d6fd4) : const Color(0xFF444444),
            borderColor: isPinned ? const Color(0xFF3d6fd4) : const Color(0xFFc8c8c8),
            onTap: () {
              _toggleStar(song.id);
              setState(() { showActionSheet = false; actionTarget = null; });
            },
          ),
          const SizedBox(height: 10),
          _sheetBtn('移除歌曲',
              bgColor: const Color(0xFFfdf0ee),
              textColor: const Color(0xFFc0392b),
              borderColor: const Color(0xFFf5c6be),
              onTap: () => _deleteSong(song.id)),
          const SizedBox(height: 10),
          _sheetBtn('取　消',
              bgColor: const Color(0xFFf4f4f4),
              textColor: const Color(0xFF888888),
              borderColor: const Color(0xFFe0e0e0),
              onTap: () => setState(() { showActionSheet = false; actionTarget = null; })),
        ],
      ),
    );
  }

  // ── Clear Confirm ───────────────────────────────────────────────────────────

  Widget _buildClearConfirm() => _buildOverlay(
        onDismiss: () => setState(() => showClearConfirm = false),
        child: _sheet(
          title: '清空整個歌單？',
          subtitle: '所有歌曲將被永久刪除，建議先匯出備份。',
          children: [
            _sheetBtn('確　認　清　空',
                bgColor: const Color(0xFFc0392b), textColor: Colors.white,
                onTap: () => setState(() {
                      showClearConfirm = false;
                      showPinOverlay = true;
                      pinBuffer = '';
                      pinError = false;
                    })),
            const SizedBox(height: 10),
            _sheetBtn('取　消',
                bgColor: const Color(0xFFf4f4f4), textColor: const Color(0xFF444444),
                borderColor: const Color(0xFFe0e0e0),
                onTap: () => setState(() => showClearConfirm = false)),
          ],
        ),
      );

  // ── PIN Overlay ─────────────────────────────────────────────────────────────

  Widget _buildPinOverlay() => _buildOverlay(
        onDismiss: null,
        topBorderColor: const Color(0xFFc0392b),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('請輸入確認密碼',
              style: TextStyle(fontFamily: 'Georgia', fontSize: 18,
                  fontWeight: FontWeight.w700, color: Color(0xFFc0392b))),
          const SizedBox(height: 6),
          const Text('輸入 4 位數字以確認清空',
              style: TextStyle(fontSize: 13, color: Color(0xFF888888),
                  letterSpacing: 1)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < pinBuffer.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 18, height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (filled || pinError)
                      ? const Color(0xFFc0392b) : const Color(0xFFf4f4f4),
                  border: Border.all(
                      color: (filled || pinError)
                          ? const Color(0xFFc0392b) : const Color(0xFFc8c8c8),
                      width: 2),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          _buildPinKeypad(),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() { showPinOverlay = false; pinBuffer = ''; }),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: const Color(0xFFf4f4f4),
                border: Border.all(color: const Color(0xFFe0e0e0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('取　消', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
                      color: Color(0xFF444444), letterSpacing: 1)),
            ),
          ),
        ]),
      );

  Widget _buildPinKeypad() {
    final keys = ['1','2','3','4','5','6','7','8','9','','0','⌫'];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 10,
          crossAxisSpacing: 10, childAspectRatio: 2.2),
      itemCount: 12,
      itemBuilder: (ctx, i) {
        final k = keys[i];
        if (k.isEmpty) return const SizedBox();
        return GestureDetector(
          onTap: () => k == '⌫' ? _pinDelete() : _pinInput(k),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFf4f4f4),
              border: Border.all(color: const Color(0xFFe0e0e0), width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(k,
                style: TextStyle(fontSize: k == '⌫' ? 18.0 : 22.0,
                    fontWeight: FontWeight.w700, color: const Color(0xFF111111))),
          ),
        );
      },
    );
  }

  // ── Info / Dup ──────────────────────────────────────────────────────────────

  Widget _buildInfoSheet() => _buildOverlay(
        onDismiss: () => setState(() => showInfo = false),
        child: _sheet(
          title: infoTitle, subtitle: infoSub,
          children: [
            _sheetBtn('知　道　了', bgColor: Colors.black, textColor: Colors.white,
                onTap: () => setState(() => showInfo = false)),
          ],
        ),
      );

  Widget _buildDupSheet() => _buildOverlay(
        onDismiss: () => setState(() => showDup = false),
        child: _sheet(
          title: '歌曲已存在', subtitle: dupMsg,
          children: [
            _sheetBtn('知　道　了', bgColor: Colors.black, textColor: Colors.white,
                onTap: () => setState(() => showDup = false)),
          ],
        ),
      );

  // ── Toast ───────────────────────────────────────────────────────────────────

  Widget _buildToast() => Positioned(
        bottom: 32, left: 0, right: 0,
        child: Center(
          child: AnimatedOpacity(
            opacity: toastVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                  color: Colors.black, borderRadius: BorderRadius.circular(24)),
              child: Text(toastMsg,
                  style: const TextStyle(color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
          ),
        ),
      );

  // ── Shared helpers ──────────────────────────────────────────────────────────

  Widget _buildEmpty(String line1, String line2) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(line1,
                style: const TextStyle(fontFamily: 'Georgia', fontSize: 22,
                    color: Color(0xFF888888))),
            const SizedBox(height: 8),
            Text(line2,
                style: const TextStyle(fontSize: 14, color: Color(0xFF888888),
                    letterSpacing: 1)),
          ]),
        ),
      );

  Widget _buildOverlay({
    required Widget child,
    VoidCallback? onDismiss,
    Color? topBorderColor,
  }) =>
      GestureDetector(
        onTap: onDismiss,
        child: Container(
          color: Colors.black54,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(top: BorderSide(
                    color: topBorderColor ?? Colors.black, width: 2)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: SafeArea(top: false, child: child),
            ),
          ),
        ),
      );

  Widget _sheet({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title,
            style: const TextStyle(fontFamily: 'Georgia', fontSize: 18,
                fontWeight: FontWeight.w700, color: Color(0xFF111111))),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF888888),
                letterSpacing: 1, height: 1.8)),
        const SizedBox(height: 20),
        ...children,
      ]);

  Widget _sheetBtn(
    String label, {
    Color bgColor = Colors.white,
    Color textColor = Colors.black,
    Color borderColor = Colors.transparent,
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  letterSpacing: 2, color: textColor)),
        ),
      );
}

// ── 原生平台讀取檔案位元組（條件匯入自動選擇實作）─────────────────────────────
// Web 不會呼叫此方法（_importCSV 內有 kIsWeb guard 保護）
Future<List<int>> _readFileBytes(String path) => readFileBytesImpl(path);
