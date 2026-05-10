# KTV 歌單 — Flutter 版

## 架構說明

原始 HTML 為單頁 PWA，所有邏輯與 UI 集中在一份 `index.html`。
Flutter 版以單一 `main.dart` 重現全部功能，結構對照如下：

| HTML 模組 | Flutter 對應 |
|---|---|
| `localStorage` 持久化 | `shared_preferences` |
| 4 個分頁（browse / search / add / settings） | `_buildBrowsePage / _buildSearchPage / _buildAddPage / _buildSettingsPage` |
| 全螢幕單曲檢視 | `_buildSingleOverlay()` |
| 長按動作 Sheet | `_buildActionSheet()` |
| 刪除確認 / PIN 保護 | `_buildClearConfirm()` / `_buildPinOverlay()` |
| 重複提示 / 通用訊息 | `_buildDupSheet()` / `_buildInfoSheet()` |
| Toast | `_buildToast()` |
| CSV 匯出/匯入 | `_exportCSV()` / `_importCSV()` |

## 功能清單（完全重現）

- ✅ 歌曲列表瀏覽（常用置頂、藍字區分）
- ✅ 鎖定 / 解鎖模式（長輩友善；鎖定時隱藏所有編輯功能）
- ✅ 全螢幕單曲檢視（左右滑動 / 按鈕換歌）
- ✅ 搜尋（歌曲名稱 / 代號 / 歌手兩種模式）
- ✅ 新增歌曲（歌名 + 代號 + 歌手）
- ✅ 長按操作選單（加入常用 / 移除歌曲）
- ✅ 常用篩選（只顯示常用歌曲）
- ✅ 字體大小 / 行距調整（22–64px）
- ✅ 顯示 / 隱藏歌手名稱
- ✅ CSV 匯出備份
- ✅ CSV 匯入還原（支援 pinned 欄位）
- ✅ 清空歌單（含 PIN 0000 二次確認防誤觸）
- ✅ 重複歌曲偵測
- ✅ Toast 提示
- ✅ 設定持久化（字體、間距、顯示偏好）

## 安裝與執行

### 依賴套件

```yaml
shared_preferences: ^2.2.2   # 取代 localStorage
file_picker: ^6.1.1           # 取代 <input type="file">
path_provider: ^2.1.2         # 取得裝置文件目錄（CSV 匯出路徑）
```

### 執行步驟

```bash
# 1. 進入專案目錄
cd ktv_songlist

# 2. 取得依賴
flutter pub get

# 3. 執行 (連接手機或開啟模擬器)
flutter run
```

### iOS 額外設定

在 `ios/Runner/Info.plist` 加入：
```xml
<key>NSDocumentsFolderUsageDescription</key>
<string>用於 CSV 歌單備份匯出</string>
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

### Android 額外設定

`AndroidManifest.xml` 已包含於 `android/app/src/main/AndroidManifest.xml`。

---

## PIN 密碼

預設清空密碼：**0000**
（對應原始 HTML 的 `const PIN_CODE = '0000'`）
