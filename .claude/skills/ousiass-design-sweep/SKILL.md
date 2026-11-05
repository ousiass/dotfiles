---
name: ousiass-design-sweep
description: ousiass-design-check と design-fix を、指摘が 0 件になるまで自律で回す（fix は並列）。
user-invocable: true
---

# ousiass-design-sweep

`/ousiass-design-check` で Ousiass 共通デザインガイド準拠を確認 → カテゴリ別 Issue を `/design-fix` で修正 → 再 check、を**指摘が 0 件になるまで**反復する。**最後の check を終えたら、その間に溜まったスコープ外（spinoff）を起票し、それも実装してから終わる**（フェーズ3。起票だけで終わらない。実装後の再 check はしない）。`refine-sweep` のデザインガイド版で、Issue を可視性の Source of Truth にする。メインスレッド（CTO）は状態管理と判定だけを行い、**コードには触れない**。check も fix も必ず `Agent` に丸投げする。

**並列化の方針**: check が返す Issue ごとの対象ファイルが**重なるものは 1 バッチ（1 worktree で直列）、重ならないものは別バッチ（並列）**にする。C/T/S/I/M/O は同じファイルを触りがちなので、カテゴリ単位で無条件に並列にはしない。

sweep 系の共通規約（lock・heartbeat・prelude・事前ガード・single-pr）は `../sweep-common/` と `issue-sweep` に従い、ここでは**デザイン固有の差分だけ**書く。

## 引数

- `/ousiass-design-sweep [<target>...]` — `<target>` は `ousiass-design-check` の引数と同じパス・URL（複数可）。省略時は P-0 で聞く。**`#<PR>` 指定は不可**（sweep が差分を動かすので対象が固定されない）
- `--hard-cap N` — check 実行回数の物理上限（デフォルト 10）
- `--no-minor` — 🟡🟢 を Issue 化しない（🔴🟠 が 0 で終了）。デフォルトは全重大度を 0 にする
- `--parallel N` — 同時に走る fix agent 数（デフォルト 5、上限 5）
- `--max-inflight M` — multi-pr のみ。未マージ PR 数の上限（デフォルト 10、上限 15）
- `--single-pr` / `--multi-pr` / `--base <branch>` / `--branch <name>` — `issue-sweep` と同じ。統合ブランチ名のデフォルトは `sweep/ousiass-design-sweep-<YYYYmmdd-HHMMSS>`。**未指定なら P-0 で必ず聞く**
- `--abort` — `../issue-sweep/references/abort-and-recovery.md` の `--abort` 手順を実行して終了

## 前提

- `git`, `gh` 認証済み / GNU coreutils / Stop Hook（`check-sweep-state.sh`, `check-issue-queue.sh`）が有効
- `.sweep/` は常にメインリポジトリ側（`SWEEP_DIR` の定義と、bash 呼び出しごとに `source "$SWEEP_DIR/prelude.sh"` する規約は `../sweep-common/branch-preflight.md`）
- `ousiass-design-check` が動く前提（`ousiass-design-guide` スキルの `references/brand-guide.md` を含む）

## 状態管理 `$SWEEP_DIR/state.json`

```json
{
  "skill": "ousiass-design-sweep",
  "started_at": "<ISO8601>", "updated_at": "<ISO8601>",
  "phase": "iterating" | "terminal",
  "iteration": <check 実行回数>, "hard_cap_iter": <N>,
  "mode": "single-pr" | "multi-pr" | null, "base_branch": null, "int_branch": null,
  "targets": ["<path|URL>"], "include_minor": true, "halt": false,
  "clean_streak": <0 件が連続した check 回数>, "spinoff_stage": null | "filed" | "done",
  "parallel": 5, "max_inflight": 10,
  "termination_reason": null | "clean" | "manual_intervention" | "hard_cap_reached" | "fix_ineffective" | "agent_failed" | "aborted"
}
```

- **監査証跡は `$SWEEP_DIR/design-metrics.jsonl` 一本**。state.json にカウント類を複製しない
- カウンタ（`iteration` / `clean_streak`）はシェルに残らない。更新は `jq` で state.json に書く
- **check を再実行せず推定で `phase=terminal` にしてはならない**。terminal 化の前に `design-sweep-check` 行が最低 1 行あることを確認する

## フェーズ0: lock と state.json

1. `$SWEEP_DIR/lock` が 2 時間以内なら「他 sweep 実行中」で終了。それ以外は `echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"`
2. state.json を上記スキーマで初期化（`mode` / `base_branch` / `int_branch` は null、`iteration=0`、`clean_streak=0`、`spinoff_stage=null`、`phase=iterating`）。**`spinoff-count` も 0 に戻す**（`spinoff-issue` の通算 5 件の起票上限は `$SWEEP_DIR/spinoff-count` に残るので、前回の sweep の分が最後の一括起票を食わないようにする）: `echo 0 > "$SWEEP_DIR/spinoff-count"`
3. ラベルを準備:
   ```bash
   gh label create ousiass-design-sweep --color BB6BD9 --description "created by /ousiass-design-sweep" 2>/dev/null || true
   gh label create ousiass-design-sweep-stuck --color B60205 2>/dev/null || true
   ```

## フェーズ P-0: モード・ベース・対象の確定（必須）

**`../sweep-common/branch-preflight.md` に従う**（`skill_name="ousiass-design-sweep"`）。`<target>` が引数に無いときは、P-0-2 の `AskUserQuestion` に 3 問目「チェック対象」（`リポジトリ全体（.）` / Other でパス・URL）を足して**1 回で**聞く。決まった `targets` を state.json に書く。

**HALT 検知**（targets 確定後に 1 回）: 判定は **`refine-sweep` フェーズ1 手順2 の検知ルールをそのまま使う**（ここに条件を書き写さない。食い違うと sweep ごとに対象が変わる）。`HAS_HALT=true` なら `halt=true` を state.json に書く。**UI が React/Vue でなく `*.templ`（Go テンプレート）と Lit（Web Components の `.ts`）、それらが読む CSS にある**ので、以降の check・fix・バッチ編成は拡張子や構成を tsx/vue 前提にしない。このスキルに拡張子での絞り込みは無い（`*.templ` / `.ts` / `*.css` は check の確認範囲と 2-3 のバッチ編成にそのまま入る）。

`mode=single-pr` なら続けて `../sweep-common/single-branch-mode.md` の S-0（統合ブランチ作成）へ。

## フェーズ2: check → fix → 統合 の反復

### 2-1. check（Agent に丸投げ）

```bash
source "$SWEEP_DIR/prelude.sh"
echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"                  # heartbeat
# multi-pr のみ: git fetch origin "$base_branch" && git pull --ff-only origin "$base_branch"
# single-pr: メイン作業ツリーは統合ブランチに居続ける。ベースを pull しない
jq '.iteration += 1 | .updated_at = (now|floor|todate)' "$SWEEP_DIR/state.json" > "$SWEEP_DIR/s.tmp" && mv "$SWEEP_DIR/s.tmp" "$SWEEP_DIR/state.json"
iter=$(jq -r .iteration "$SWEEP_DIR/state.json")
gh label create "ousiass-design-sweep-iter-${iter}" --color 0E8A16 2>/dev/null || true
stuck=$(gh issue list --label ousiass-design-sweep-stuck --state open --json number --jq 'map(.number)')
```

`Agent(subagent_type: review)`（`model` は渡さない。`harness-model`）:

```
`/ousiass-design-check <targets>` を Skill ツールで実行してください。コードは変更しません。

- 出力先は「GitHub Issue（カテゴリ別）」を選ぶ。確認を求められたら承認して進む。ユーザーへの確認で停止しない
- <halt=true の場合> 対象を tsx/vue/Tailwind 前提で絞らない。`*.templ`・Lit コンポーネント・グローバル CSS / トークン CSS・HTMX 属性で出す UI（トーストやモーダルのスワップ先）も確認範囲に入れる。生成物（`*_templ.go` など）は指摘の `files` に入れず、元の `*.templ` を書く
- 作成した各 Issue に `gh issue edit <n> --add-label ousiass-design-sweep,ousiass-design-sweep-iter-<iter>` を付ける
- 既存 open Issue <stuck> に載っている指摘（項目 ID とファイルが同じ）は新規 Issue にせず `stuck_known` に数える。**`findings` と `issues` には含めない**（`findings` = このチェックで新規 Issue にした指摘だけ。stuck は残っていても 2-2 の「0 件」に届くための定義）
- <include_minor=false の場合> 🟡🟢 は Issue 化せず `skipped_minor` に件数だけ数える
- 指摘 0 件なら Issue を作らない（design-check の 0 件時の挙動どおり）
- 画面などを確認できなかった項目は「問題なし」にせず `unchecked` に書く
- 「ガイド未収載（追加提案）」はカテゴリ Issue に入れず、見つけた瞬間に `jq -nc --arg parent "" --arg type docs --arg title "[ガイド提案] <要約>" --arg files "<file:line>" --arg why "ガイドに規定なし。fix では直せない" '{parent:$parent,type:$type,title:$title,files:$files,why:$why}' >> "$SWEEP_DIR/spinoff-draft.jsonl"` で 1 行 append する（ここでは起票しない。`$SWEEP_DIR` はメインリポジトリ側の `.sweep`。タイトルの `[ガイド提案]` は 3-2 が実装対象から外す目印なので必ず付ける）

最終メッセージは JSON 1 行のみ:
{"issues":[{"issue":N,"category":"C","counts":{"red":a,"orange":b,"yellow":c,"green":d},"files":["<Issue 本文のファイルパス。無ければ []>"]}],"findings":["<項目ID>|<ファイル>", ...],"stuck_known":N,"skipped_minor":N,"unchecked":["<項目: 理由>"],"guide_drift":["<食い違い>"],"failure":null}
失敗時: {"issues":[],"findings":[],"failure":"<1行で原因>"}
```

返答を metrics に **必ず** 追記する（この行が check を実際に走らせた証跡）:

```bash
source "$SWEEP_DIR/prelude.sh"
iter=$(jq -r .iteration "$SWEEP_DIR/state.json")
resp=$(cat <<'JSON'
<agent の返答 JSON をそのまま貼る>
JSON
)
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson iter "$iter" --argjson r "$resp" '{
  ts:$ts, source:"design-sweep-check", iter:$iter,
  new_issues: ($r.issues|length),
  counts: {red:([$r.issues[].counts.red]|add // 0), orange:([$r.issues[].counts.orange]|add // 0),
           yellow:([$r.issues[].counts.yellow]|add // 0), green:([$r.issues[].counts.green]|add // 0)},
  findings: ($r.findings|sort|unique), stuck_known: ($r.stuck_known // 0),
  unchecked: ($r.unchecked // []), guide_drift: ($r.guide_drift // [])
}' >> "$SWEEP_DIR/design-metrics.jsonl"
```

### 2-2. 判定

上から最初に当たったものを実行する:

| 条件 | 実行すること |
|---|---|
| `failure != null` | `agent_failed` → フェーズ3 |
| `findings` が空（0 件） | `clean_streak += 1`。**2 以上**なら `stuck_known > 0` で `manual_intervention`、それ以外は `clean` → フェーズ3。1 なら **2-1 に戻って 2 回目の check**（reviewer のゆらぎで 1 回の 0 を信用しない。消化はしない） |
| `iteration >= hard_cap_iter` | `hard_cap_reached` → フェーズ3 |
| 直前の check と `findings` の集合が完全一致（空でない） | `fix_ineffective` → フェーズ3 |
| それ以外 | `clean_streak = 0` にして 2-3 へ |

`fix_ineffective` の比較（2 要素が等しく、空でない）:

```bash
jq -sc 'map(select(.source=="design-sweep-check")) | [(.[-1].findings), (.[-2].findings // [])]' "$SWEEP_DIR/design-metrics.jsonl"
```

`stuck_known` だけ残って新規指摘が 0 のときも上の 0 件の行に入る（人に返す指摘として終了する）。

**フェーズ3 へ進むと決めたその場で、終了理由を state.json に書く**（`phase` は `iterating` のまま。terminal 化は 3-3）。シェル変数 `$reason` は次の Bash 呼び出しに残らず、3-2 の条件と最終レポートが reason を state.json から読むため:

```bash
source "$SWEEP_DIR/prelude.sh"
jq --arg r "<clean|manual_intervention|hard_cap_reached|fix_ineffective|agent_failed>" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.termination_reason=$r | .updated_at=$now' "$SWEEP_DIR/state.json" > "$SWEEP_DIR/s.tmp" && mv "$SWEEP_DIR/s.tmp" "$SWEEP_DIR/state.json"
```

### 2-3. バッチ編成とキュー

**メインは Issue 本文を読まない**。2-1 の `issues[].files` だけで組む:

- `files` が 1 つでも重なる Issue は同じバッチ（連結成分でまとめる）
- `files` が空の Issue は**単独バッチかつ serial_only**（読み取れないときは保守的に倒す。他のバッチが in-flight の間は起動しない）
- <halt=true の場合> 同じ部品名のファイル（例: `button.templ` / `button.ts` / `button.css`）は同じ部品として**重なる**扱いにする。HALT はスタイルと挙動が部品単位で分かれて別パスになりやすく、パスの完全一致だけだと別バッチに割れて競合する
- バッチ内の順は 🔴 を含む Issue を先頭、残りは C → T → S → I → M → O
- バッチの先頭に近い（🔴 を含む）ものから起動する

`$SWEEP_DIR/queue.txt` に 1 行 = 1 バッチ（`61,63` のようにカンマ区切り。行に他の情報を混ぜない）で書き出し、`attempts.json` を `{}` に戻す。work_branch は design-fix が作る `design/#<バッチ最後の Issue>`。

### 2-4. fix（並列、in-flight パイプライン）

`issue-sweep` フェーズ2 のパイプラインに従う（バリアなし。スロットが空いたら次を起動）。`--parallel` = 同時に走る fix agent 数。worktree は **sweep が 1 つ作って**パスを渡す（agent に作らせない。失敗したらそのバッチは起動しない）:

```bash
source "$SWEEP_DIR/prelude.sh"
wt="$(dirname "$main_worktree")/$(basename "$main_worktree")-dsweep-<先頭Issue>"
git worktree add "$wt" -b "sweep/design-<先頭Issue>" "${int_branch:-$base_branch}"
assert_not_base "$wt" || echo "guard 失敗: このバッチは諦める"
```

`Agent(subagent_type: develop)`、description `"design-sweep iter <iter> #<a>[,#<b>]"`。プロンプト（multi-pr 版）:

```
Issue #<a>[, #<b>] のデザイン指摘を修正して PR を 1 本作ってください。メインスレッドには JSON だけを返します。
worktree は作成済みです。以降のすべての作業を <wt の絶対パス> の中で行ってください。

0. 最初に必ず実行する（最初の `git commit` の前にも再確認）:
   cd <wt の絶対パス>
   cur=$(git rev-parse --abbrev-ref HEAD)
   [[ "$cur" != "<base_branch>" && "$cur" != "main" && "$cur" != "develop" ]] || exit 2
   失敗したらメインリポジトリで代わりに作業せず、failure JSON を返して終了する。
1. 各 Issue を**この順に 1 件ずつ** `/design-fix #<n> --auto --no-pr` を Skill ツールで起動して修正する。
   `--auto` = 確認で止まらない（デザイン検証 3-3 は省略されない）/ `--no-pr` = PR は手順2 で 1 本だけ作る。
   design-fix は `design/#<n>` ブランチを切る。複数 Issue では前の Issue のブランチ上に積まれるので、
   最後に `git rev-parse --abbrev-ref HEAD` が返すブランチが work_branch。
   <halt=true の場合> `*.templ` を直したらプロジェクトの生成コマンド（`templ generate` 等）を実行し、生成物をコミットに含めるかは既存リポジトリの慣例に従う（含めない慣例なら含めない）。Lit・CSS の修正は同じバッチの Issue 内で完結させる。
2. push して `gh pr create --base <base_branch> --head <work_branch>`（タイトルに全 Issue 番号、本文に Issue ごとの対応を 1 行ずつ）。
   `gh pr edit <PR> --add-issue <各 Issue URL>` でリンクする（`Closes` は使わない）。
3. `/refine-git --no-merge --skip-minor --max-iter 2` を Skill ツールで起動して研磨する
   （design-fix の `--auto` は review を省くので、ここが汎用観点のレビューになる）。
   `critical_remaining == 0 ∧ major_remaining == 0` でなければ failure として返す。
4. CI 待ち・マージ・Issue close はしない（メインの責務）。`gh issue edit <n> --add-assignee @me` で着手 Issue を assign する。
5. 修正中に見つけた**スコープ外**（共有部品の別件・他 Issue に属さない逸脱など）は、見つけた瞬間に `"$SWEEP_DIR/spinoff-draft.jsonl"`（メインリポジトリ側の `.sweep`。worktree 内に書かない）へ `jq -nc --arg parent "<Issue番号>" --arg type "<bug|feat|chore|refactor|docs>" --arg title "<要約>" --arg files "<file:line>" --arg why "<混ぜない理由>" '{parent:$parent,type:$type,title:$title,files:$files,why:$why}'` で 1 行 append する。PR 本文・返答への列挙で代えない。`/spinoff-issue` は呼ばない。

成功: {"issues":[<a>,<b>],"work_branch":"design/#<b>","worktree":"<絶対パス>","pr_number":N,"pr_url":"<URL>","refine_status":"<clean|iter_limit|no_progress>","critical_remaining":0,"major_remaining":0,"failure":null}
失敗: {"issues":[<a>,<b>],"failure":"<1行で原因>","failed_issue":<n>,"completed_issues":[...],"worktree":"<絶対パス>"}

返答は JSON 1 行のみ。`.sweep/` の state / lock を触らない。`/ousiass-design-sweep` 等の sweep を再帰起動しない。`gh pr merge` / `gh issue close` を叩かない。
```

**single-pr のとき**の差分（`single-branch-mode.md` S-1 と同じ）: 手順2 の push までで `gh pr create` はしない、手順3 の `/refine-git` は起動しない（研磨は S-2-0）、ゲートは「テストと lint が通ること」、返答 JSON は `pr_number` / `pr_url` / `refine_status` / `*_remaining` を `work_branch` と `worktree` に置き換える。

### 2-5. 統合と後処理

| mode | 実行すること |
|---|---|
| multi-pr | `issue-sweep` の 2-0（PR 一覧は `head:design/` と `head:sweep/design-` の両方で絞る）/ 2-3（判定表・CI fix プロンプト）/ 2-6 / 2-7 / 2-8 をそのまま使う。2-4 の Issue close はバッチの全 Issue（親 Issue 判定は不要）。マージは `gh pr merge --merge --delete-branch`。**冪等性チェックのブランチ名は `design/#<バッチ最後の Issue>`**（フェーズ3-2 の spinoff 実装は `sweep/design-spin-<バッチ先頭の Issue>`） |
| single-pr | `single-branch-mode.md` S-1 の統合（**必ず直列**の `git merge --no-ff`、競合は rebase agent 1 回 → 諦め）。Issue は close しない。CI は最終 PR で 1 回 |

metrics は `issue-sweep` の `metrics.jsonl` ではなく **`design-metrics.jsonl`** に書く（`design-sweep-check` 行と同居させ、混ぜないために `source` で区別）:

```bash
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson iter "$iter" --argjson issues '[61,63]' \
  --argjson pr "${pr:-null}" --arg status "merged" \
  '{ts:$ts,source:"design-sweep-consume",iter:$iter,issues:$issues,pr_number:$pr,status:$status}' >> "$SWEEP_DIR/design-metrics.jsonl"
```

`status`: `merged`（multi-pr）/ `integrated`（single-pr）/ `agent_failed` / `ci_gave_up` / `merge_conflict` / `branch_guard`。

**失敗の扱い**（`issue-sweep` 2-7 と同じ。`attempts.json` で 2 回試行して通らなければ諦める）に加えて、諦めたバッチの Issue に `ousiass-design-sweep-stuck` ラベルを付ける（次回以降の check が重複 Issue を作らない根拠）。キュー行は**必ず削除**する。**失敗したバッチは worktree と、そのバッチの `sweep/design-*` / `design/#<n>` ブランチ（PR が無いもの）のローカル・リモートを消してから**再試行する（design-fix が同名ブランチを切れなくなる）。

キューが空 ∧ in-flight 0 になったら 2-1 に戻る。待つときは 1 つの bash コマンドの中で `sleep 60`（**「待機」でターンを終えない**）。

## フェーズ3: spinoff の起票と実装、完了処理

check のループが終わった（terminal 理由が確定した）あとに 1 回だけ実行する。**spinoff の実装まで終えてから** terminal 化する。

### 3-1. spinoff の一括起票

`spinoff_stage` が null で `$SWEEP_DIR/spinoff-draft.jsonl` が空でなければ、起票する。ファイルが無い / 空なら 3-3 へ。

1. 起票済みとして退避する（以降に append される新しい draft と混ぜない）:
   ```bash
   source "$SWEEP_DIR/prelude.sh"
   mv "$SWEEP_DIR/spinoff-draft.jsonl" "$SWEEP_DIR/spinoff-filed-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
   ```
2. `Agent(subagent_type: develop)` に `/spinoff-issue --batch <退避した path>` を **1 回だけ**実行させ、JSON 1 行で返させる:
   `{"created":[{"issue":N,"type":"bug|feat|chore|refactor|docs","title":"<タイトル>","files":["<パスのみ。行番号は除く。無ければ []>"]}],"duplicates":[{"title":"...","existing":N}],"skipped":[{"title":"...","reason":"<上限超過 など>"}],"failure":null}`
   `skipped` は `spinoff-issue` が件数上限（1 回 5 件・`spinoff-count` で通算 5 件）などで**起票しなかった**分。黙って落とさず必ず返させる。
   失敗時 `{"created":[],"duplicates":[],"skipped":[],"failure":"<1行で原因>"}`（失敗なら実装は行わずレポートに書いて 3-3 へ）
3. `spinoff_stage="filed"` を state.json に書く

**「ガイド未収載」の提案**（2-1 の check agent が append したもの）は、タイトルを `[ガイド提案] <要約>` で draft に書かせる。これらはプロジェクトでは直せない（ガイドは `ousiassllc/brand-guide` 側）ので **3-2 の実装対象から外し**、open のままレポートに「ガイドへの追加提案」として列挙する。

### 3-2. spinoff の実装（1 回だけ・再 check なし）

**実行する条件**: 3-1 が成功し、state.json の `termination_reason` が `agent_failed` でないこと（`jq -r .termination_reason "$SWEEP_DIR/state.json"` で読む。2-2 で書いてある）。対象は `created` から `[ガイド提案]` を除いたもの。`duplicates` は既存 Issue、`skipped` は起票されていないので、どちらも実装せずレポートに列挙する（`skipped` の draft は退避ファイル `spinoff-filed-*.jsonl` に残っている）。対象が 0 件ならスキップ。

2-3（バッチ編成。`files` の重なり・空は単独直列・HALT の部品名）→ 2-4（並列 fix パイプライン）→ 2-5（統合と後処理）をそのまま使う。**差分はこれだけ**:

| 箇所 | spinoff 実装での差し替え |
|---|---|
| 入力 | 2-1 の `issues[].files` の代わりに 3-1 の `created[].files`。`queue.txt` は対象バッチで書き直し、`attempts.json` を `{}` に戻す |
| worktree / ブランチ | `git worktree add "$wt" -b "sweep/design-spin-<先頭Issue>" "${int_branch:-$base_branch}"`（design-fix は使わないので `design/#n` は作られない） |
| fix プロンプト手順1 | `/design-fix` ではなく Issue ごとに `gh issue view <n> --json labels` を見て、`type:bug` なら `/bug-fix #<n> --auto --no-pr`、それ以外は `/impl #<n> --auto --no-pr`（ガイド準拠の指摘ではなくスコープ外の別件のため）。work_branch は手順1 末尾の `git rev-parse --abbrev-ref HEAD` の結果（= sweep が作った `sweep/design-spin-…`）。手順0・2・3・4・5 と返答 JSON は同じ |
| 冪等性チェックのブランチ名 | `sweep/design-spin-<バッチ先頭の Issue>` |
| metrics | `source` は `design-sweep-spinoff`（`design-sweep-check` 行・`design-sweep-consume` 行と混ぜない） |
| 諦めたバッチ | 2 回試行して通らなければ Issue にコメントして諦める（`issue-sweep` 2-7）。**`ousiass-design-sweep-stuck` は付けない**（以降 check は走らない）。レポートの「未実装 spinoff」に理由付きで列挙 |
| この pass 中の新しい発見 | fix agent が append した draft、`/impl` / `/bug-fix` が自分で起票した Issue は**実装しない・再 sweep しない**。レポートに列挙するだけ（無限に伸びないように 1 回で打ち切る） |

キューが空 ∧ in-flight 0 になったら `spinoff_stage="done"` を state.json に書く。**実装後に check は再実行しない**。このため spinoff 実装が導入した逸脱は検証されない。レポートに「spinoff 実装後は未 check」と書く。

### 3-3. 完了処理

1. **single-pr のみ**: `single-branch-mode.md` の S-2（統合研磨 → 最終 PR → CI 確認。**PR はマージしない**）→ S-3（Issue は close せず「マージ後に close する Issue」を列挙。spinoff の Issue も含める）。**S-2 は 3-2 の統合まで終えてから**行う（spinoff の差分も最終 PR に入れるため）
2. `git worktree prune`
3. **terminal 化**（`design-metrics.jsonl` に `design-sweep-check` 行があることを確認してから。`termination_reason` は 2-2 で書き込み済みなので `phase` だけ変える）:
   ```bash
   source "$SWEEP_DIR/prelude.sh"
   jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.phase="terminal" | .updated_at=$now' \
     "$SWEEP_DIR/state.json" > "$SWEEP_DIR/s.tmp" && mv "$SWEEP_DIR/s.tmp" "$SWEEP_DIR/state.json"
   ```
4. レポート `$SWEEP_DIR/report-ousiass-design-sweep-<ts>.md` を書く。必須項目: Summary（mode・base・統合ブランチと PR URL・最終 status と reason〔state.json の `termination_reason`〕・check 回数）/ 反復ごとの推移（`design-sweep-check` 行の iter・new_issues・counts を表に）/ 残りの open Issue（`ousiass-design-sweep` ラベル。stuck は別掲）/ **最終 check の `unchecked`**（「問題なし」と書かない）/ `guide_drift`（Issue にしない。チャットで報告）/ **spinoff**（実装して merged / integrated にした Issue、未実装で諦めた Issue と理由、重複で触らなかった Issue、**上限などで起票されなかった `skipped`（タイトルと理由。0 件でも「なし」と書く）**、`[ガイド提案]`、3-2 中に新しく出たもの。「spinoff 実装後は未 check」）
5. `rm -f "$SWEEP_DIR/lock"`、`notify.url` があれば `../sweep-common/notifications.md` で通知
6. ユーザーに報告（日本語。CLAUDE.md の `## 完了報告` の欄に従う。single-pr は PR が open のまま返ること、CI 結果、マージ後に close する Issue をそのまま貼れるコマンドで示す）

## 禁止行動

本文に書いた手順は再掲しない。ここは手順どおりに読んでも踏みうる罠だけ。

- **check が 1 回 0 件だっただけで終了する**（2 回連続で確認する）／ **`unchecked` を「問題なし」として報告する**
- **`files` が重なるバッチを並列で起動する** ／ **`files` が空のバッチを他と並列にする**
- **`/design-fix` を `--auto` なしで呼ぶ**（ユーザー確認で止まる）／ `--no-pr` なしで呼ぶ（バッチの PR が二重になる）
- **stuck Issue を `ousiass-design-sweep-stuck` ラベルなしで諦める**（次の check が同じ指摘の重複 Issue を作り続ける）／ ラベルを勝手に外す
- **メインスレッドが Issue 本文を読む・コードを直す・コミットする**
- **ユーザーに確認して止まる**（「続けますか」「並列度は？」。P-0 の質問以外は聞かない。Stop Hook が押し戻す）
- **スコープ外の発見を spinoff-draft に append せず、PR 本文・返答・レポートの列挙だけで済ませる**／ **発見のたびに `/spinoff-issue` を呼ぶ**（起票はフェーズ3-1 の 1 回）
- **spinoff を起票だけして終わる**（3-2 で実装する。`[ガイド提案]` と重複だけが対象外）／ **3-2 の途中で見つかった spinoff をさらに実装する**（1 回で打ち切る）／ **spinoff の実装に `/design-fix` を使う**／ **spinoff 実装の前に S-2（最終 PR）や terminal 化をする**
- ブランチ・キュー・パイプライン・single-pr の禁止行動は `issue-sweep` / `../sweep-common/branch-preflight.md` / `../sweep-common/single-branch-mode.md` のものをそのまま適用する（P-0 を飛ばす、ベースを推測する、worktree 失敗でメインで代替作業する、統合 merge を並列にする、最終 PR を sweep がマージする、等）
