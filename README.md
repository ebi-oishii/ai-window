# AI Window

macOS のバックグラウンドで動く AI アシスタント。**右クリックドラッグ** で出るパネルに自然言語で指示を出すと、AI (Claude / Gemini) が tool_use ループで実際に macOS を操作します。

ブラウザを開く・音量を変える・Gmail で検索・最近のファイルを開く・Spotlight で PC 内検索・AppleScript で Notes やリマインダーを作る・画面のスクリーンショットを見せて翻訳させる、まで全部一つのパネルから。

![Detroit-style HUD panel](https://placeholder)

---

## 主な特徴

- **右クリックドラッグで起動** — 画面のどこでも対角線にドラッグするとパネルが出る
- **2 つの UI モード**
  - 通常モード: Detroit BH 風の紫アクセント・ダーク HUD
  - 簡単モード: ライトテーマ + AI が選択肢ボタンを提示する対話的フロー（初心者向け）
- **学習する**: 使うたびに「次回似た指示で役立つルール」を AI 自身が抽出して永続化（最大 30 件）
- **PC を把握**: インストール済みアプリ一覧をキャッシュ、前面アプリ名 + ウィンドウタイトルを毎ターン自動でコンテキストに付与
- **マルチモーダル**: 📷 SCREEN トグルで送信時に画面全体を AI に同送（Claude / Gemini 両対応）
- **/help` ボタン**: AI 自身が現在使える機能を初心者向けに説明
- **ショートカット**: `/gmail` `/calendar` `/drive` などのチップトグルで操作対象を固定。よく開く新規ドメインは自動学習されてチップに昇格

---

## セットアップ

### 1. ビルド

```sh
git clone https://github.com/ebi-oishii/ai-window.git
cd ai-window
make bundle
```

`AIWindow.app` が生成されます。Xcode は不要、Swift Package Manager + Makefile のみ。

### 2. Accessibility 権限を許可

CGEventTap で右クリックドラッグを監視するため必須です。

```sh
open AIWindow.app
```

→ メニューバー ✨ アイコン → 「アクセシビリティを許可する...」→ システム設定で AIWindow を + で追加 → ON。

`make bundle` で再ビルドするたび ad-hoc 署名の cdhash が変わるので、TCC エントリの付け直しが必要になることがあります。詰まったら：

```sh
tccutil reset Accessibility com.aiwindow.app
```

→ 再度許可。

### 3. API キー設定

メニューバー ✨ → API キー → Claude または Gemini をクリック → Keychain に保存。
無料運用なら Gemini (`gemini-2.5-flash-lite`, 30 RPM / 1000 RPD) がおすすめ。

API キー入手:
- Gemini: <https://aistudio.google.com/apikey>
- Claude: <https://console.anthropic.com/>

---

## 使い方

### パネルを出す

画面のどこでも、**右クリックを押しながら 20px 以上ドラッグ** → 選択した矩形領域にパネルが現れます。コンテキストメニューは抑制されます。

### 通常モード

紫アクセントの HUD パネル。

| 要素 | 役割 |
|---|---|
| 入力欄 | 自然言語で指示。Enter で送信、Esc で閉じる |
| `▸ EXECUTE` | 実行ボタン |
| `/help` チップ | AI が「何ができるか」を説明 |
| `📷 SCREEN` チップ | オンで送信時に画面全体のスクリーンショットを AI に同送 |
| `/gmail` `/calendar` ... チップ | 操作対象をプレフィックスとして固定。複数選択可 |
| `▸ READY` | ステータス（PROCESSING / DONE / ERROR） |
| 右上 ✕ | 閉じる |

**自動挙動**:
- 90 秒無操作で自動的に閉じる
- フォーカスが外れると半透明 (α=0.45)、戻ると不透明
- 成功完了後 6 秒で自動 dismiss

### 簡単モード

ライトテーマで、対話的にボタンを押して進めるフロー。AI には「初心者向けに用語を使わず、曖昧な指示は `suggest_actions` ツールで選択肢ボタンを提示して聞き返す」と指示が入っています。

起動時に表示されるスターターボタン:
- 📧 メールを書く
- 📅 今日の予定を見る
- 🔉 音量を変える
- 📁 最近のファイル
- 🌐 ネットで調べる

ボタンを押すとそのプロンプトが送信され、AI の応答に応じて次の選択肢ボタンが提示されます。

### モード切替

メニューバー ✨ → モード → 通常モード / 簡単モード。次回パネル表示時から新モードになります。

---

## できること（指示例）

| カテゴリ | 例 |
|---|---|
| アプリ操作 | 「Chrome を開いて」「Cursor を起動」「ターミナルを前面に」 |
| Web | 「Gmail で田中さんからのメールを検索」「YouTube で lo-fi を探して」「最新の AI ニュースを調べて」 |
| ファイル | 「今ダウンロードしたファイルを開いて」「請求書の PDF を探して」「Desktop の最新ファイルを Preview で」 |
| macOS スクリプタブル | 「Notes に "買い物" メモを作って」「リマインダーに "明日 9 時に〇〇" を追加」 |
| クリップボード | 「クリップボードの英文を訳して」「下書きをコピーしておいて」 |
| システム | 「音量を 30 に」「音量を少し下げて」 |
| 画面理解 (📷 ON) | 「画面に映ってる英語を訳して」「今のエラーを説明して」 |

---

## メニューバー

✨ アイコンからすべて操作できます：

- **権限状態** (Accessibility OK / NG)
- **モード** 切替
- **API キー** 設定（Keychain 保存）
- **学習済みルール** 一覧 / 全削除
- **アプリを再起動 / 終了**

---

## 自動学習

各タスク完了後、バックグラウンドで反省 LLM 呼び出しが走り、「次回似た指示で役立つルール」を 1 つ抽出して `~/Library/Application Support/AIWindow/learned_rules.json` に永続化します。

例えば「田中さんからのメールを検索」→ Gmail のホームだけ開いた失敗が起きた場合、次回までに「Gmail で人物検索なら `https://mail.google.com/mail/u/0/#search/from%3A<人物>` を組み立てる」というルールが追加され、以降は正しく検索画面まで飛ぶようになります。

レート制限 (429) などで反省が失敗しても黙って捨てるので UI には影響しません。

---

## 必要な権限

| 権限 | 用途 | 取得タイミング |
|---|---|---|
| Accessibility | 右クリックドラッグ監視 (CGEventTap) | 初回起動時にダイアログ |
| Screen Recording | 📷 スクリーンショット同送 | 📷 トグル初回 ON 時 |
| Files & Folders (Downloads/Desktop/Documents) | 最近ファイル取得 | 初回アクセス時 |

---

## 開発

```sh
make build    # swift build -c release のみ
make bundle   # build + .app パッケージ化 + ad-hoc 署名
make run      # bundle + 直接実行（env vars を継承するので開発時便利）
make clean    # .build と AIWindow.app を削除
```

`Sources/AIWindow/` フラット構成。`Package.swift` は SPM、最小ターゲット macOS 13。

主要ファイル:
- `RightClickDragMonitor.swift` — CGEventTap での右クリックドラッグ監視
- `InputPanelWindow.swift` — 通常モード UI
- `EasyPanelWindow.swift` — 簡単モード UI
- `ActionDispatcher.swift` — tool_use ループの中核
- `ToolDefinitions.swift` — Claude / Gemini 両プロバイダのツールスキーマ + system prompt
- `ClaudeClient.swift` / `GeminiClient.swift` — マルチモーダル対応 HTTP クライアント
- `ShortcutRegistry.swift` — `/gmail` 等のチップ管理 + 自動学習
- `LearnedRulesStore.swift` / `Reflector.swift` — 反省ループによる自己改善
- `AppInventory.swift` / `FileExecutor.swift` — PC 把握系
- `Theme.swift` — Detroit カラー / フォントトークン

---

## ライセンス

未設定（個人プロジェクト）。
