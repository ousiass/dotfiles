# 通知（`.sweep/notify.url`）

**このファイルは `.sweep/notify.url` が存在するときだけ読めばよい。** 無ければ `sweep_notify` は常に no-op なので、呼び出し箇所は全て無視してよい。

プロジェクトごとに異なる Slack / Discord / ntfy.sh に通知できる。

**セットアップ:** リポジトリ直下に1行の URL を保存（`.gitignore` 対象）:

```bash
echo "https://hooks.slack.com/services/T0XXX/B0XXX/xxxx" > .sweep/notify.url
```

**送信先の自動判別:** URL の文字列パターンで使い分ける:

| URL に含まれる文字列 | サービス | フォーマット |
|---|---|---|
| `hooks.slack.com` | Slack | `{"text": "..."}` JSON POST |
| `discord.com/api/webhooks` | Discord | `{"content": "..."}` JSON POST |
| `ntfy.sh` / その他 | ntfy 互換 | POST body 平文 + `Title` / `Priority` ヘッダ |

**通知タイミング:**

| イベント | 通知内容 | 絵文字 |
|---|---|---|
| Issue マージ完了（2-5 直後） | `Merged #<n> (PR #<P>, <duration>)` | `:white_check_mark:` |
| CI 失敗検知（2-4 内） | `CI failed on PR #<P> (attempt <k>/3): <checks>` | `:warning:` |
| sweep が諦め（2-4 上限到達 / 2-8 agent failure） | `Manual intervention needed: #<n> — <理由>` | `:rotating_light:` |
| 最終 PR が CI 緑（single-pr の S-2-2） | `Ready to merge: PR #<P>` | `:white_check_mark:` |
| sweep 全完了（フェーズ3） | `Sweep done: <merged> merged, <failed> failed, elapsed <duration>` | `:checkered_flag:` |

**送信関数の実装:**

```bash
sweep_notify() {
  local title="$1" msg="$2" emoji="${3:-}"
  local url_file=".sweep/notify.url"
  [[ -f "$url_file" ]] || return 0  # URL 未設定 → 無音
  local url
  url=$(head -n1 "$url_file")
  [[ -z "$url" ]] && return 0

  case "$url" in
    *hooks.slack.com*)
      curl -sf -X POST -H 'Content-Type: application/json' \
        --data "$(jq -nc --arg t "$emoji $title: $msg" '{text:$t}')" \
        "$url" >/dev/null 2>&1 || true
      ;;
    *discord.com/api/webhooks*)
      curl -sf -X POST -H 'Content-Type: application/json' \
        --data "$(jq -nc --arg c "$emoji **$title**: $msg" '{content:$c}')" \
        "$url" >/dev/null 2>&1 || true
      ;;
    *)
      curl -sf -X POST -H "Title: $title" -H "Tags: robot" \
        -d "$msg" "$url" >/dev/null 2>&1 || true
      ;;
  esac
}
```

通知失敗（network エラー等）は sweep 本体を止めない (`|| true`)。
