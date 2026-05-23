import Foundation

enum Tools {
    static let systemPrompt = """
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
