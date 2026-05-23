import Foundation

enum Tools {
    /// Composed at call time so newly-learned rules and the user's current
    /// UI mode are picked up immediately.
    static var systemPrompt: String {
        basePrompt + modeSection + LearnedRulesStore.shared.promptSection
    }

    /// Mode-specific behavioral guidance appended to the base prompt.
    private static var modeSection: String {
        switch UIMode.current {
        case .normal:
            return ""
        case .easy:
            return """


            ===== 簡単モード（重要）=====
            現在のユーザーは PC 初心者です。以下を必ず守ってください:

            1. 専門用語を避ける。
               - NG: 「URL を構築」「ターミナル」「コマンド」「メタデータ」「シェル」「リダイレクト」「クエリ」
               - OK: 「リンク」「ファイル」「ボタン」「アプリ」程度
               - ツール名（open_url / search_files / run_applescript など）は応答に絶対に出さない。ユーザーには「やったこと」だけを伝える。

            2. 指示が曖昧なときは絶対に推測実行せず、suggest_actions で 2〜4 個の選択肢を提示して聞き返す。
               - ユーザー「メールしたい」→ suggest_actions(
                   [{"label": "受信箱を開く", "prompt": "Gmail の受信箱を開いて"},
                    {"label": "新しいメールを書く", "prompt": "Gmail で新規メール作成画面を開いて"},
                    {"label": "特定の人を検索", "prompt": "Gmail で誰からのメールを探しますか？と聞いて"}]
                 )
               - ユーザー「資料探して」→ どこで何を、を聞き返す

            3. 1 ステップで終わらない流れの途中も、毎回 suggest_actions で「次は？」候補を出す。
               - 例: メール開いた直後 → "返信する" / "削除する" / "別のメールを見る"
               - 例: ファイル検索結果出した → "1 番を開く" / "別のキーワードで再検索" / "もうやめる"

            4. 取り返しのつかない操作（削除・送信・支払い・大きな設定変更）の前は必ず suggest_actions で確認を出す。
               - "実行する" / "やめる" の 2 択ボタン。

            5. 応答テキスト本体は短く優しい日本語で 1〜3 文。長い説明や箇条書きは避ける。読み上げても自然な口調で。
               - 「Gmail を開いたよ」「音量を 50% にしたよ」のような完了報告を必ず 1 文添える。

            6. 失敗した時は何が起きたか平易に説明し、suggest_actions で「もう一度試す」「別の方法」「やめる」の選択肢を出す。

            7. ユーザーが「次は？」「これでいい？」のようにこちらに判断を委ねた時は、suggest_actions で具体的な行動候補を出す。テキストだけで「いかがでしょうか」と返すのは NG。
            """
        }
    }

    private static let basePrompt = """
    あなたはmacOSを操作するAIアシスタントです。
    ユーザーの自然言語の指示を理解し、適切なツールを呼び出してください。

    ツール選択の最重要ルール:
    - 「<アプリ名> を開いて/起動して」と言われたら open_app を使うこと。
      例: 「Chrome を開いて」「Cursor を開いて」「Slack 起動」「ターミナル開いて」
      → URL を作って open_url を呼んではいけない。
    - 「<アプリ名> で <Webサービス> を開いて」と言われたら open_url の browser パラメータを使う。
      例: 「Chrome で Gmail 開いて」→ open_url(url=..., browser="Google Chrome")
    - ブラウザ名なしで「Gmail 開いて」など Web サービスだけ言われたら open_url(url=...) を呼ぶ（デフォルトブラウザ）。
    - 音量操作は control_volume。
    - 「今ダウンロードした〜」「さっき保存した〜」「最近の〜」のような文脈依存ファイル指示は
      まず list_recent_files で候補を取得 → 適切な 1 件を選んで open_file。
      例: 「今ダウンロードしたファイル開いて」→ list_recent_files(location="downloads", limit=1) → open_file(path=<返ってきたパス>)
    - 「<キーワード>のファイルを開いて」のように内容で探したい場合や、
      list_recent_files で見つからなかった場合は search_files で PC 全体を検索 → open_file。
      例: 「請求書のPDF開いて」→ search_files(query="請求書", limit=5) → 適切な 1 件を選んで open_file
    - 任意の絶対パス / ~ 始まりのパスを開く場合も open_file を使う。
    - 「クリップボードの〜」「コピーした〜」と言われたら read_clipboard、「コピーしておいて」「クリップボードに〜」なら write_clipboard。
    - 「最新の〜」「<トピック>を調べて」「ググって」と言われたら web_search で上位結果を取得 → 必要なら open_url で個別ページへ。
    - Notes/リマインダー/Music/Finder の細かい操作・壁紙変更・メール下書き作成など、専用ツールがない macOS スクリプタブル操作は run_applescript で組み立てる。
      例:「『買い物』というメモを作って」→ tell application "Notes" to make new note with properties {name:"買い物", body:""}

    前面コンテキスト:
    - ユーザー入力の冒頭に "[現在前面のアプリ: <X> — \"<title>\"]" が自動付与される場合があります。
      これは「現在ユーザーが見ている画面のアプリ」のヒントなので、指示の対象が曖昧なときは
      この前面アプリを優先解釈する。例:「ここに〇〇を入力して」と言われたら前面アプリへの入力。

    主なWebサービスのURL:
    - Gmail: https://mail.google.com
    - Google カレンダー: https://calendar.google.com
    - Google ドライブ: https://drive.google.com
    - YouTube: https://youtube.com
    - Google: https://www.google.com
    - Slack: https://app.slack.com
    - GitHub: https://github.com
    - Twitter/X: https://x.com
    - ChatGPT: https://chat.openai.com
    - Notion: https://notion.so

    Deep link（検索・特定の画面に直接飛ぶURL — クエリは必ずパーセントエンコード）:
    - Gmail 検索: https://mail.google.com/mail/u/0/#search/<query>
      - 「<人物>からのメール」→ クエリは from:<人物>
      - 「<語句>を含むメール」→ クエリは <語句>
      - 例:「田中さんからのメール」→ #search/from%3A%E7%94%B0%E4%B8%AD
    - Gmail 新規作成: https://mail.google.com/mail/u/0/?fs=1&tf=cm
    - Google カレンダー検索: https://calendar.google.com/calendar/r/search?q=<query>
    - Google Drive 検索: https://drive.google.com/drive/search?q=<query>
    - YouTube 検索: https://www.youtube.com/results?search_query=<query>
    - Google 検索: https://www.google.com/search?q=<query>
    - GitHub 検索: https://github.com/search?q=<query>
    - X 検索: https://x.com/search?q=<query>

    重要: 「<サービス>で<X>を検索」「<サービス>で<X>を探して」と言われたら、
    ホーム画面ではなく上記の deep link を組み立てて open_url を呼ぶこと。
    クエリ中の日本語・記号・スペースはすべて URL エンコードする。

    出力:
    - ツール実行後、実行内容を1〜2文の日本語で簡潔に報告する
    - URLはhttps://で始まる完全な形式を使用する
    """

    // Claude (Anthropic) format: flat array, schema key is "input_schema"
    static let claudeDefinitions: [[String: Any]] = [
        [
            "name": "open_app",
            "description": "macOSのアプリケーションを起動します。「<アプリ> を開いて/起動して」と言われたら必ずこのツールを使うこと（URLを作ってopen_urlを呼んではいけない）。デフォルトでは新しいウィンドウを開きます。",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "アプリ名（例: \"Google Chrome\", \"Cursor\", \"Slack\", \"Terminal\"）"] as [String: Any],
                    "new_window": ["type": "boolean", "description": "新しいウィンドウを開くかどうか。省略時はtrue。「前面に」「フォーカス」のような指示の時のみfalseにする"] as [String: Any],
                ],
                "required": ["name"],
            ] as [String: Any],
        ],
        [
            "name": "list_recent_files",
            "description": "指定フォルダの最新ファイルを更新日時の新しい順に一覧します。「今ダウンロードした」「さっき保存した」のような文脈で候補を得るのに使用。",
            "input_schema": [
                "type": "object",
                "properties": [
                    "location": ["type": "string", "enum": ["downloads", "desktop", "documents", "home"], "description": "対象フォルダ"] as [String: Any],
                    "limit": ["type": "integer", "description": "返す件数。省略時は5。「今ダウンロードした」なら1で良い"] as [String: Any],
                ],
                "required": ["location"],
            ] as [String: Any],
        ],
        [
            "name": "open_file",
            "description": "ファイルを開きます。絶対パス、または ~/ で始まるパスを指定。app を省略するとファイルタイプのデフォルトアプリで開きます。",
            "input_schema": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "ファイルの絶対パスまたは ~/... 形式"] as [String: Any],
                    "app": ["type": "string", "description": "オプション。指定アプリで開きたい場合のアプリ名"] as [String: Any],
                ],
                "required": ["path"],
            ] as [String: Any],
        ],
        [
            "name": "search_files",
            "description": "Spotlightで PC 内のファイルを検索します。list_recent_files で目的のファイルが見つからなかった場合のフォールバックとして使う。デフォルトはファイル名・本文・メタデータ全てを検索。",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "検索クエリ（例: \"請求書\", \"report.pdf\"）"] as [String: Any],
                    "name_only": ["type": "boolean", "description": "trueならファイル名のみで検索。省略時はfalse（本文・メタデータも含む）"] as [String: Any],
                    "location": ["type": "string", "enum": ["downloads", "desktop", "documents", "home"], "description": "オプション。検索対象を特定フォルダ配下に限定"] as [String: Any],
                    "limit": ["type": "integer", "description": "返す件数。省略時は10"] as [String: Any],
                ],
                "required": ["query"],
            ] as [String: Any],
        ],
        [
            "name": "read_clipboard",
            "description": "現在のクリップボードのテキスト内容を読み取ります。「クリップボードの〜を訳して」「コピーしたやつを〜」などで使用。",
            "input_schema": ["type": "object", "properties": [:] as [String: Any]] as [String: Any],
        ],
        [
            "name": "write_clipboard",
            "description": "指定したテキストをクリップボードに書き込みます。「コピーしておいて」「クリップボードに〜を入れて」などで使用。",
            "input_schema": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "コピーするテキスト"] as [String: Any],
                ],
                "required": ["text"],
            ] as [String: Any],
        ],
        [
            "name": "run_applescript",
            "description": "任意の AppleScript を実行します。Notes/リマインダー/Finder/Music/壁紙/メール作成下書きなど、macOSのスクリプタブルアプリの操作は基本これで行います。他のツール（open_app/open_url/list_recent_files等）で目的が達成できる場合はそちらを優先。失敗時は stderr が返るので適切にハンドリングしてください。",
            "input_schema": [
                "type": "object",
                "properties": [
                    "script": ["type": "string", "description": "実行する AppleScript ソース。例: 'tell application \"Notes\" to make new note with properties {name:\"買い物\", body:\"卵\"}'"] as [String: Any],
                ],
                "required": ["script"],
            ] as [String: Any],
        ],
        [
            "name": "suggest_actions",
            "description": "ユーザーに次の操作の選択肢を提示します。簡単モードのときに有効で、ユーザーが何をしたいか曖昧・迷っている可能性がある時、または1ステップで完結しない流れの途中で、2〜5個の次の操作候補をボタンとして提示する。各候補は label（ボタン表示文 12 文字程度）と prompt（ボタン押下時に AI に送る指示文）を持つ。テキスト応答と併用可。",
            "input_schema": [
                "type": "object",
                "properties": [
                    "actions": [
                        "type": "array",
                        "description": "2〜5個の選択肢配列",
                        "items": [
                            "type": "object",
                            "properties": [
                                "label": ["type": "string", "description": "ボタン表示文（短く）"] as [String: Any],
                                "prompt": ["type": "string", "description": "ボタン押下時に送られる指示文"] as [String: Any],
                            ] as [String: Any],
                            "required": ["label", "prompt"],
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["actions"],
            ] as [String: Any],
        ],
        [
            "name": "web_search",
            "description": "DuckDuckGoでWebを検索し、上位N件のタイトル・URL・スニペットを返します。最新情報や調べ物に使用。検索結果のURLを開きたい場合は別途 open_url を呼ぶ。",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "検索クエリ"] as [String: Any],
                    "limit": ["type": "integer", "description": "返す件数。省略時は5"] as [String: Any],
                ],
                "required": ["query"],
            ] as [String: Any],
        ],
        [
            "name": "open_url",
            "description": "URLをブラウザで開きます。browserを省略するとデフォルトブラウザで開きます。",
            "input_schema": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "開くURL（例: https://mail.google.com）"] as [String: Any],
                    "browser": ["type": "string", "description": "オプション。特定のブラウザで開きたい場合のアプリ名（例: \"Google Chrome\", \"Safari\", \"Arc\"）"] as [String: Any],
                ],
                "required": ["url"],
            ] as [String: Any],
        ],
        [
            "name": "control_volume",
            "description": "macOSのシステム音量を制御します",
            "input_schema": [
                "type": "object",
                "properties": [
                    "action": [
                        "type": "string",
                        "enum": ["set", "increase", "decrease", "mute", "unmute"],
                        "description": "set=絶対値指定, increase=増加, decrease=減少, mute=消音, unmute=消音解除",
                    ] as [String: Any],
                    "value": [
                        "type": "integer",
                        "description": "action=set: 0〜100の値。increase/decrease: 変化量（1〜30推奨）",
                    ] as [String: Any],
                ],
                "required": ["action"],
            ] as [String: Any],
        ],
    ]

    // Gemini format: all functions inside one object under "function_declarations"
    static let geminiDefinitions: [[String: Any]] = [
        [
            "function_declarations": [
                [
                    "name": "open_app",
                    "description": "macOSのアプリケーションを起動します。「<アプリ> を開いて/起動して」と言われたら必ずこれを使い、URLを作ってopen_urlを呼んではいけません。デフォルトでは新しいウィンドウを開きます。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "name": [
                                "type": "string",
                                "description": "アプリ名（例: Google Chrome, Cursor, Slack, Terminal）",
                            ] as [String: Any],
                            "new_window": [
                                "type": "boolean",
                                "description": "新しいウィンドウを開くかどうか。省略時はtrue。「前面に」「フォーカス」のような指示の時のみfalse",
                            ] as [String: Any],
                        ],
                        "required": ["name"],
                    ] as [String: Any],
                ] as [String: Any],
                [
                    "name": "list_recent_files",
                    "description": "指定フォルダの最新ファイルを更新日時の新しい順に一覧します。「今ダウンロードした」「さっき保存した」のような文脈で候補を得るのに使用。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "location": ["type": "string", "description": "downloads / desktop / documents / home のいずれか"] as [String: Any],
                            "limit": ["type": "integer", "description": "返す件数。省略時は5"] as [String: Any],
                        ],
                        "required": ["location"],
                    ] as [String: Any],
                ] as [String: Any],
                [
                    "name": "open_file",
                    "description": "ファイルを開きます。絶対パス、または ~/ で始まるパスを指定。app を省略するとデフォルトアプリで開きます。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string", "description": "ファイルの絶対パスまたは ~/... 形式"] as [String: Any],
                            "app": ["type": "string", "description": "オプション。指定アプリで開きたい場合のアプリ名"] as [String: Any],
                        ],
                        "required": ["path"],
                    ] as [String: Any],
                ] as [String: Any],
                [
                    "name": "search_files",
                    "description": "Spotlightで PC 内のファイルを検索します。list_recent_files で目的のファイルが見つからなかった時のフォールバック。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": ["type": "string", "description": "検索クエリ"] as [String: Any],
                            "name_only": ["type": "boolean", "description": "trueならファイル名のみで検索。省略時はfalse"] as [String: Any],
                            "location": ["type": "string", "description": "オプション。downloads / desktop / documents / home に限定"] as [String: Any],
                            "limit": ["type": "integer", "description": "返す件数。省略時は10"] as [String: Any],
                        ],
                        "required": ["query"],
                    ] as [String: Any],
                ] as [String: Any],
                [
                    "name": "read_clipboard",
                    "description": "現在のクリップボードのテキスト内容を読み取ります。",
                    "parameters": ["type": "object", "properties": [:] as [String: Any]] as [String: Any],
                ] as [String: Any],
                [
                    "name": "write_clipboard",
                    "description": "指定したテキストをクリップボードに書き込みます。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "text": ["type": "string", "description": "コピーするテキスト"] as [String: Any],
                        ],
                        "required": ["text"],
                    ] as [String: Any],
                ] as [String: Any],
                [
                    "name": "run_applescript",
                    "description": "任意の AppleScript を実行します。Notes/リマインダー/Finder/Music/壁紙/メール下書きなどスクリプタブル操作はこれで。他ツールで達成できる場合はそちらを優先。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "script": ["type": "string", "description": "AppleScript ソース"] as [String: Any],
                        ],
                        "required": ["script"],
                    ] as [String: Any],
                ] as [String: Any],
                [
                    "name": "suggest_actions",
                    "description": "ユーザーに次の操作候補をボタンとして提示します。簡単モード時、ユーザーが迷っている / 流れの途中の選択場面で 2〜5 個提示。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "actions": [
                                "type": "array",
                                "description": "2〜5個の選択肢配列",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "label": ["type": "string", "description": "ボタン表示文（短く）"] as [String: Any],
                                        "prompt": ["type": "string", "description": "押下時に送る指示文"] as [String: Any],
                                    ] as [String: Any],
                                    "required": ["label", "prompt"],
                                ] as [String: Any],
                            ] as [String: Any],
                        ] as [String: Any],
                        "required": ["actions"],
                    ] as [String: Any],
                ] as [String: Any],
                [
                    "name": "web_search",
                    "description": "DuckDuckGoでWebを検索し、上位N件のタイトル・URL・スニペットを返します。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": ["type": "string", "description": "検索クエリ"] as [String: Any],
                            "limit": ["type": "integer", "description": "返す件数。省略時は5"] as [String: Any],
                        ],
                        "required": ["query"],
                    ] as [String: Any],
                ] as [String: Any],
                [
                    "name": "open_url",
                    "description": "URLをブラウザで開きます。browserを省略するとデフォルトブラウザで開きます。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "url": [
                                "type": "string",
                                "description": "開くURL（例: https://mail.google.com）",
                            ] as [String: Any],
                            "browser": [
                                "type": "string",
                                "description": "オプション。特定のブラウザで開きたい場合のアプリ名（例: Google Chrome, Safari, Arc）",
                            ] as [String: Any],
                        ],
                        "required": ["url"],
                    ] as [String: Any],
                ] as [String: Any],
                [
                    "name": "control_volume",
                    "description": "macOSのシステム音量を制御します",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "action": [
                                "type": "string",
                                "description": "set=絶対値指定(0-100), increase=増加, decrease=減少, mute=消音, unmute=消音解除",
                            ] as [String: Any],
                            "value": [
                                "type": "integer",
                                "description": "action=set: 0〜100の値。increase/decrease: 変化量（1〜30推奨）",
                            ] as [String: Any],
                        ],
                        "required": ["action"],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [[String: Any]],
        ]
    ]
}
