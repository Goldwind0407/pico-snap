# PICO SNAP

可愛的韓系拍貼 App，用 Flutter 製作，可以做四格拍貼、拍立得拼貼和貼紙裝飾。所有資料都存在手機本機，不需要登入。

## 目前進度

目前是**介面原型**，整體是粉嫩的照片日記風格：奶油色紙張、咖啡色細描邊、紙膠帶和手寫字。

### 首頁

- 拼貼風格的主視覺卡片，加上「開始製作」按鈕
- 三種玩法入口：四格拍貼、拍立得、貼紙裝飾
- 「今日風格」橫向模板列表
- 底部導覽列，中間有凸起的相機按鈕

### 編輯器

- **四格拍貼**：12 款模板，分成可愛、經典、生日、應援四類。每款模板可以設定以下項目：
  - 外框：純色、漸層，或點點、貓掌、碎紙花、條紋圖案
  - 照片格形狀：方形、圓角、雲朵、波浪邊
  - 底部樣式：手寫字、PICO SNAP 標誌加日期、大標題
  - 印在模板上的貼紙和對話泡泡
  - 黑白照片
- **拍立得拼貼**：4 張拍立得斜放成 Z 字形，貼著紙膠帶，下面可以寫手寫字。可以切換比例（9:16、1:1、4:5、3:4）和背景色。
- **貼紙裝飾**：雙色格紋背景、波浪形的白色描邊相框，還有對話泡泡。

### 貼紙

- 三種模式都可以加貼紙，包含 16 款手繪貼紙和一些 emoji。
- 貼紙可以拖曳、雙指縮放和旋轉，也可以用角落的把手調整大小和角度。
- 可以刪除，也可以復原上一步。

### 尚未完成

- 高畫質輸出和儲存到相簿（現在按「儲存」只會跳出提示）
- 相機拍照
- 作品集與本機存檔
- 真正的照片去背
- 畫筆、濾鏡

## 專案結構

| 路徑 | 內容 |
|---|---|
| `lib/main.dart` | App 進入點與主題 |
| `lib/theme.dart` | 配色、手寫字型樣式 |
| `lib/models.dart` | 模板、貼紙、格紋等資料 |
| `lib/home_screen.dart` | 首頁 |
| `lib/editor_screen.dart` | 編輯器（四格、拍立得、貼紙三種模式） |
| `lib/widgets/frames.dart` | 拍貼條、拍立得、紙膠帶、格紋等元件 |
| `lib/widgets/sticker_item.dart` | 可拖曳、縮放、旋轉的貼紙 |
| `assets/stickers/` | 手繪貼紙 PNG |
| `assets/samples/` | 首頁用的範例照片 |
| `assets/fonts/` | Nunito、Caveat 字型 |
| `design/` | 設計參考：Gemini 提示詞、示意圖 |

## 素材來源

- 介面示意圖和手繪貼紙是用 Gemini 生成的，提示詞放在 `design/prompts/`；拍貼模板的提示詞在 `design/prompts/templates/`，生成的圖放在 `design/templates/`。
- `assets/samples/` 的人物照片是從 AI 示意圖裁切下來的，**只是佔位用**。正式發布前請換成有使用權的照片。
- 實體拍貼機的參考照片（`design/拍貼機範本/`）有版權，只留在本機當設計參考，已加入 `.gitignore`，不會上傳。
- 字型：[Nunito](https://fonts.google.com/specimen/Nunito)、[Caveat](https://fonts.google.com/specimen/Caveat)，兩者都採用 SIL Open Font License。

## 執行方式

1. 安裝 [Flutter](https://docs.flutter.dev/get-started/install)。
2. 如果還沒有平台資料夾（`android/`、`ios/` 等），先執行 `flutter create .`。
3. 執行 `flutter pub get`。
4. 執行 `flutter run`。
