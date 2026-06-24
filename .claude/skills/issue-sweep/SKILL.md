---
name: issue-sweep
description: 複数のオープン Issue をキュー化し、Stop Hook と連動して端から自律的に実装・PR auto-merge まで進める。
user-invocable: true
---

# issue-sweep

複数の GitHub Issue を端から自律的に連続実装するスキル。`.sweep/queue.txt` にキューを書き出し、Stop Hook (`hooks/check-issue-queue.sh`) と連動してキューが空になるまで Claude が停止できないようにする。

## 引数

- `/issue-sweep` — ラベル指定なし（全オープン Issue）
- `/issue-sweep label:<name>` — ラベルで絞り込み（例: `label:sprint-1`）
- `/issue-sweep #<n1> #<n2> ...` — Issue 番号を直接指定
- `/issue-sweep #<parent>` — 指定した **フェーズ Issue**（`split-from:#<parent>` ラベル付き子 Issue を持つ親）に対しては、子 Issue 群に自動展開してそれだけ処理する。親本体は実装対象にしない（フェーズ単位の一括実装に使える）
- `/issue-sweep --abort` — 実行中の sweep を中止しキュー / ロックを削除（後述）
- `/issue-sweep --parallel <N>` — 同時に処理する Issue 数（**デフォルト 5**、上限 5）。依存関係のない Issue を最大 N 件並列で agent に渡す。ユーザーに値を確認せず常にこのデフォルトで起動する
- `/issue-sweep --no-follow-spinoffs` — sweep 中に spinoff された Issue を最後に再 sweep するのを抑止（デフォルトは spinoff が出なくなるまで自動追跡）
- `/issue-sweep --max-rounds <N>` — spinoff 追跡の上限周回数（**デフォルト 10、最大 20**）。通常はこの値に到達する前に spinoff が枯れて自然終了する。明示指定された場合のみその値を使う

## 前提条件

- `gh` CLI が認証済み
- `.claude/hooks/check-issue-queue.sh` と `.claude/hooks/check-sweep-state.sh` が実行可能
- `settings.json` の Stop / SessionStart Hook が有効
- ベースブランチ（例: `develop`）にチェックアウト済み。各サブスキルはそのブランチをベースに PR を作る
- リポジトリで auto-merge が有効化されていることが望ましい（Settings → General → Allow auto-merge）。**OFF の場合はフェーズ0.5 でユーザーに ON 化確認 → 不可なら direct merge モードに自動フォールバック**

## 状態管理 `.sweep/state.json`

sweep 系スキル共通の進行状態ファイル。Stop Hook (`check-sweep-state.sh`) は `phase != "terminal"` の間（lock が新鮮な限り）停止をブロックする。**「キューが空っぽいから終わった」と推定で `phase=terminal` にしてはならない**。terminal 化前にキュー残数 = 0 と spinoff 検出済みを必ず確認し、`evidence` に当該 sweep で参照した metrics 行を append する。

**スキーマ（issue-sweep の場合）:**
```json
{
  "skill": "issue-sweep",
  "started_at": "<ISO8601>",
  "updated_at": "<ISO8601>",
  "phase": "iterating" | "terminal",
  "queue_total": <N>,
  "queue_remaining": <N>,
  "processed_count": <N>,
  "merged_count": <N>,
  "failed_count": <N>,
  "round": <K>,
  "max_rounds": <M>,
  "merge_mode": "auto" | "direct",
  "last_counts": {"critical": null, "major": null, "minor": null},
  "evidence": [".sweep/metrics.jsonl:<line>", ...],
  "termination_reason": null | "queue_empty" | "manual_intervention" | "aborted"
}
```

`last_counts` は issue-sweep 内では使わないが Stop Hook 互換のためフィールドを残す（null 固定）。各 Issue を処理し終えるたびに `.sweep/metrics.jsonl` への追記行を `evidence` に append する。

**更新タイミング:**
- フェーズ0/1 でキュー構築完了後に `phase=iterating, queue_total, queue_remaining=queue_total, processed_count=0, ...` で初期化
- 各 Issue 完了ごとに `queue_remaining -= 1`, `processed_count += 1`, `merged_count` or `failed_count` をインクリメント、`evidence` に metrics 行参照を append、`updated_at` 更新
- spinoff 追跡 round 更新時に `round += 1`、`queue_remaining` を新キューサイズに更新
- フェーズ3 終了時に `phase=terminal` + `termination_reason` をセット

## --abort 処理

引数が `--abort` の場合は以下を実行して終了する（他フェーズに進まない）:

```bash
rm -f .sweep/queue.txt .sweep/lock
# state.json があれば terminal 化（履歴を残すため削除しない）
if [[ -f .sweep/state.json ]]; then
  jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.phase = "terminal" | .termination_reason = "aborted" | .updated_at = $now' \
    .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
fi
```

完了後「sweep を中止しキュー / ロックを削除しました」とユーザーに報告。

## フェーズ0: 多重起動チェック（lock 取得）

フェーズ1の前に必ず実行する。lock は **heartbeat 方式**で stale を判定する（PID 比較は Bash 子プロセス起動関係に左右されて脆いため使わない）。

1. `.sweep/lock` の存在確認
2. 存在する場合: ファイル内容 `<owner_pid>:<unix-ts>` を読み取り、`unix-ts` と現在時刻を比較
   - **2時間以内** → 他セッションが sweep 実行中。`echo "他セッションが sweep 実行中（lock の最終更新は <時刻>）。停止するには /issue-sweep --abort を実行"` と表示して終了
   - **2時間以上経過** → stale lock として `rm .sweep/lock` で削除して続行
3. ロック書き込み: `echo "$PPID:$(date +%s)" > .sweep/lock`
4. フェーズ2の各反復冒頭で **heartbeat 更新**: `echo "$PPID:$(date +%s)" > .sweep/lock`（lock の鮮度を保つ）
5. フェーズ3完了時 / 中断時 / `--abort` 時に必ず `rm -f .sweep/lock` する

## フェーズ0.5: auto-merge 設定の preflight（lock 取得直後）

`merge_mode` を確定する。以後のフェーズ2 ですべての agent / メインがこの値で動く。

1. **リポジトリ設定を確認**:
   ```bash
   repo_slug=$(gh repo view --json owner,name -q '"\(.owner.login)/\(.name)"')
   allow_auto=$(gh api "repos/${repo_slug}" -q .allow_auto_merge 2>/dev/null || echo "false")
   ```

2. `allow_auto == "true"` → `merge_mode=auto` 確定、フェーズ1 へ。

3. `allow_auto == "false"` の場合、**`AskUserQuestion` で確認**:
   - 質問: 「リポジトリ設定 `Allow auto-merge` が OFF です。ON にして auto-merge モードで進めますか？（OFF のままなら CI 緑後にメインが直接マージする direct モードで進行）」
   - 選択肢: 「ON にする (auto モード)」「OFF のまま (direct モード)」

4. 回答が **「ON にする」** の場合:
   ```bash
   if gh api "repos/${repo_slug}" -X PATCH -F allow_auto_merge=true 2>/dev/null; then
     merge_mode="auto"
   else
     merge_mode="direct"
     # 通知: 「権限不足等で ON 化に失敗したため direct モードで進めます」
   fi
   ```
   失敗した場合はユーザーにエラー内容を1行通知してから direct で続行。

5. 回答が **「OFF のまま」** の場合: `merge_mode=direct`。

6. 確定した `merge_mode` をユーザーに 1 行表示（`auto-merge mode: <auto|direct>`）し、フェーズ1 の state.json 初期化に渡す。

**merge_mode による挙動の違い:**
- `auto`: agent が `gh pr merge --auto --merge --delete-branch` で予約 → メインが MERGED ポーリング
- `direct`: agent は PR 作成までで返す（`--auto` 叩かない） → メインが CI 緑をポーリング → 緑確定で `gh pr merge --merge --delete-branch` を直接実行

## フェーズ1: Issue キューの構築

1. 引数を解釈する
   - 引数なし: `gh issue list --state open --json number,labels,title --limit 200`
   - `label:<name>`: `gh issue list --state open --label <name> --json number,labels,title --limit 200`
   - `#<n>` 列挙: 各 Issue を `gh issue view <n> --json number,labels,title`
   - **親 Issue 自動展開**: 列挙された各 `#<n>` について、`gh issue list --state open --search "label:split-from:#<n>" --json number,labels,title` で子 Issue を検索:
     - **子が見つかった場合**: その親 `#<n>` は **トラッカーとみなしキューから除外**し、代わりに子 Issue 群をキューに含める（親本体は実装対象にしない）
     - **子が見つからない場合**: その `#<n>` 自身をキューに残す
     - これにより `/issue-sweep #100`（#100 が 5 子持ちのフェーズ Issue）で「そのフェーズに属する 5 件だけ」を端から処理する運用が可能
2. 順序と**並列可否**を決定する（ユーザーには確認しない、デフォルト 5 並列を最大限活かしつつ並列不可ケースを自動検知）
   - **明示的依存**: 本文の「依存: #N」「blocked by #N」「Depends on #N」「Blocked by #N」「Closes/Fixes #N」を依存とみなし、依存先を先に処理する
   - **優先度**: `priority:p0` / `p1` 等のラベルを優先
   - **並列禁止フラグ**: 以下のいずれかに該当する Issue は `serial-only` としてマークし、**他 Issue と並列起動しない**（その Issue は単独で処理。前後の Issue とは普通に進む）
     - `serial-only` / `no-parallel` / `isolated` ラベルが付いている
     - 本文に「並列禁止」「sequential only」「do not parallelize」等の明示記述
     - `migration` / `schema-change` / `breaking-change` ラベル（スキーマ変更や破壊的変更は他作業と競合しやすい）
     - 本文に DB マイグレーション・依存パッケージのメジャー更新・設定ファイル（CI / Lint / package.json 等）変更が含まれる旨の記述
   - **同一 parent の split-from**: `split-from:#<parent>` で同じ親を持つサブ Issue 群は、互いに関連コード変更する可能性が高いので **同一 parent 内では sequential**（別 parent の Issue とは並列可）
   - 上記すべて自動判定で、不明な場合は安全側に倒して sequential 化する（誤判定で並列にして失敗するより、保守的に処理した方が結果的に速い）
3. **巨大 Issue の自動分割（fan-out）**: 各 Issue について以下を満たすものは `/issue-split-auto #<n>` を `Agent(subagent_type=claude)` 経由で呼び出す:
   - 本文が 1500 文字以上 **かつ** H2 セクション (`## `) が 3 個以上
   - `bug` ラベルが付いていない
   - `split-from:#<m>` ラベルが付いていない（既に分割された子ではない）

   呼び出し prompt 例:
   ```
   /issue-split-auto #<n> を実行し、結果の JSON 1行だけを返してください。
   ```

   返ってきた JSON の `children` がある場合、キュー内の親番号 `<n>` を `children` の配列に置換する。`children` が空（分割不要判定）または `created: false` の場合は親のまま維持。
4. `.sweep/queue.txt` に Issue 番号を1行ずつ書き出す（空行・コメント禁止）
5. キュー件数とラベル別内訳をユーザーに表示する
6. 現在のブランチ（`git branch --show-current`）を「ベースブランチ」として表示する。違うブランチで進めたい場合はここでチェックアウトし直してから続行する
7. 「中止したい時は `/issue-sweep --abort` または `rm .sweep/queue.txt`」を1行案内する
8. **`.sweep/state.json` を初期化**:
   ```bash
   queue_total=$(wc -l < .sweep/queue.txt | tr -d ' ')
   jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         --argjson qt "$queue_total" --argjson mr "$max_rounds" \
         --arg mm "$merge_mode" '{
     skill: "issue-sweep",
     started_at: $now, updated_at: $now,
     phase: "iterating",
     queue_total: $qt, queue_remaining: $qt,
     processed_count: 0, merged_count: 0, failed_count: 0,
     round: 0, max_rounds: $mr,
     merge_mode: $mm,
     last_counts: {critical: null, major: null, minor: null},
     evidence: [],
     termination_reason: null
   }' > .sweep/state.json
   ```

## フェーズ2: 1 Issue ずつ処理（キューが空になるまでループ）

各反復で以下を完了させる。**反復冒頭で必ず以下を実行**:

```bash
# (1) lock の heartbeat 更新
echo "$PPID:$(date +%s)" > .sweep/lock

# (2) ベースブランチを最新化（直前のマージ分を取り込む）
git fetch origin "$base_branch" 2>/dev/null || true
git pull --ff-only origin "$base_branch" 2>/dev/null || true
```

これにより、各 Issue の worktree は**直前にマージされた変更を含む base から作られる**。同一 sweep 内で `develop` が次々進んでも、各 Issue は常に最新 base 上で実装される。fast-forward できない場合（local に余分なコミットがある等）は警告だけ出して続行する。

Stop Hook がキューに残行がある限り停止をブロックするため途中で止まらず流し続ける。

**重要 — context 設計:**
**1 Issue 分の実装（Plan→Develop→Review→Commit→Push→PR 作成→auto-merge 予約）は必ず `Agent` ツールでサブエージェントに丸投げする。** メインスレッドは「キュー操作 / 冪等性チェック / agent 起動 / マージ完了ポーリング / 失敗判定」だけを行う。これによりメイン context は Issue 数に対して線形に汚れず、PR URL の一覧だけが積まれる。

**並列実行モード（`--parallel N`、デフォルト N=5）:**
- 各反復の冒頭で「依存関係なし ∧ `serial-only` フラグなし ∧ 同 parent 並列でない先頭 N 件」を取得
- フェーズ1 で `serial-only` 判定された Issue は **必ず単独反復で処理**（他の Issue と同じバッチに入れない）
- N 件の Agent を **同一メッセージ内で並列起動**（`Agent` ツールを N 回呼ぶ）
- 全 agent の返答を集めた後、各 PR を順にポーリング（2-4）→ Issue close（2-5）→ キューから該当行を削除（2-6）
- worktree は branch 名で分離されるので衝突しない前提
- 上限は 5。それ以上は API rate limit と CI スロット競合のリスクが高い
- **ユーザーに並列度を確認しない**。デフォルト 5 で常に起動する。明示的に `--parallel N` が指定されたときだけその値を使う

### 2-1. キュー先頭の Issue 番号を取得
`head -n<N> .sweep/queue.txt`（`--parallel N` 指定時。デフォルト N=1）。依存先がキューに残っているものは除外する

### 2-2. 既存 PR の冪等性チェック（メインスレッド）

```bash
gh pr list --search "#<n> in:title,body" --state all --json number,state,mergedAt
```

判定:
- `state == MERGED` or `mergedAt != null` → **マージ済み**。2-5（キュー削除）へ
- `state == OPEN` → **既存 PR あり**。agent 起動（2-3）はスキップし、PR 番号を引き継いで 2-4（ポーリング）へ
- それ以外 → 通常フロー（2-3）

### 2-3. サブエージェントで Issue を1件丸ごと処理

**worktree スナップショット**: agent 起動前に `git worktree list --porcelain | grep '^worktree ' | awk '{print $2}' | sort > /tmp/wt-before` を実行（2-7 の差分検知で使用）。

`Agent` ツールを以下の指定で呼ぶ:

- `subagent_type`: `claude`（catch-all、全ツール利用可）
- `description`: `"Issue #<n> implementation"`
- `prompt`: 自己完結したプロンプトを渡す。**初回起動**と **CI fix 起動** の2モード:

**初回起動プロンプト:**

メインは `<MERGE_MODE>` プレースホルダを `auto` または `direct` に置換してから渡す。

```
Issue #<n> を1件、最後まで自律的に処理してください。メインスレッドには PR 情報だけを返します。
merge_mode: <MERGE_MODE>

手順:
1. `gh issue view <n> --json labels` でラベルを取得し、以下のマッピングでスキル選択:
   - bug → /bug-fix-wt #<n>
   - design → /design-fix #<n>
   - それ以外 → /impl-wt #<n>
2. 選択したスキルを Skill ツールで起動し、Plan→Develop→Review→Commit→Push→PR 作成まで完了させる。
   各サブスキルの禁止行動（フェーズスキップ・テスト省略・サイレントスキップ・スコープ外発見の未 issue 化）は厳守。
3. **PR 作成後、続けて `/refine --no-merge` を Skill ツールで起動し、4 観点（code-review / doc-drift / spec-audit、HALT 検知時は halt-review）で並列レビューして critical/major=0 ∧ minor≤5 まで研磨させる。マージは行わせない（--no-merge）**。refine の最終結果から `refine_status` / `critical_remaining` / `major_remaining` / `minor_remaining` を取得する。
4. **マージゲート判定**（必須）:
   - `critical_remaining == 0 ∧ major_remaining == 0` を満たす場合のみ次のいずれかでマージ予約する:
     - merge_mode=`auto`: `gh pr merge <PR番号> --auto --merge --delete-branch` で auto-merge 予約
     - merge_mode=`direct`: **マージコマンドは叩かず PR 作成までで返す**（メインが CI 緑後に直接 `gh pr merge --merge --delete-branch` する）
   - 上記を満たさない（refine が iter_limit や agent_failed で critical/major が残った）場合は **マージ予約せず、failure として返す**（手動対応が必要）
5. 完了したら以下の JSON 1行だけを最終メッセージとして返す:
   {"pr_number": <N>, "pr_url": "<URL>", "branch": "<branch>", "skill": "<使ったスキル名>", "refine_status": "<clean|iter_limit|agent_failed>", "refine_iters": <K>, "critical_remaining": <N>, "major_remaining": <N>, "minor_remaining": <N>}
6. マージゲート不合格時の failure JSON:
   {"failure": "refine threshold not met (critical=<C>, major=<M>)", "phase": "refine-gate", "pr_number": <N>, "pr_url": "<URL>"}
7. その他の失敗（実装失敗、PR 作成失敗等）:
   {"failure": "<1行で原因>", "phase": "<どのフェーズで失敗したか>"}

返答ルール:
- 上記 JSON 以外を最終メッセージに含めない（メインスレッドが parse する）。
- 「ユーザーに確認してから次へ進みます」等で停止しない。失敗または完了まで進める。
- マージ完了の待機はメインスレッドが行うので、agent は auto-merge 予約（auto モード時）または PR 作成（direct モード時）までで返す。
- **critical/major が残った状態でマージ予約してはならない**（4 のゲート判定を必ず通す）。
```

**CI fix 起動プロンプト**（メインスレッドが 2-4 ポーリング中に CI 失敗を検知した場合に使用）:

```
PR #<PR番号>（branch: <branch>）の CI で以下の check が失敗しました:
- <check名1>: <概要>
- <check名2>: <概要>

タスク:
1. `git fetch && git checkout <branch>` で対象 branch に切り替える（既存 worktree があれば再利用）。
2. 失敗 check のログを `gh run view --log-failed --job <job-id>` 等で取得し、原因を特定する。
3. 修正コミットを push する。テストが必要なら追加する。
4. auto モード: 予約は維持されているので push で CI 再走 → 緑になり次第サーバが自動マージする。direct モード: メインが CI 緑をポーリングして直接マージするので push まででよい。
5. 完了したら以下を返す:
   {"pr_number": <N>, "fixed": true, "commit": "<sha>"}
   修正不能なら:
   {"pr_number": <N>, "failure": "<1行で原因>"}

返答ルール: 上記 JSON 以外を最終メッセージに含めない。
```

agent の返答 JSON を parse して PR 番号を取得する。`failure` が返ったら 2-7（失敗時挙動）へ。

### 2-4. マージ完了をポーリング（メインスレッド）

`statusCheckRollup` と `mergeStateStatus` を含めて CI 失敗を確定検知する。**direct モード時**は全 check 完了 ∧ FAILURE なし ∧ まだ未マージのときに `gh pr merge <PR> --merge --delete-branch` を直接実行する:

```bash
respawn_count=0
while true; do
  payload=$(gh pr view <PR> --json state,mergedAt,statusCheckRollup,mergeStateStatus)
  state=$(echo "$payload" | jq -r .state)
  merged=$(echo "$payload" | jq -r '.mergedAt // "null"')
  failed_checks=$(echo "$payload" | jq -r '[.statusCheckRollup[]? | select(.conclusion == "FAILURE") | .name] | join(",")')
  pending=$(echo "$payload" | jq '[.statusCheckRollup[]? | select(.conclusion == null and .status != "COMPLETED")] | length')

  if [[ "$state" == "MERGED" ]]; then break; fi

  if [[ "$state" == "CLOSED" && "$merged" == "null" ]]; then
    # 手動 close 検知 → 1回目は agent 再起動、2回目はユーザー判断
    if (( respawn_count >= 1 )); then exit 1; fi
    respawn_count=$((respawn_count+1))
    # 2-3 の「初回起動プロンプト」で再 spawn → 2-2 冪等性チェックで既存 PR を処理
    continue
  fi

  if [[ -n "$failed_checks" && "$pending" -eq 0 ]]; then
    # CI 確定失敗 → CI fix 起動プロンプトで agent 再 spawn
    if (( respawn_count >= 2 )); then
      gh pr comment <PR> --body "sweep: CI が 3 回連続で失敗（checks: $failed_checks）。自動修正を諦めユーザー判断を仰ぎます。"
      sweep_notify "Manual intervention needed" "Issue #${n} PR #${PR}: CI 3回連続失敗 ($failed_checks)" ":rotating_light:"
      echo "CI が3回連続で失敗。ユーザー判断を仰ぐ。失敗 checks: $failed_checks" >&2
      exit 1
    fi
    respawn_count=$((respawn_count+1))
    # 監査ログとして PR にコメント
    gh pr comment <PR> --body "sweep: CI 失敗を検知（attempt ${respawn_count}/3、checks: $failed_checks）。修正 agent を再起動します。"
    # 通知
    sweep_notify "CI failed" "PR #${PR} attempt ${respawn_count}/3: $failed_checks" ":warning:"
    # 2-3 の「CI fix 起動プロンプト」を使って agent 起動。返答 fixed=true なら continue
    # ポーリングを継続（auto モード時は auto-merge 予約が残っているので、修正 push → CI 緑 → MERGED まで自動。direct モード時は次ループで全 check 完了を検知してメインがマージ）
    continue
  fi

  # direct モード時、全 check 完了 ∧ FAILURE なし ∧ 未マージなら直接マージ
  if [[ "$merge_mode" == "direct" && "$pending" -eq 0 && -z "$failed_checks" && "$state" == "OPEN" ]]; then
    if gh pr merge <PR> --merge --delete-branch 2>/tmp/merge-err; then
      sweep_notify "direct merge" "PR #${PR}" ":white_check_mark:"
      continue  # 次ループで state==MERGED を検知して break
    else
      err=$(cat /tmp/merge-err)
      sweep_notify "direct merge failed" "PR #${PR}: $err" ":x:"
      echo "direct merge failed for PR #${PR}: $err" >&2
      exit 1
    fi
  fi

  sleep 60
done
```

- ポーリング間隔 60s、上限なし
- ポーリング中はメインスレッドは sleep + `gh`/`jq` 呼び出しのみで「思考」しないので context は増えない
- 待ち中も Stop Hook がキューを見るのでメインは止まらない
- **CI 失敗判定**: `conclusion == FAILURE` の check が1つ以上 **かつ** `conclusion == null` の pending check が 0（全 check 完了）でのみ確定。pending があれば待ち続ける
- **respawn 上限**: 同一 PR で agent 再起動を **2回まで**。3回目で `gh run view` ログを添えてユーザーに判断を仰ぐ
- **CLOSED null**（手動 close）: 1回目は agent 再起動、2回目で諦める
- **direct モード時のマージ**: CI 全 check が COMPLETED（pending=0）∧ FAILURE 0 件 ∧ PR が OPEN のときにメインが `gh pr merge <PR> --merge --delete-branch` を実行

### 2-5. Issue を close（sweep 限定の振る舞い）

マージ完了後、対応する Issue を明示的に close する。CI 再実行回数も併記して監査性を上げる:

```bash
gh issue close <n> --comment "Closed by PR #<PR番号> (auto-merged via /issue-sweep, CI respawns=${respawn_count})"
sweep_notify "Merged" "#${n} (PR #${PR}, $(( $(date +%s) - start_ts ))s)" ":white_check_mark:"
```

- 親 sub-skill 群（impl-wt 等）は意図的に `Closes #N` を使わない設計だが、sweep ではマージ → close を直結したいので sweep 側で補う
- `split-from:#<parent>` ラベルが付いた子 Issue の場合、すべての兄弟 Issue が close されたかチェックし、全 close なら親 Issue も `gh issue close <parent> --comment "All split children merged"` で閉じる
- close に失敗（権限・既に closed 等）してもキュー処理は続行する

### 2-6. キューから先頭行を削除 + state.json 更新
**Issue close 完了後に実行**:
```bash
sed -i '1d' .sweep/queue.txt

# state.json を更新（処理済み 1 件分カウント・evidence append）
metrics_line=$(wc -l < .sweep/metrics.jsonl | tr -d ' ')
final_status=$(tail -n1 .sweep/metrics.jsonl | jq -r '.status // "merged"')
jq --arg ev ".sweep/metrics.jsonl:${metrics_line}" \
   --arg status "$final_status" \
   --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.queue_remaining = (.queue_remaining - 1)
    | .processed_count = (.processed_count + 1)
    | (if $status == "merged" then .merged_count = (.merged_count + 1) else .failed_count = (.failed_count + 1) end)
    | .evidence += [$ev]
    | .updated_at = $now' \
   .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
```

### 2-7. orphan worktree 掃除（毎反復末尾）

agent が成功/失敗どちらでも、その反復で作られた worktree が残っていれば掃除する:

```bash
# agent 起動前後の worktree 差分から「この反復で作られた」 path を特定
git worktree list --porcelain | grep '^worktree ' | awk '{print $2}' > /tmp/wt-after
# 比較対象は反復開始前にスナップショットした /tmp/wt-before
new_paths=$(comm -13 <(sort /tmp/wt-before) <(sort /tmp/wt-after))

# agent が failure を返したとき: 作成した worktree を強制削除
# agent が success を返し PR がマージ完了したとき: branch ごと削除（--delete-branch で remote 側は処理済み、local worktree のみ掃除）
for wt in $new_paths; do
  git worktree remove --force "$wt" 2>/dev/null || true
done
```

agent が `failure` を返した場合は同じ Issue で次回再起動時に worktree 衝突しないよう **必ず** 削除する。

### 2-8. 次の反復 / 失敗時
- 正常完了: 2-1 に戻る。停止しようとしても Stop Hook が押し戻す
- agent が `failure` を返した:
  - `gh issue comment <n> --body "sweep: 実装失敗（$failure）。手動対応が必要です。"`
  - `sweep_notify "Agent failed" "Issue #${n}: $failure" ":x:"`
  - キューはそのまま、ロックは削除してユーザーに報告して終了

## 禁止行動

- **PR マージ完了前にキューから Issue 番号を削除する**（最重要 — マージ忘れの根本原因）
- **メインスレッドで直接サブスキル（`/impl-wt` 等）を Skill ツール起動する**（context 汚染の根本原因。必ず `Agent` 経由）
- **メインスレッド自身がコードを修正する / コミットする / PR を編集する**（CTO は実装に手を出さない。修正は必ず CI fix 起動プロンプトで agent に委譲）
- **engineer agent 内で `/refine --no-merge` をスキップする**（4 観点レビューを通さず auto-merge に進むと品質ばらつきが出る）
- **反復冒頭の base branch 最新化をスキップする**（前 Issue のマージ分を取り込まず古い base で次を実装すると競合・無駄作業の原因）
- **ユーザーに並列度（--parallel）を確認する**（デフォルト 5 で常に起動。必要なら明示指定された値を使う）
- **spinoff 検出をスキップして sweep を終わらせる**（実装中に作られた子 Issue を放置すると「自律連続実装」の意味が薄れる。デフォルト 10 周まで自動追跡、spinoff 0 で自然終了）
- **「spinoff も追跡しますか？」「次の round に進みますか？」のような確認をユーザーに取る**（デフォルトで全 round 自動継続する。`--no-follow-spinoffs` が明示指定されているとき以外、ユーザーに二択を投げない）
- auto モードで auto-merge 予約をスキップして手動マージを促す（ずっと自律稼働するのが目的）
- **フェーズ0.5 の preflight をスキップして `merge_mode` を未確定のまま進める**（`allow_auto_merge=false` のまま auto モードで `gh pr merge --auto` を叩くと毎回 GraphQL エラーで止まる）
- **direct モードでメインが直接マージするのを忘れる**（agent は PR 作成までで返るため、メインがポーリングして CI 緑後にマージしないと sweep が永久に止まる）
- マージ完了確認をスキップして次の Issue に進む（PR が closed/CI fail なまま埋もれる）
- **CI 失敗を検知せずポーリングを継続する**（無限待機の原因）
- **失敗 check 名を agent に伝えず「とりあえず再実行」を頼む**（agent が原因不明のまま盲目的に手を入れる事故を防ぐ）
- agent の返答 JSON 以外をメイン context に取り込もうとする（agent 内部の Plan/Develop/Review ログをメインに残すのは禁止）
- 「ここで停止します」「次に進む前に確認してください」とユーザー判断を待って止まる（Stop Hook が押し戻す）
- ベースブランチを途中で変える
- フェーズ0 の lock 取得をスキップする
- **`.sweep/state.json` を `phase=terminal` にする前にキュー残数 = 0 と spinoff 検出済みを確認しない**（キュー処理途中で「ここで終わったことにする」のは禁止）
- **state.json の `evidence` 配列が空のままフェーズ3 に進む**（各 Issue 完了で metrics 行参照を必ず追加する）
- レポートに `## Evidence` セクションを書かない（state.json の evidence を必ず引用する形で残す）

## 通知（`.sweep/notify.url`）

プロジェクトごとに異なる Slack / Discord / ntfy.sh に通知できる。

**セットアップ:** リポジトリ直下に1行の URL を保存（`.gitignore` 対象）:

```bash
echo "https://hooks.slack.com/services/T0XXX/B0XXX/xxxx" > .sweep/notify.url
```

ファイルが**存在しなければ通知は何もしない**（CI 等で誤発火しない）。

**送信先の自動判別:** URL の文字列パターンで使い分ける:

| URL に含まれる文字列 | サービス | フォーマット |
|---|---|---|
| `hooks.slack.com` | Slack | `{"text": "..."}` JSON POST |
| `discord.com/api/webhooks` | Discord | `{"content": "..."}` JSON POST |
| `ntfy.sh` | ntfy.sh | POST body 平文 + `Title` / `Priority` ヘッダ |
| その他 | ntfy 互換 | 同上 |

**通知タイミング:**

| イベント | 通知内容 | 絵文字 |
|---|---|---|
| Issue マージ完了（2-5 直後） | `Merged #<n> (PR #<P>, <duration>)` | `:white_check_mark:` |
| CI 失敗検知（2-4 内） | `CI failed on PR #<P> (attempt <k>/3): <checks>` | `:warning:` |
| sweep が諦め（2-4 上限到達 / 2-8 agent failure） | `Manual intervention needed: #<n> — <理由>` | `:rotating_light:` |
| sweep 全完了（フェーズ3） | `Sweep done: <merged> merged, <failed> failed, elapsed <duration>` | `:checkered_flag:` |

**送信関数の実装例:**

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

## テレメトリ（`.sweep/metrics.jsonl`）

各 Issue の処理完了時 / 失敗時に **JSON 1行を append** する。後で `jq` で集計可能。

**書き出すタイミング:**
- 正常マージ完了（2-5 の Issue close 直後）
- agent failure（2-8 の失敗時挙動）
- CI 諦め（respawn 上限到達時）

**スキーマ:**

```json
{"ts":"<ISO8601>","issue":42,"skill":"impl-wt","duration_sec":423,"agent_attempts":1,"ci_respawns":0,"pr_number":127,"pr_url":"https://...","status":"merged"}
{"ts":"<ISO8601>","issue":51,"skill":"bug-fix-wt","duration_sec":1820,"agent_attempts":3,"ci_respawns":2,"pr_number":131,"pr_url":"https://...","status":"ci_gave_up","failed_checks":"unit-tests,lint"}
{"ts":"<ISO8601>","issue":53,"skill":null,"duration_sec":12,"agent_attempts":1,"ci_respawns":0,"pr_number":null,"pr_url":null,"status":"agent_failed","failure":"<理由>"}
```

**status 値:** `merged` / `ci_gave_up` / `agent_failed` / `aborted` / `manual_close`

**実装:** 2-1 で `start_ts=$(date +%s)` を記録し、2-5 / 2-8 の直前で:

```bash
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson issue "$n" \
  --arg skill "$skill_used" \
  --argjson dur "$(( $(date +%s) - start_ts ))" \
  --argjson att "$agent_attempts" \
  --argjson resp "$respawn_count" \
  --argjson pr "$pr_number" \
  --arg url "$pr_url" \
  --arg status "$status" \
  '{ts:$ts,issue:$issue,skill:$skill,duration_sec:$dur,agent_attempts:$att,ci_respawns:$resp,pr_number:$pr,pr_url:$url,status:$status}' \
  >> .sweep/metrics.jsonl
```

**集計例:**

```bash
# 直近 sweep の所要時間統計
jq -s 'group_by(.skill) | map({skill: .[0].skill, avg: (map(.duration_sec) | add/length | floor), n: length})' .sweep/metrics.jsonl

# 失敗率
jq -s '[.[] | select(.status != "merged")] | length' .sweep/metrics.jsonl

# CI respawn ヒートマップ
jq -s 'map(select(.ci_respawns > 0)) | group_by(.ci_respawns) | map({respawns: .[0].ci_respawns, n: length})' .sweep/metrics.jsonl
```

ファイルは `.gitignore` 対象。

## フェーズ3: 完了報告と spinoff 追跡

### 3-0. spinoff 検出と再 sweep 判定

実装中に `/spinoff-issue --parent #N` で作成された Issue が **キュー構築後** に生成されているため、それらを拾い直す:

```bash
# 今回 sweep が処理した親 Issue 番号一覧（フェーズ1 で展開した子 Issue を含む）
PROCESSED_IDS=$(jq -r --arg since "$sweep_start_iso" \
  'select(.ts >= $since and .source != "refine" and (.issue|tostring) != "") | .issue' \
  .sweep/metrics.jsonl | sort -u | tr '\n' ',' | sed 's/,$//')

# sweep 開始以降に作成された OPEN Issue を取得
new_issues=$(gh issue list --state open \
  --search "created:>=${sweep_start_iso}" \
  --json number,title,body,labels --limit 200)

# spinoff 由来を判定: 本文 "Parent: #N" / "parent:#N" / "Spun off from #N" or ラベル "parent:#N"
# のいずれかで PROCESSED_IDS と一致するものを抽出
spinoff_ids=$(echo "$new_issues" | jq -r --arg ids "$PROCESSED_IDS" '
  ($ids | split(",") | map(tonumber)) as $parents
  | .[]
  | select(
      (.labels[]?.name | tostring | capture("parent:#?(?<n>[0-9]+)")? | .n? | tonumber? // -1) as $lbl_parent
      | ((.body // "") | scan("[Pp]arent:\\s*#?([0-9]+)")[0]? // empty | tonumber) as $body_parent
      | ($lbl_parent != -1 and ($parents | index($lbl_parent)) != null)
        or ($body_parent != null and ($parents | index($body_parent)) != null)
    )
  | .number
')
```

判定:
- `spinoff_ids` が **空** → 通常の終了処理（3-1 以降）
- `spinoff_ids` がある かつ `--no-follow-spinoffs` 指定なし かつ `round_count < max_rounds`:
  - 通知 `sweep_notify "spinoffs detected" "${#spinoff_ids} 件を再 sweep" ":arrows_counterclockwise:"`
  - `round_count += 1` をインクリメント
  - `spinoff_ids` を新規キューとして `.sweep/queue.txt` に書き出す
  - **フェーズ2 に戻る**（ロック / 通知 URL / メトリクスは引き継ぎ、`sweep_start_iso` のみ次周開始時刻に更新）
- 上限到達または `--no-follow-spinoffs` 指定時:
  - レポートに「未処理 spinoffs」セクションを追加して列挙
  - 通知 `sweep_notify "spinoffs left unprocessed" "${#spinoff_ids} 件、要手動 sweep" ":warning:"`

### 3-1. 完了報告

1. 処理した Issue 番号と PR URL の一覧を表でまとめる（**全 round 通算**）
2. **`.sweep/metrics.jsonl` の今回 sweep 分から所要時間・失敗内訳を集計してユーザーに表示**
3. キューファイルが空（`wc -l .sweep/queue.txt` が 0）であることを確認
4. `git worktree prune` で残存 worktree を全削除
4b. **state.json を terminal 化**:
   ```bash
   # フェーズ3 到達時点で queue_remaining が 0 でなければ manual_intervention 扱い
   remaining=$(jq -r '.queue_remaining // 0' .sweep/state.json)
   if [[ "$remaining" == "0" ]]; then
     reason="queue_empty"
   else
     reason="manual_intervention"
   fi
   jq --arg reason "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.phase = "terminal" | .termination_reason = $reason | .updated_at = $now' \
      .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
   ```
5. **Markdown レポート生成** — `.sweep/report-sweep-<timestamp>.md` に書き出す（**`## Evidence` セクション必須**、state.json の `evidence` を引用）:

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
report=".sweep/report-sweep-${ts}.md"
sweep_start_iso=$(date -u -d @${sweep_start_ts} +%Y-%m-%dT%H:%M:%SZ)
mkdir -p .sweep
{
  echo "# issue-sweep report — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Summary"
  echo "- Started: $sweep_start_iso"
  echo "- Processed: $processed_count"
  echo "- Merged: $merged_count"
  echo "- Failed: $failed_count"
  echo "- Elapsed: ${total_dur}s"
  echo "- Base branch: $base_branch"
  echo "- Parallel: $parallel_n"
  echo
  echo "## Per-Issue"
  echo
  echo "| Issue | Skill | Duration | Status | PR | Respawns |"
  echo "|---|---|---|---|---|---|"
  jq -r --arg since "$sweep_start_iso" \
    'select(.ts >= $since and .source != "refine") |
     "| #\(.issue) | \(.skill // "-") | \(.duration_sec)s | \(.status) | \(.pr_url // "-") | \(.ci_respawns // 0) |"' \
    .sweep/metrics.jsonl
  echo
  echo "## Evidence"
  echo
  echo "（各 Issue 処理時に参照した metrics 行。state.json の evidence をそのまま列挙）"
  jq -r '.evidence[] | "- \(.)"' .sweep/state.json
  echo
  echo "## Failures & Manual Intervention"
  jq -r --arg since "$sweep_start_iso" \
    'select(.ts >= $since and .status != "merged") |
     "- **#\(.issue)** (\(.status)): \(.failure // .failed_checks // "-") — PR \(.pr_url // "n/a")"' \
    .sweep/metrics.jsonl
  if [[ -f .sweep/refine-metrics.jsonl ]]; then
    echo
    echo "## Recent refine runs（直近 24h）"
    cutoff=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)
    jq -r --arg c "$cutoff" \
      'select(.ts >= $c and .source == "refine") |
       "- PR #\(.pr_number) iter \(.iter): critical=\(.critical) major=\(.major) minor=\(.minor)"' \
      .sweep/refine-metrics.jsonl
  fi
} > "$report"
echo "Report: $report"
```

6. `rm -f .sweep/lock` でロック解除
7. **完了通知**: `sweep_notify "Sweep done" "${merged_count} merged, ${failed_count} failed (report: ${report})" ":checkered_flag:"`
8. ユーザーに最終サマリと**レポートパス**を返す

## 失敗時の挙動

- サブスキル失敗 / PR 作成失敗 / auto-merge 予約失敗のいずれも、Issue 番号をキューに残したまま中断し、ロック (`.sweep/lock`) は削除してユーザーに報告する
- ポーリング中の `CLOSED null` は1回目はサブスキル再実行、2回連続でユーザー判断
- キューファイルが壊れた場合は `--abort` で全削除してフェーズ1からやり直す
- 同じ Issue で2回連続して同じエラーが出たらユーザーに判断を仰ぐ（無限ループ防止）
