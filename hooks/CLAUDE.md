# TTS Hook Technical Reference (for Claude Code)

hookスクリプトを編集する際に必要な技術コンテキスト。

## Hook Input JSON

各hookはstdinでJSONを受け取る。

### Stop / UserPromptSubmit / PreToolUse

```json
{
  "session_id": "uuid",
  "transcript_path": "/Users/.../.claude/projects/.../uuid.jsonl",
  "cwd": "/path/to/project",
  "hook_event_name": "Stop"
}
```

### SessionEnd

```json
{
  "session_id": "uuid",
  "reason": "exit"
}
```

## Transcript JSONL 形式

Claude Code は応答を JSONL に分割して記録する:

```jsonl
{"type":"assistant","message":{"content":[{"type":"text","text":"確認します..."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read",...}]}}
{"type":"tool_result","tool_use_id":"...","content":"..."}
{"type":"assistant","message":{"content":[{"type":"text","text":"完了しました。"}]}}
```

テキスト抽出ロジック: `tail -r` で逆順に読み、最初の `tool_result` を見つけたらフラグを立て、その前の `assistant` テキストを取得する。ツール未使用時は最後の `assistant` テキストを使う。

## サブシェルパターン

```bash
command ... &
```

`&` でバックグラウンド実行し、hookスクリプトは即座にexit 0する。これにより:
- Claude Code がブロックされない (hookのtimeout内に完了)
- kokoro-tts はバックグラウンドで独立して動作
- ユーザーは音声再生中もClaude Codeを操作可能

**注意**: hookスクリプトがバックグラウンドプロセスの完了を待ってはならない。waitやfgは禁止。

## TTS_SUMMARY マーカー

```html
<!-- TTS_SUMMARY
音声で読み上げるサマリテキスト
TTS_SUMMARY -->
```

- マーカーがあればサマリのみ読み上げ、なければ全文をmarkdown除去して読み上げ
- `awk` の `index()` で抽出 (テキストは `tr '\n' ' '` で1行化済み)
- 抽出後もmarkdown除去 (`strip_markdown.py`) を適用

## 非ブロッキング要件

- Stop hook timeout: 10秒。この間にTTSプロセスを起動してexit 0する必要がある
- Interrupt hook timeout: 5秒。pkill して即exit
- SessionEnd hook timeout: 5秒。クリーンアップして即exit
- hookがtimeoutすると Claude Code がエラーを表示するため、重い処理はバックグラウンドで実行すること

## プロセス管理

- TTSプロセスの停止: `pkill -9 -f kokoro-tts`
- `-f` フラグ: コマンドライン全体でマッチ (プロセス名だけでなく引数も含む)
- `-9`: SIGKILL で即座に停止 (SIGTERMではkokoro-ttsが停止しない場合がある)
- 一時ファイル: `mktemp /tmp/kokoro-input.XXXXXX` で作成、SessionEnd hookで削除
