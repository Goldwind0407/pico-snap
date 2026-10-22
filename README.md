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

- **四格拍貼**：共 20 款模板，分成精選、可愛、經典、生日、應援五類。
  - **精選 8 款**是用 Gemini 生成的插畫模板，貓咪、草莓等裝飾會壓在照片邊緣，跟實體拍貼機印出來的一樣。
  - **其他 12 款**是程式繪製的自訂模板，之後可以擴充成讓使用者自己設計。每款可以設定以下項目：
    - 外框：純色、漸層，或點點、貓掌、碎紙花、條紋圖案
    - 照片格形狀：方形、圓角、雲朵、波浪邊
    - 底部樣式：手寫字、PICO SNAP 標誌加日期、大標題
    - 印在模板上的貼紙和對話泡泡
    - 黑白照片
- **拍立得拼貼**：4 張拍立得斜放成 Z 字形，貼著紙膠帶，下面可以寫手寫字。可以切換比例（9:16、1:1、4:5、3:4）和背景色。
- **貼紙裝飾**：雙色格紋背景和對話泡泡。照片可以去背，去好背的人或東西會加上白色描邊，像真的貼紙一樣。

### 儲存作品

- 按「儲存」會輸出高畫質圖片（最長邊約 3000 像素），存到手機相簿的「PICO SNAP」相簿。
- 存檔時會自動隱藏「tap to add」、選取框和貼紙的把手。

### 去背

- 會先用**手機內建 AI** 去背：iPhone 用 Vision（iOS 17 以上可以切任何主體，iOS 15、16 只能切人像），Android 用 ML Kit。
- AI 不能用時（模擬器、沒有 Google Play 服務、或認不出來），會**自動改用手動去背**。手動去背用的是 GrabCut 演算法，依照顏色和邊緣來判斷，不需要任何模型。
- 使用者也可以自己選：
  - 「AI 去背」或「手動去背」：重新去背一次
  - 長按想留下的東西，可以只選那一個
  - 「擦掉」和「補回」筆刷，可以調整粗細；搭配「貼齊邊緣」（畫一筆就會沿著邊緣切），或關掉它自由塗抹
  - 復原和重做
- 去背可以用在兩個地方：
  - **貼紙裝飾模式**：把照片裡的主體去背
  - **貼紙面板的「📷 我的」**：任何照片去背後都能變成貼紙，貼在任何模式上；按貼紙角落的 × 可以刪除（目前只存在記憶體裡，關掉 App 就會消失）

### 貼紙

- 三種模式都可以加貼紙，包含 16 款手繪貼紙和一些 emoji。
- 貼紙可以拖曳、雙指縮放和旋轉，也可以拖右下角的把手調整大小和角度；按右上角的按鈕可以左右翻轉。
- 可以刪除，也可以復原上一步。

### 尚未完成

- 相機拍照
- 作品集與本機存檔（包含自己做的照片貼紙）
- 照片在格子裡移動、縮放（現在會自動置中裁切）
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
| `lib/widgets/sticker_item.dart` | 可拖曳、縮放、旋轉、翻轉的貼紙 |
| `lib/cutout/` | 去背：去背頁面、手機內建 AI、GrabCut、筆刷工具（移植自 color_pic） |
| `lib/services/photo_save_service.dart` | 存到相簿 |
| `test/` | 版面、去背、儲存的測試 |
| `assets/stickers/` | 手繪貼紙 PNG |
| `assets/templates/` | 精選插畫模板（照片格已去背的 WebP） |
| `assets/samples/` | 首頁用的範例照片 |
| `assets/fonts/` | Nunito、Caveat 字型 |
| `design/prompts/` | Gemini 提示詞 |
| `ios/`、`codemagic.yaml` | iPhone 版設定與雲端建置 |

## 素材來源

- 介面示意圖、手繪貼紙和精選模板都是用 Gemini 生成的，提示詞放在 `design/prompts/`。
- Gemini 生成的原始圖（`design/mockups/`、`design/templates/`）只留在本機，不上傳；App 用的是處理過的版本，放在 `assets/`。
- `assets/samples/` 的人物照片是從 AI 示意圖裁切下來的，**只是佔位用**。正式發布前請換成有使用權的照片。
- 實體拍貼機的參考照片（`design/拍貼機範本/`）有版權，只留在本機當設計參考，已加入 `.gitignore`，不會上傳。
- 字型：[Nunito](https://fonts.google.com/specimen/Nunito)、[Caveat](https://fonts.google.com/specimen/Caveat)，兩者都採用 SIL Open Font License。

## 執行方式

1. 安裝 [Flutter](https://docs.flutter.dev/get-started/install)。
2. 執行 `flutter pub get`。
3. 執行 `flutter run`。

## App 識別碼

iPhone 和 Android 都是 `com.goldwind.picosnap`。上架之後就不能再改。

## 建置 iPhone 版（沒有 Mac 也可以）

用 [Codemagic](https://codemagic.io) 在雲端建置，設定寫在 `codemagic.yaml`：

1. 用 GitHub 帳號登入 Codemagic，加入 `pico-snap` 這個倉庫。
2. 選 **ios-unsigned** 工作流程，分支選 `main`，按 **Start new build**。只有手動按才會建置，推送程式碼不會自動跑，可以節省免費額度。
3. 建好之後，在 Artifacts 下載 `pico_snap-unsigned.ipa`。
4. 在 Windows 用 [Sideloadly](https://sideloadly.io) 以自己的 Apple ID 簽名，裝到 iPhone。
   - 用免費 Apple ID 安裝的 App，7 天後要重新安裝一次。
   - 第一次打開前，要先到 iPhone 的「設定 → 一般 → VPN 與裝置管理」信任自己的 Apple ID。

### iOS 設定重點

- Bundle ID：`com.goldwind.picosnap`，最低支援 iOS 15，只支援 iPhone，只能直式使用。
- `Info.plist` 已經寫好相簿、相機、存到相簿的權限說明。少了這些說明，iOS 會直接讓 App 閃退。
- 去背用的 Vision 程式寫在 `AppDelegate.swift`（不另開新檔，因為新的 .swift 檔要加進 Xcode 專案檔才會編譯）。模擬器上 Vision 的主體去背不能用，要用實機測。
- 已經採用 UIScene（`SceneDelegate.swift`）。iOS 27 起，沒有採用 UIScene 的 App 一打開就會被系統終止。
