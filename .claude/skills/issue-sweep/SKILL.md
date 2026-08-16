---
name: issue-sweep
description: 複数のオープン Issue をキュー化し、Stop Hook と連動して端から自律的に実装・PR マージまで進める。
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
- `/issue-sweep --no-batch` — 関連 Issue のバッチ編成（フェーズ1-4）を無効化し、常に 1 Issue = 1 PR で処理する
- `/issue-sweep --no-follow-spinoffs` — sweep 中に spinoff された Issue を再 sweep するのを抑止（追跡ゼロ。検出結果はレポート列挙のみ）
- `/issue-sweep --max-rounds <N>` — spinoff 追跡の上限周回数（**デフォルト 1、最大 20**）。デフォルトでは「今回の sweep が直接生んだ spinoff」までを 1 周だけ処理し、**その spinoff がさらに生んだ孫 spinoff は追わない**（レポート列挙に落とす）。孫以降まで自律的に枯らしたい場合のみ明示的に大きい値を渡す
- `/issue-sweep --follow-all-spinoffs` — 追跡対象の重要度フィルタ（3-0 参照）を外し、検出した spinoff を重要度によらず全件再 sweep する

## 前提条件

- `gh` CLI が認証済み
- `.claude/hooks/check-issue-queue.sh` と `.claude/hooks/check-sweep-state.sh` が実行可能
- `settings.json` の Stop / SessionStart Hook が有効
- ベースブランチ（例: `develop`）にチェックアウト済み。各サブスキルはそのブランチをベースに PR を作る

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

引数が `--abort` の場合は `references/abort-and-recovery.md` の手順を実行して終了する（他フェーズに進まない）。

## フェーズ0: 多重起動チェック（lock 取得）

フェーズ1の前に必ず実行する。lock は **heartbeat 方式**で stale を判定する（PID 比較は Bash 子プロセス起動関係に左右されて脆いため使わない）。

1. `.sweep/lock` の存在確認
2. 存在する場合: ファイル内容 `<owner_pid>:<unix-ts>` を読み取り、`unix-ts` と現在時刻を比較
   - **2時間以内** → 他セッションが sweep 実行中。`echo "他セッションが sweep 実行中（lock の最終更新は <時刻>）。停止するには /issue-sweep --abort を実行"` と表示して終了
   - **2時間以上経過** → stale lock として `rm .sweep/lock` で削除して続行
3. ロック書き込み: `echo "$PPID:$(date +%s)" > .sweep/lock`
4. フェーズ2の各反復冒頭で **heartbeat 更新**: `echo "$PPID:$(date +%s)" > .sweep/lock`（lock の鮮度を保つ）
5. フェーズ3完了時 / 中断時 / `--abort` 時に必ず `rm -f .sweep/lock` する

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
   - **同一 parent の split-from（デフォルト sequential、安全と判断したら並列に上書き可）**: `split-from:#<parent>` で同じ親を持つサブ Issue 群は、互いに関連コード変更する可能性があるので**デフォルト sequential**。ただし以下の **並列セーフ条件** をすべて満たす Issue ペアは並列起動する（phase 初期実装で独立した雛形ファイルを各 Issue が触るようなケースを直列化しないため）:
     - 各 Issue 本文に「## スコープ」「## 影響範囲」「## ファイル」等のセクションがあり、対象ファイル / ディレクトリ集合が **disjoint**（共通要素なし）
     - どちらも `migration` / `schema-change` / `breaking-change` ラベルを持たない
     - どちらも `package.json` / `go.mod` / `bun.lock` / `.golangci.yml` / `biome.json` / `tsconfig.json` / `compose.yml` / `Makefile` / `.github/workflows/**` のような **shared 設定ファイル** に触る記述を本文に含まない（触ると兄弟全員と conflict する）
     - 本文に「依存: #N」「blocked by #N」等の明示依存がない
   - 上記すべて自動判定で、**並列セーフ条件の判定がつかない場合は sequential** に倒す（誤判定で並列にして失敗するより、保守的に処理した方が結果的に速い）
   - **並列上書きの記録**: split-from sequential を上書きして並列起動した Issue ペアは、起動直前にメインのテキスト出力で「#A と #B を並列起動（スコープ disjoint: A=apps/web/foo/, B=cmd/worker/bar/）」と 1 行宣言する（後でレポートから挙動を追えるように）
3. **Issue の自動分割（fan-out）**: 以下の除外条件に該当しない全 Issue について `/issue-split-auto #<n>` を `Agent(subagent_type=claude, model=sonnet)` 経由で呼び出す。**モデルは `sonnet` を明示する** — このステージは Issue 本文を読んでスコープ境界を切り出し JSON を返すだけで、コード生成も CI 突破も伴わない。Issue 数ぶん並列起動されるので単価が効く一方、判定を外しても親のまま維持されるだけで下方リスクが小さい。**文字数や H2 数のような表層メトリクスで事前フィルタしない** — 短くてもスコープが混在してることはあるし、長くても単一機能で分割不要なことはある。split-auto 側で本文と関連仕様書を実際に読んで判定させる:
   - `bug` ラベルが付いていない
   - `split-from:#<m>` ラベルが付いていない（既に分割された子ではない）

   呼び出し prompt 例:
   ```
   /issue-split-auto #<n> を実行し、結果の JSON 1行だけを返してください。
   ```

   返ってきた JSON の `children` がある場合、キュー内の親番号 `<n>` を `children` の配列に置換する。`children` が空（分割不要判定）または `created: false` の場合は親のまま維持。
4. **バッチ編成（1 worktree にまとめる Issue 群を決める）**: 分割後の Issue 群のうち、以下をすべて満たす組を 1 バッチにまとめる。バッチは **1 worktree / 1 ブランチ / 1 PR** で処理し、まとめてマージする:
   - 次のいずれかで関連が強い:
     - 同一 parent の `split-from:#<n>` 兄弟である
     - 本文の「## スコープ」「## 影響範囲」「## ファイル」等から読み取れる対象ファイル / ディレクトリ集合が **重なる**
   - `serial-only` / `no-parallel` / `isolated` / `migration` / `schema-change` / `breaking-change` のいずれのラベルも持たない
   - バッチ内に循環依存がない（「依存: #N」を辿って一列に並べられる）

   **2 の並列判定との関係**: 2 は「scope が disjoint だから別々に走らせて安全か」を見る。バッチは逆に「scope が近接しているから 1 本にまとめた方が得か」を見る。**2 で sequential に倒された Issue 群（特に同一 parent の split-from 兄弟）が最有力のバッチ候補**。バッチにまとめた Issue は互いに並列起動しない（同じ worktree で順に実装するため）。

   件数の上限は設けない。ただし **6 件以上のバッチを作る場合のみ**「#a,#b,… の N 件を 1 PR にまとめます（PR が大きくなります）」と 1 行宣言してから進む（確認は取らない）。
5. `.sweep/queue.txt` に **1 行 = 1 バッチ**で書き出す（空行・コメント禁止）。バッチはカンマ区切り、単独はそのまま:
   ```
   12,13,14
   27
   ```
6. キュー件数（バッチ数と Issue 総数）とラベル別内訳をユーザーに表示する
7. 現在のブランチ（`git branch --show-current`）を「ベースブランチ」として表示する。違うブランチで進めたい場合はここでチェックアウトし直してから続行する
8. 「中止したい時は `/issue-sweep --abort` または `rm .sweep/queue.txt`」を1行案内する
9. **`.sweep/state.json` を初期化**:
   ```bash
   queue_total=$(wc -l < .sweep/queue.txt | tr -d ' ')
   max_rounds=${max_rounds:-1}   # --max-rounds 未指定時のデフォルト
   jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         --argjson qt "$queue_total" --argjson mr "$max_rounds" '{
     skill: "issue-sweep",
     started_at: $now, updated_at: $now,
     phase: "iterating",
     queue_total: $qt, queue_remaining: $qt,
     processed_count: 0, merged_count: 0, failed_count: 0,
     round: 0, max_rounds: $mr,
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

これで各 Issue の worktree が**直前のマージを含む最新 base** から作られる。fast-forward できない場合（local に余分なコミットがある等）は警告だけ出して続行する。Stop Hook がキューに残行がある限り停止をブロックするので途中で止まらず流し続ける。

**重要 — context 設計:** **1 Issue 分の実装（Plan→Develop→Review→Commit→Push→PR 作成）は必ず `Agent` ツールに丸投げする。** メインスレッドは「キュー操作 / 冪等性チェック / agent 起動 / CI 緑ポーリング / 直接マージ / 失敗判定」だけを行い、メイン context には PR URL の一覧だけを積む。

**並列実行モード（`--parallel N`、デフォルト N=5）:**
- 各反復の冒頭で「依存関係なし ∧ `serial-only` フラグなし ∧ 同 parent 並列でない先頭 N 件」を取得
- フェーズ1 で `serial-only` 判定された Issue は **必ず単独反復で処理**（他の Issue と同じバッチに入れない）
- N 件の Agent を **同一メッセージ内で並列起動**（`Agent` ツールを N 回呼ぶ）
- 全 agent の返答を集めた後、各 PR を順にポーリング（2-4）→ Issue close（2-5）→ キューから該当行を削除（2-6）
- worktree は branch 名で分離されるので衝突しない前提
- 上限は 5。それ以上は API rate limit と CI スロット競合のリスクが高い

### 2-1. キュー先頭のバッチを取得
`head -n<N> .sweep/queue.txt`（N は `--parallel`、デフォルト 5）。**1 行 = 1 バッチ**なので、各行をカンマで分割して Issue 群にする（`12,13,14` → #12 #13 #14）。依存先がキューに残っているバッチは除外する。

並列度 N はバッチ単位で数える（バッチ内の Issue は同一 worktree で順に処理するので並列にはしない）。

### 2-2. 既存 PR の冪等性チェック（メインスレッド）

バッチのブランチ名（2-3 の規約 `sweep/issues-<a>-<b>-…`）で探す。無ければ Issue 番号でも探す（sweep 以外の経路で作られた PR を拾うため）:

```bash
gh pr list --head "sweep/issues-<a>-<b>" --state all --json number,state,mergedAt
# 見つからなければバッチ先頭の Issue 番号でフォールバック
gh pr list --search "#<a> in:title,body" --state all --json number,state,mergedAt
```

判定:
- `state == MERGED` or `mergedAt != null` → **マージ済み**。2-5（キュー削除）へ
- `state == OPEN` → **既存 PR あり**。agent 起動（2-3）はスキップし、PR 番号を引き継いで 2-4（ポーリング）へ
- それ以外 → 通常フロー（2-3）

### 2-3. サブエージェントでバッチを丸ごと処理

**バッチ件数で使うプロンプトを分ける**:
- **1 件** → 「初回起動プロンプト」（wt 版スキルが worktree ごと面倒を見る、従来どおり）
- **2 件以上** → 「バッチ起動プロンプト」（sweep 側で worktree を 1 つ作り、非 wt 版スキルを順に回して PR を 1 本にまとめる）


**worktree スナップショット**: agent 起動前に `git worktree list --porcelain | grep '^worktree ' | awk '{print $2}' | sort > /tmp/wt-before` を実行（2-7 の差分検知で使用）。

`Agent` ツールを以下の指定で呼ぶ:

- `subagent_type`: `claude`（catch-all、全ツール利用可）
- `description`: `"Issue #<n> implementation"`
- `prompt`: 自己完結したプロンプトを渡す。**初回起動**と **CI fix 起動** の2モード:

**初回起動プロンプト（バッチ件数 = 1）:**

```
Issue #<n> を1件、最後まで自律的に処理してください。メインスレッドには PR 情報だけを返します。

手順:
1. `gh issue view <n> --json labels` でラベルを取得し、以下のマッピングでスキル選択:
   - bug → /bug-fix-wt #<n>
   - design → /design-fix #<n>
   - それ以外 → /impl-wt #<n>
2. 選択したスキルを Skill ツールで起動し、Plan→Develop→Review→Commit→Push→PR 作成まで完了させる。
   各サブスキルの禁止行動（フェーズスキップ・テスト省略・サイレントスキップ・スコープ外発見の未 issue 化）は厳守。
3. **PR 作成後、続けて `/refine-git --no-merge` を Skill ツールで起動し、4 観点（code-review-git / doc-drift-git / spec-audit-git、HALT 検知時は halt-review）で並列レビューして critical/major=0 ∧ minor≤5 まで研磨させる。マージは行わせない（--no-merge）**。refine-git の最終結果から `refine_status` / `critical_remaining` / `major_remaining` / `minor_remaining` を取得する。
   **必ず `refine` ではなく `refine-git` を使う**（`refine` はリポジトリ全体が対象。Issue と無関係な既存問題でマージゲートが落ち続ける）。
4. **マージゲート判定**（必須）:
   - `critical_remaining == 0 ∧ major_remaining == 0` を満たす場合: **マージコマンドは叩かず PR 作成までで返す**（メインが CI 緑をポーリングして `gh pr merge <PR> --merge --delete-branch` を直接実行する）
   - 上記を満たさない（refine が iter_limit や agent_failed で critical/major が残った）場合は failure として返す（手動対応が必要）
5. 完了したら以下の JSON 1行だけを最終メッセージとして返す:
   {"pr_number": <N>, "pr_url": "<URL>", "branch": "<branch>", "skill": "<使ったスキル名>", "refine_status": "<clean|iter_limit|agent_failed>", "refine_iters": <K>, "critical_remaining": <N>, "major_remaining": <N>, "minor_remaining": <N>}
6. マージゲート不合格時の failure JSON:
   {"failure": "refine threshold not met (critical=<C>, major=<M>)", "phase": "refine-gate", "pr_number": <N>, "pr_url": "<URL>"}
7. その他の失敗（実装失敗、PR 作成失敗等）:
   {"failure": "<1行で原因>", "phase": "<どのフェーズで失敗したか>"}

返答ルール:
- 上記 JSON 以外を最終メッセージに含めない（メインスレッドが parse する）。
- 「ユーザーに確認してから次へ進みます」等で停止しない。失敗または完了まで進める。
- マージはメインスレッドが行うので、agent は PR 作成までで返す（`gh pr merge` は叩かない）。
- **critical/major が残った状態で 5 の success JSON を返してはならない**（4 のゲート判定を必ず通す）。
```

**バッチ起動プロンプト（バッチ件数 ≥ 2）:**

```
Issue #<a>, #<b>, #<c> を **1 つの worktree にまとめて** 処理してください。メインスレッドには PR 情報だけを返します。

手順:
1. worktree を 1 つ作る:
   git worktree add <repo>-sweep-<a> -b sweep/issues-<a>-<b>-<c> <base_branch>
   以降のすべての作業をこの worktree ディレクトリ内で行う。
2. 各 Issue を **依存順に** 1 件ずつ処理する。Issue ごとに `gh issue view <n> --json labels` でラベルを見てスキルを選ぶ:
   - bug → /bug-fix #<n>
   - それ以外 → /impl #<n>
   **wt 版（/impl-wt, /bug-fix-wt）は使わない**（worktree は 1 で作成済み。wt 版を呼ぶと worktree が二重に作られる）。
   起動時に「**複数 Issue を 1 ブランチに積むので PR は呼び出し元が作る。PR 作成はスキップして commit + push までで返すこと**」と明示する。
   各サブスキルのその他の禁止行動（フェーズスキップ・テスト省略・スコープ外発見の未 issue 化）は厳守。
3. 全 Issue の実装が終わったら push し、`gh pr create --base <base_branch>` で **PR を 1 本だけ** 作る:
   - タイトルに全 Issue 番号を含める
   - 本文に対象 Issue を全件列挙し、各 Issue でやったことを 1 行ずつ書く
   - `gh pr edit <PR番号> --add-issue <各 Issue URL>` で全件リンクする（Closes は使わない）
4. `/refine-git --no-merge --max-minor <5 × バッチ件数>` を Skill ツールで起動して研磨する。
   **minor 閾値を件数比例で渡すこと**（既定の 5 のままだと複数 Issue 分の差分では到達できず max_iter で打ち切られる）。
   **必ず `refine` ではなく `refine-git` を使う**（`refine` はリポジトリ全体が対象。Issue と無関係な既存問題でマージゲートが落ち続ける）。
5. **マージゲート判定**（必須）: `critical_remaining == 0 ∧ major_remaining == 0` ならマージコマンドは叩かず PR 作成までで返す（マージはメインの責務）。満たさなければ failure として返す。
6. 成功時の JSON 1行:
   {"issues": [<a>,<b>,<c>], "pr_number": <N>, "pr_url": "<URL>", "branch": "sweep/issues-<a>-<b>-<c>", "skills": ["<Issue ごとに使ったスキル>"], "refine_status": "<clean|iter_limit|agent_failed>", "refine_iters": <K>, "critical_remaining": <N>, "major_remaining": <N>, "minor_remaining": <N>}
7. 失敗時の JSON（**どの Issue で転んだかを必ず含める**。切り分けに使う）:
   {"failure": "<1行で原因>", "phase": "<どのフェーズ>", "failed_issue": <n>, "completed_issues": [<実装まで終わった Issue>], "pr_number": <あれば>, "pr_url": "<あれば>"}

返答ルール:
- 上記 JSON 以外を最終メッセージに含めない（メインスレッドが parse する）。
- 「ユーザーに確認してから次へ進みます」等で停止しない。失敗または完了まで進める。
- マージはメインスレッドが行う（`gh pr merge` は叩かない）。
- **critical/major が残った状態で 6 の success JSON を返してはならない**（5 のゲート判定を必ず通す）。
```

**CI fix 起動プロンプト**（メインスレッドが 2-4 ポーリング中に CI 失敗を検知した場合に使用。バッチでも PR は 1 本なのでそのまま使える）:

```
PR #<PR番号>（branch: <branch>）の CI で以下の check が失敗しました:
- <check名1>: <概要>
- <check名2>: <概要>

タスク:
1. `git fetch && git checkout <branch>` で対象 branch に切り替える（既存 worktree があれば再利用）。
2. 失敗 check のログを `gh run view --log-failed --job <job-id>` 等で取得し、原因を特定する。
3. 修正コミットを push する。テストが必要なら追加する。
4. push まででよい（メインが CI 再走の緑をポーリングして直接マージする）。
5. 完了したら以下を返す:
   {"pr_number": <N>, "fixed": true, "commit": "<sha>"}
   修正不能なら:
   {"pr_number": <N>, "failure": "<1行で原因>"}

返答ルール: 上記 JSON 以外を最終メッセージに含めない。
```

agent の返答 JSON を parse して PR 番号を取得する。`failure` が返ったら 2-7（失敗時挙動）へ。

### 2-4. CI 緑を待ってメインが直接マージ（メインスレッド）

`statusCheckRollup` をポーリングし、全 check 完了 ∧ FAILURE なし ∧ OPEN のときに `gh pr merge <PR> --merge --delete-branch` を直接実行する:

```bash
respawn_count=0
while true; do
  payload=$(gh pr view <PR> --json state,mergedAt,statusCheckRollup)
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
    gh pr comment <PR> --body "sweep: CI 失敗を検知（attempt ${respawn_count}/3、checks: $failed_checks）。修正 agent を再起動します。"
    sweep_notify "CI failed" "PR #${PR} attempt ${respawn_count}/3: $failed_checks" ":warning:"
    # 2-3 の「CI fix 起動プロンプト」を使って agent 起動。返答 fixed=true なら continue で次ループへ
    continue
  fi

  # 全 check 完了 ∧ FAILURE なし ∧ 未マージ → メインが直接マージ
  if [[ "$pending" -eq 0 && -z "$failed_checks" && "$state" == "OPEN" ]]; then
    if gh pr merge <PR> --merge --delete-branch 2>/tmp/merge-err; then
      sweep_notify "merged" "PR #${PR}" ":white_check_mark:"
      continue  # 次ループで state==MERGED を検知して break
    else
      err=$(cat /tmp/merge-err)
      sweep_notify "merge failed" "PR #${PR}: $err" ":x:"
      echo "merge failed for PR #${PR}: $err" >&2
      exit 1
    fi
  fi

  sleep 60
done
```

- ポーリング中のメインは sleep + `gh`/`jq` のみで「思考」しないので context は増えず、Stop Hook がキューを見るので止まらない
- respawn 上限（同一 PR で agent 再起動 2 回）に達したら `gh run view` のログを添えてユーザー判断を仰ぐ

### 2-5. Issue を close（sweep 限定の振る舞い）

マージ完了後、対応する Issue を明示的に close する。CI 再実行回数も併記して監査性を上げる:

**バッチ内の全 Issue を close する**（1 PR が複数 Issue を閉じる）:

```bash
for n in $batch_issues; do   # バッチのカンマ区切りを空白区切りにしたもの
  gh issue close "$n" --comment "Closed by PR #<PR番号> (merged via /issue-sweep, CI respawns=${respawn_count})" || true
done
sweep_notify "Merged" "#$(echo $batch_issues | tr ' ' ',') (PR #${PR}, $(( $(date +%s) - start_ts ))s)" ":white_check_mark:"
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
- **engineer agent 内で `/refine-git --no-merge` をスキップする**（4 観点レビューを通さずマージに進むと品質ばらつきが出る）
- **engineer agent 内で `refine-git` の代わりに `refine` を起動する**（全体スキャンになり、Issue と無関係な既存指摘でマージゲートが永久に落ちる）
- **反復冒頭の base branch 最新化をスキップする**（前 Issue のマージ分を取り込まず古い base で次を実装すると競合・無駄作業の原因）
- **ユーザーに並列度（--parallel）を確認する**（デフォルト 5 で常に起動。必要なら明示指定された値を使う）
- **spinoff 検出（3-0）自体をスキップして sweep を終わらせる**（実装中に作られた子 Issue の存在を報告しないのは禁止。追跡しない分は必ずレポートに列挙する）
- **`max_rounds` のデフォルトを自己判断で 1 より大きくする**（1 round = spinoff 件数ぶんの `impl-wt` フルサイクル。増やすのはユーザーが明示指定した時だけ）
- **重要度フィルタで落ちた spinoff（`spinoff_deferred`）をレポートに書かずに捨てる**
- **「spinoff も追跡しますか？」「次の round に進みますか？」のような確認をユーザーに取る**（`max_rounds` の範囲内で自動継続し、超えたら黙って列挙に落とす。ユーザーに二択を投げない）
- **メインが CI 緑後にマージするのを忘れる / マージ完了を確認せず次の Issue に進む**（agent は PR 作成までで返るため、メインがポーリングして直接マージしないと sweep が永久に止まり、PR が closed/CI fail のまま埋もれる）
- **agent 内で `gh pr merge` を叩く**（マージはメインの責務。agent は PR 作成までで返す）
- **CI 失敗を検知せずポーリングを継続する**（無限待機の原因）
- **失敗 check 名を agent に伝えず「とりあえず再実行」を頼む**（agent が原因不明のまま盲目的に手を入れる事故を防ぐ）
- agent の返答 JSON 以外をメイン context に取り込もうとする（agent 内部の Plan/Develop/Review ログをメインに残すのは禁止）
- 「ここで停止します」「次に進む前に確認してください」とユーザー判断を待って止まる（Stop Hook が押し戻す）
- ベースブランチを途中で変える
- フェーズ0 の lock 取得をスキップする
- **バッチ（2 件以上）で wt 版スキル（`/impl-wt`, `/bug-fix-wt`）を呼ぶ**（worktree が二重に作られる。バッチでは sweep 側が作った worktree 内で非 wt 版を使う）
- **バッチで `refine-git` の `--max-minor` を件数比例にせず既定の 5 のまま呼ぶ**（複数 Issue 分の差分では閾値に到達できず `max_iter` で打ち切られる）
- **バッチの一部 Issue だけ close してキューから消す**（マージされた PR が閉じるはずの Issue を取りこぼす。2-5 で全件 close する）
- **`.sweep/state.json` を `phase=terminal` にする前にキュー残数 = 0 と spinoff 検出済みを確認しない**（キュー処理途中で「ここで終わったことにする」のは禁止）
- **state.json の `evidence` が空のままフェーズ3 に進む / レポートに `## Evidence` を書かない**（各 Issue 完了で metrics 行参照を追加し、レポートではそれを引用する）

## 通知（`.sweep/notify.url`）

各所で `sweep_notify "<title>" "<msg>" "<emoji>"` を呼ぶ。**`.sweep/notify.url` が存在しなければ通知は完全に no-op** なので、無ければ呼び出し箇所ごと無視してよい。存在する場合のみ `references/notifications.md` を読み、関数定義と通知タイミング表に従う。

## テレメトリ（`.sweep/metrics.jsonl`）

各**バッチ**の処理完了時 / 失敗時に **JSON 1行を append** する（バッチ = 1 PR）。後で `jq` で集計可能。

**書き出すタイミング:**
- 正常マージ完了（2-5 の Issue close 直後）
- agent failure（2-8 の失敗時挙動）
- CI 諦め（respawn 上限到達時）

**スキーマ:**

`issues` がバッチの全 Issue、`issue` はその先頭（既存クエリとの後方互換のため残す）。

```json
{"ts":"<ISO8601>","issue":42,"issues":[42],"skill":"impl-wt","duration_sec":423,"agent_attempts":1,"ci_respawns":0,"pr_number":127,"pr_url":"https://...","status":"merged"}
{"ts":"<ISO8601>","issue":12,"issues":[12,13,14],"skill":"impl","duration_sec":2140,"agent_attempts":1,"ci_respawns":0,"pr_number":129,"pr_url":"https://...","status":"merged"}
{"ts":"<ISO8601>","issue":51,"issues":[51],"skill":"bug-fix-wt","duration_sec":1820,"agent_attempts":3,"ci_respawns":2,"pr_number":131,"pr_url":"https://...","status":"ci_gave_up","failed_checks":"unit-tests,lint"}
{"ts":"<ISO8601>","issue":53,"issues":[53],"skill":null,"duration_sec":12,"agent_attempts":1,"ci_respawns":0,"pr_number":null,"pr_url":null,"status":"agent_failed","failure":"<理由>","failed_issue":53}
```

**status 値:** `merged` / `ci_gave_up` / `agent_failed` / `aborted` / `manual_close`

**実装:** 2-1 で `start_ts=$(date +%s)` を記録し、2-5 / 2-8 の直前で:

```bash
issues=$(printf '%s\n' $batch_issues | jq -sc 'map(tonumber)')   # バッチの全 Issue
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson issues "$issues" \
  --arg skill "$skill_used" \
  --argjson dur "$(( $(date +%s) - start_ts ))" \
  --argjson att "$agent_attempts" \
  --argjson resp "$respawn_count" \
  --argjson pr "$pr_number" \
  --arg url "$pr_url" \
  --arg status "$status" \
  '{ts:$ts,issue:$issues[0],issues:$issues,skill:$skill,duration_sec:$dur,agent_attempts:$att,ci_respawns:$resp,pr_number:$pr,pr_url:$url,status:$status}' \
  >> .sweep/metrics.jsonl
```

集計クエリは `references/metrics-queries.md`（フェーズ3-1 で使う）。ファイルは `.gitignore` 対象。

## フェーズ3: 完了報告と spinoff 追跡

### 3-0. spinoff 検出と再 sweep 判定

実装中の発見が `impl-wt` のフェーズ3 で `/spinoff-issue --batch` により **キュー構築後** に起票されているため、それらを拾い直す:

```bash
# 今回 sweep が処理した親 Issue 番号一覧（フェーズ1 で展開した子 Issue を含む）
PROCESSED_IDS=$(jq -r --arg since "$sweep_start_iso" \
  'select(.ts >= $since and ((.source // "") | startswith("refine") | not))
   | if .issues then .issues[] else .issue end
   | select(. != null)' \
  .sweep/metrics.jsonl | sort -u | tr '\n' ',' | sed 's/,$//')

# sweep 開始以降に作成された OPEN Issue を取得
new_issues=$(gh issue list --state open \
  --search "created:>=${sweep_start_iso}" \
  --json number,title,body,labels --limit 200)

# spinoff 由来を判定: /spinoff-issue が付与する `spinoff` ラベルを主シグナルとし、
# 本文 "元: #N"（spinoff-issue のテンプレ）または "Parent: #N"（後方互換）から親番号を取り出し、
# PROCESSED_IDS と一致するものを抽出
#   `high` = 再 sweep（impl-wt フルサイクル）まで自動で回す重要度かどうか
spinoff_json=$(echo "$new_issues" | jq -c --arg ids "$PROCESSED_IDS" '
  ($ids | split(",") | map(tonumber)) as $parents
  | [ .[]
      | select(([.labels[]?.name] | index("spinoff")) != null)
      | select(
          # scan はキャプチャ付きだと [["3"]] を返すので flatten してから数値化する
          ( [ .body // "" | scan("(?:元|[Pp]arent):\\s*#?([0-9]+)") ] | flatten | .[0]? | tonumber? ) as $body_parent
          | $body_parent != null and ($parents | index($body_parent)) != null
        )
      | { number,
          high: ([.labels[]?.name]
                 | any(. == "severity:critical" or . == "severity:high" or . == "priority:high")) }
    ]')

spinoff_all=$(echo "$spinoff_json" | jq -r '.[].number')
# 再 sweep 対象は重要度の高いものだけ。--follow-all-spinoffs 指定時は spinoff_all をそのまま使う
spinoff_ids=$(echo "$spinoff_json" | jq -r '.[] | select(.high) | .number')
spinoff_deferred=$(echo "$spinoff_json" | jq -r '.[] | select(.high | not) | .number')
```

判定:
- `spinoff_all` が **空** → 通常の終了処理（3-1 以降）
- `spinoff_ids` がある かつ `--no-follow-spinoffs` 指定なし かつ `round_count < max_rounds`（**デフォルト 1**）:
  - 通知 `sweep_notify "spinoffs detected" "${#spinoff_ids} 件を再 sweep" ":arrows_counterclockwise:"`
  - `round_count += 1` をインクリメント
  - `spinoff_ids` を新規キューとして `.sweep/queue.txt` に書き出す
  - **フェーズ2 に戻る**（ロック / 通知 URL / メトリクスは引き継ぎ、`sweep_start_iso` のみ次周開始時刻に更新）
- 上限到達（デフォルトでは 2 周目に入ろうとした時点で必ずここに来る）または `--no-follow-spinoffs` 指定時:
  - レポートに「未処理 spinoffs」セクションを追加して `spinoff_all` を列挙
  - 通知 `sweep_notify "spinoffs left unprocessed" "${#spinoff_all} 件、要手動 sweep" ":warning:"`
- `spinoff_deferred` が空でない場合は、再 sweep の有無にかかわらずレポートに **「未追跡 spinoffs（重要度フィルタで対象外）」** セクションを追加して列挙する（黙って握り潰さない）

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
  echo "| Issues | Skill | Duration | Status | PR | Respawns |"
  echo "|---|---|---|---|---|---|"
  jq -r --arg since "$sweep_start_iso" \
    'select(.ts >= $since and ((.source // "") | startswith("refine") | not)) |
     "| \((.issues // [.issue]) | map("#\(.)") | join(", ")) | \(.skill // "-") | \(.duration_sec)s | \(.status) | \(.pr_url // "-") | \(.ci_respawns // 0) |"' \
    .sweep/metrics.jsonl
  echo
  echo "## Evidence"
  echo
  echo "（各 Issue 処理時に参照した metrics 行。state.json の evidence をそのまま列挙）"
  jq -r '.evidence[] | "- \(.)"' .sweep/state.json
  echo
  echo "## Failures & Manual Intervention"
  jq -r --arg since "$sweep_start_iso" \
    'select(.ts >= $since and ((.source // "") | startswith("refine") | not) and .status != "merged") |
     "- **\((.issues // [.issue]) | map("#\(.)") | join(", "))** (\(.status))\(if .failed_issue then " — 転んだのは #\(.failed_issue)" else "" end): \(.failure // .failed_checks // "-") — PR \(.pr_url // "n/a")"' \
    .sweep/metrics.jsonl
  if [[ -f .sweep/refine-metrics.jsonl ]]; then
    echo
    echo "## Recent refine runs（直近 24h）"
    cutoff=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)
    jq -r --arg c "$cutoff" \
      'select(.ts >= $c and (.source | startswith("refine"))) |
       "- [\(.source)] PR #\(.pr_number) iter \(.iter): critical=\(.critical) major=\(.major) minor=\(.minor)"' \
      .sweep/refine-metrics.jsonl
  fi
} > "$report"
echo "Report: $report"
```

6. `rm -f .sweep/lock` でロック解除
7. **完了通知**: `sweep_notify "Sweep done" "${merged_count} merged, ${failed_count} failed (report: ${report})" ":checkered_flag:"`
8. ユーザーに最終サマリと**レポートパス**を返す

## 失敗時の挙動

`references/abort-and-recovery.md` を参照（失敗が起きたときだけ読めばよい）。
