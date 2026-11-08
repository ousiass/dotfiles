---
name: ousiass-design-sweep-split
description: ousiass-design-sweep の check を観点別の並列 agent にした版。指摘 0 件まで check→fix を回す（試作）。
user-invocable: true
---

# ousiass-design-sweep-split

`ousiass-design-sweep`（check → `/design-fix` を指摘 0 件まで反復 → spinoff 実装）の **check 工程だけ**を、観点グループごとの並列 agent に差し替えた版。1 agent が見る項目を減らして読み飛ばし（標準 UI のスライダー、進捗バーの見た目、トークン外の色、など）を減らすのが狙い。

**このスキルは差分だけを書く。** 実行前に `../ousiass-design-sweep/SKILL.md` を読み、**下の差分以外はすべてそのとおりに実行する**（引数、状態管理、フェーズ0、P-0、判定 2-2、バッチ編成 2-3、fix 2-4、統合 2-5、フェーズ3 の spinoff 起票と実装、禁止行動）。`ousiass-design-sweep` を直したらこちらにも効く（複製しないのでずれない）。

check のグループ表・agent プロンプト・確認状況（coverage）の検証は `../ousiass-design-check-split/SKILL.md` が正本。ここに書き写さない。

## 差分

| 箇所 | このスキルでの差し替え |
|---|---|
| 引数 | `ousiass-design-sweep` と同じ。ただし **URL 指定は不可**（`ousiass-design-check-split` が画面確認を扱わないため）。パスだけ |
| `skill_name` / state.json の `skill` | `ousiass-design-sweep-split`（統合ブランチ名の既定は `sweep/ousiass-design-sweep-split-<ts>`、`state.json` の `"skill"` もこれ）。ラベル・`design-metrics.jsonl`・`.sweep/` の置き場は `ousiass-design-sweep` と**同じ**（同時には走らせない。lock で排他） |
| 2-1 check | 下記「2-1 の差し替え」 |
| metrics の `design-sweep-check` 行 | `ousiass-design-sweep` の jq に `coverage: ($r.coverage // {})` を足す（グループごとの確認状況。2-1 の返答に含まれる） |

## 2-1 の差し替え

ラウンド冒頭（heartbeat、`iteration += 1`、iter ラベル作成、`stuck` の取得）は `ousiass-design-sweep` の 2-1 と同じ。その後の「Agent に `/ousiass-design-check` を丸投げ」を次の 4 段に置き換える。**メインはコードを読まない**。

**(a) 準備と並列 check** — `../ousiass-design-check-split/SKILL.md` の手順 1〜2 をそのまま実行する（対象一覧・トークン定義・承認済みの逸脱・SHA を揃え、**1 メッセージで全グループの Agent を同時起動**）。各 agent の返答 JSON は、メインの context に貼らず、**返答を受けたらそのままファイルに保存**する:

```bash
source "$SWEEP_DIR/prelude.sh"
iter=$(jq -r .iteration "$SWEEP_DIR/state.json")
# グループ <G> の返答（JSON 1 行）を保存。上書き再実行時は同じファイル名
cat > "$SWEEP_DIR/check-iter-${iter}-<G>.json" <<'JSON'
<agent の返答 JSON をそのまま貼る>
JSON
```

**(b) coverage 検証** — `../ousiass-design-check-split/SKILL.md` の手順 3 のとおり。欠けた ID だけを担当にして**同じグループを 1 回だけ**再実行し、返答は同じファイルに上書きする（欠けたままの ID は「未確認」）。

**(c) 統合**:

```bash
source "$SWEEP_DIR/prelude.sh"
iter=$(jq -r .iteration "$SWEEP_DIR/state.json")
jq -s '{
  findings:     ([.[].findings[]?] | unique_by([.id,.file,.line])),
  unchecked:    ([.[] | (.coverage // {}) | to_entries[] | select(.value.status=="unchecked") | {id:.key, reason:.value.note}]),
  coverage:     (map({(.group): ((.coverage // {}) | {checked:([.[]|select(.status=="checked")]|length), unchecked:([.[]|select(.status=="unchecked")]|length)})}) | add),
  guide_gap:    ([.[].guide_gap[]?]),
  guide_drift:  ([.[].guide_drift[]?] | unique),
  out_of_scope: ([.[].out_of_scope[]?]),
  failures:     ([.[] | select(.failure != null) | {group, failure}])
}' "$SWEEP_DIR"/check-iter-${iter}-[A-Z].json > "$SWEEP_DIR/check-iter-${iter}-merged.json"
```

`failures` が 1 件でもある（再実行後も `failure`）なら `agent_failed`（`ousiass-design-sweep` の 2-2 の最初の行と同じ扱い）。

**(d) Issue 化（1 つの Agent に任せる）** — `Agent(subagent_type: review)`（`model` は渡さない）に、統合結果のパス `$SWEEP_DIR/check-iter-<iter>-merged.json` を渡して Issue を作らせる。メインは統合結果の中身を読まない:

```
`<merged.json の絶対パス>` の findings を、GitHub Issue（カテゴリ別）にしてください。コードは変更しない。ユーザーへの確認で停止しない。

- 項目 ID の文字（C / T / S / I / M / O / B）ごとに、指摘があるカテゴリだけ 1 件ずつ作る。形式・タイトル・本文は `<ousiass-design-check の templates/report.md の絶対パス>` の「カテゴリ別 Issue の形式」。基準欄の SHA は <SHA>、承認済みの逸脱は <件数>
- 「未確認」には merged.json の `unchecked` を該当カテゴリごとに書く（問題なしと書かない）。「ガイド未収載（追加提案）」は `guide_gap` を該当カテゴリに入れる
- 作成した各 Issue に `gh issue edit <n> --add-label ousiass-design-sweep,ousiass-design-sweep-iter-<iter>` を付ける
- 既存 open Issue <stuck> に載っている指摘（項目 ID とファイルが同じ）は新規 Issue にせず `stuck_known` に数える。**`findings` と `issues` には含めない**
- <include_minor=false の場合> severity が yellow / green の指摘は Issue 化せず `skipped_minor` に件数だけ数える
- 「ガイド未収載（追加提案）」は `jq` で `"$SWEEP_DIR/spinoff-draft.jsonl"` にも 1 行 append する（`type` は docs、`title` は `[ガイド提案] <要約>`。形式は `ousiass-design-sweep` の 2-1 と同じ）
- Issue 本文の `files` は、その Issue の指摘の `file` から行番号を除いたパスの配列にする

最終メッセージは JSON 1 行のみ（`ousiass-design-sweep` の 2-1 の返答と同じ形に、`coverage` を足したもの）:
{"issues":[{"issue":N,"category":"C","counts":{"red":a,"orange":b,"yellow":c,"green":d},"files":["<パス>"]}],"findings":["<項目ID>|<ファイル>", ...],"stuck_known":N,"skipped_minor":N,"unchecked":["<項目: 理由>"],"guide_drift":["<食い違い>"],"coverage":<merged.json の coverage をそのまま>,"failure":null}
失敗時: {"issues":[],"findings":[],"failure":"<1行で原因>"}
```

この返答を、`ousiass-design-sweep` の 2-1 の「metrics に追記」へそのまま渡す（以降の 2-2 判定は `findings` が空かどうかなど、従来のまま）。

## 試すとき

- 初回は小さい対象に絞り、`--hard-cap 3 --multi-pr` で動かす（Issue / PR が実際に作られる）
- 並列版の効果を見たいときは、同じ対象に `ousiass-design-sweep` と本スキルを別々に（同時でなく）走らせ、1 周目の `design-sweep-check` 行（`counts` / `findings`）と本スキルの `coverage` を比べる。`design-metrics.jsonl` は共用なので、実行後にファイルを退避してから次を走らせる
- 単独の確認だけなら `/ousiass-design-check-split <対象> --out file`（Issue も fix も無し）

## 本スキル固有の禁止行動

- **`ousiass-design-sweep` を読まずに差分表だけで実行する**（差分以外は全部そちらの手順）
- **グループ agent を逐次に起動する／agent の返答をメインの context に貼り続ける**（保存してファイルで統合する）
- **メインが `merged.json` を読んで Issue を作る／コードを読む**（(d) の Agent に任せる）
- **coverage を検証せずに統合する／欠けた ID を「問題なし」にする**
- **`ousiass-design-check-split` のグループ表をここに複製する**（正本は 1 つ）
