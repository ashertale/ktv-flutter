# KTV 歌單 — Flutter 版

跨平台歌單管理 App，支援 **Android、iOS、Web（Chrome）** 三平台，由原始 HTML PWA 版本移植而來。

---

## 功能清單

### 瀏覽與操作
- 歌曲列表瀏覽，常用歌曲自動置頂並以藍色字體區分
- 側邊捲軸（捲動時顯示，可拖曳快速跳轉）
- 點擊歌曲進入全螢幕單曲檢視（顯示歌名 + 點歌代號，左右滑動換歌）
- 長按歌曲（持續約 1 秒，底部紅色進度條提示）可加入常用或移除

### 搜尋
- 依歌名 / 代號搜尋
- 依歌手名稱搜尋，列出該歌手所有歌曲

### 新增歌曲
- 填入歌名、點歌代號（必填）、歌手（選填）
- 自動偵測重複歌曲，不重複新增

### 介面設定（解鎖模式下）
- 字體大小調整（22–64px）
- 行距調整
- 顯示 / 隱藏歌手名稱

### 鎖定模式
- 預設開啟，隱藏所有編輯功能，適合長輩使用或展示場合
- 點擊右上角「鎖定／解鎖」切換

### 備份與還原
- **匯出 CSV**：Android 存至公開 Downloads 資料夾；Web 直接觸發瀏覽器下載
- **匯入 CSV**：支援 `pinned` 欄位還原常用狀態，自動略過重複歌曲
- **清空歌單**：需通過 PIN 碼（0000）二次確認，防止誤操作

---

## 專案結構

```
lib/
├── main.dart                 # 主程式（UI、狀態、邏輯）
├── csv_export_stub.dart      # 匯出介面宣告（條件匯入基底）
├── csv_export_web.dart       # Web 匯出實作（Blob + UTF-8 BOM 下載）
├── csv_export_native.dart    # Android/iOS 匯出實作（Downloads / Documents）
├── read_file_stub.dart       # 讀檔介面宣告（Web 空實作）
└── read_file_native.dart     # Android/iOS 讀檔實作（dart:io）

web/
└── index.html                # Web 入口，預載 Noto Sans TC 字型防止中文閃爍
```

---

## 依賴套件

| 套件 | 版本 | 用途 |
|---|---|---|
| `shared_preferences` | ^2.2.2 | 歌單、常用、設定的本地持久化 |
| `file_picker` | ^11.0.2 | CSV 匯入檔案選取（Web 用 bytes，原生用 path） |
| `path_provider` | ^2.1.2 | 取得裝置暫存 / 文件目錄（原生） |
| `downloadsfolder` | ^1.2.0 | Android API 29+ 透過 MediaStore 寫入 Downloads |
| `google_fonts` | ^6.2.1 | Noto Sans TC 字型，解決 Web 中文渲染閃爍 |

---

## 安裝與執行

```bash
# 1. 取得依賴
flutter pub get

# 2a. Web 調試
flutter run -d chrome

# 2b. Android 實機調試（需開啟 USB 偵錯）
flutter run

# 3. 打包
flutter build apk --release   # Android APK
flutter build web             # Web 靜態檔案
```

---

## Android 設定

`android/app/src/main/AndroidManifest.xml` 需包含以下權限：

```xml
<!-- 讀取外部儲存（CSV 匯入，Android 12 以下） -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
<!-- 寫入外部儲存（Downloads，Android 9 以下） -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="29"/>
```

Android 10（API 29）以上透過 `downloadsfolder` 套件使用 MediaStore，不需要 WRITE 權限。

---

## iOS 設定

在 `ios/Runner/Info.plist` 加入：

```xml
<key>NSDocumentsFolderUsageDescription</key>
<string>用於 CSV 歌單備份匯出</string>
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

---

## CSV 格式

匯出與匯入均使用 UTF-8 BOM 編碼（Excel 可直接開啟不亂碼），欄位如下：

```
name,code,artist,pinned
青花瓷,12345,周杰倫,1
告白氣球,67890,周杰倫,0
```

| 欄位 | 說明 | 必填 |
|---|---|---|
| `name` | 歌曲名稱 | ✅ |
| `code` | 點歌代號 | ✅ |
| `artist` | 歌手名稱 | ❌ |
| `pinned` | 是否為常用（1 = 是，0 = 否） | ❌ |

---

## 注意事項

- **清空歌單 PIN 碼**：`0000`
- **匯出路徑（Android）**：手機「下載」資料夾，可用任何檔案管理員存取
- **匯出路徑（iOS）**：「檔案」App → 我的 iPhone → 此 App
- **匯出路徑（Web）**：瀏覽器預設下載目錄
