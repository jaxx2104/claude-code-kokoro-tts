---
allowed-tools: ["Bash"]
description: "TTS読み上げのミュート/ミュート解除をトグル"
---

# TTS ミュートトグル

`/tmp/kokoro-mute` ファイルの有無でミュート状態をトグルします。
フックスクリプトはこのファイルが存在する場合、読み上げをスキップします。

以下のbashコマンドを実行してください：

```bash
if [ -f /tmp/kokoro-mute ]; then rm -f /tmp/kokoro-mute && echo "TTS: ミュート解除 🔊"; else touch /tmp/kokoro-mute && echo "TTS: ミュート 🔇"; fi
```

結果をユーザーに伝えてください。
