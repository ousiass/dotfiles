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
- `/issue-sweep --parallel <N>` — **同時に走る実装 agent 数**の上限（**デフォルト 5**、上限 5）。ユーザーに値を確認せず常にこのデフォルトで起動する
- `/issue-sweep --max-inflight <M>` — **同時に抱える未マージ PR 数**の上限（実装中 + CI 待ち + マージ待ち。**デフォルト 10**、上限 15）。CI 待ちが実装スロットを食い潰さないよう `--parallel` とは別枠
- `/issue-sweep --no-batch` — 関連 Issue のバッチ編成（フェーズ1-4）を無効化し、常に 1 Issue = 1 PR で処理する
- `/issue-sweep --no-follow-spinoffs` — sweep 中に spinoff された Issue を再 sweep するのを抑止（追跡ゼロ。検出結果はレポート列挙のみ）
- `/issue-sweep --max-rounds <N>` — spinoff 追跡の上限周回数（**デフォルト 1、最大 20**）。デフォルトでは「今回の sweep が直接生んだ spinoff」までを 1 周だけ処理し、**その spinoff がさらに生んだ孫 spinoff は追わない**（レポート列挙に落とす）。孫以降まで自律的に枯らしたい場合のみ明示的に大きい値を渡す
- `/issue-sweep --follow-all-spinoffs` — 追跡対象の重要度フィルタ（3-0 参照）を外し、検出した spinoff を重要度によらず全件再 sweep する
- `/issue-sweep --single-pr` — **1 統合ブランチ集約モード**。バッチごとに PR を作らず統合ブランチ 1 本に積み、最後にベースブランチへ PR を 1 本だけ出す（後述の「single-pr モード」）
- `/issue-sweep --multi-pr` — バッチごとに PR を作る従来モード
- `/issue-sweep --base <branch>` — ベースブランチ（PR のマージ先）
- `/issue-sweep --branch <name>` — single-pr モードの統合ブランチ名。デフォルト `sweep/issue-sweep-<YYYYmmdd-HHMMSS>`

**`--single-pr` / `--multi-pr` と `--base` は、指定がなければフェーズ P-0 で `AskUserQuestion` で必ず聞く。推測で決めない。**

## 前提条件

- `gh` CLI が認証済み
- `.claude/hooks/check-issue-queue.sh` と `.claude/hooks/check-sweep-state.sh` が実行可能
- `settings.json` の Stop / SessionStart Hook が有効
- ベースブランチは**フェーズ P-0 でユーザーに確認して確定する**（`references/branch-preflight.md`）。起動時の HEAD がどこであっても、それを推測でベースに採用しない

**`.sweep/` の場所（最初に必ず設定する）:** worktree 内で走るサブスキルと同じファイルを見るため、**常にメインリポジトリ側**を指す:

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
mkdir -p "$SWEEP_DIR"
```

以降 `.sweep/...` と書かれた箇所はすべて `$SWEEP_DIR/...` を指す。Stop Hook も同じパスを見る。

## 状態管理 `.sweep/state.json`

sweep 系スキル共通の進行状態ファイル。Stop Hook (`check-sweep-state.sh`) は `phase != "terminal"` の間（lock が新鮮な限り）停止をブロックする。**「キューが空っぽいから終わった」と推定で `phase=terminal` にしてはならない**。terminal 化前にキュー残数 = 0 と spinoff 検出済みを必ず確認する。

**このファイルは sweep が所有する。** worktree 内で走る `refine-git` 等は `refine/references/common-setup.md` 手順4 の所有権ガードで書き込みを控えるので、sweep 実行中に横から terminal 化されることはない。

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
  "termination_reason": null | "queue_empty" | "manual_intervention" | "batch_failed" | "aborted"
}
```

**監査証跡は `$SWEEP_DIR/metrics.jsonl` 一本。** state.json に metrics の行番号を写す `evidence` 配列と、null 固定だった `last_counts` は廃止した（Stop Hook は `phase` と lock の鮮度だけで判定しており、evidence は表示にしか使っていなかった）。

**更新タイミング:**
- フェーズ0/1 でキュー構築完了後に `phase=iterating, queue_total, queue_remaining=queue_total, processed_count=0, ...` で初期化
- 各バッチ完了ごとに `queue_remaining -= 1`, `processed_count += 1`, `merged_count` or `failed_count` をインクリメント、`updated_at` 更新
- spinoff 追跡 round 更新時に `round += 1`、`queue_remaining` を新キューサイズに更新
- フェーズ3 終了時に `phase=terminal` + `termination_reason` をセット。**失敗で打ち切る場合も必ず terminal 化してレポートを出す**（`phase=iterating` のまま放置すると記録が何も残らない）

## --abort 処理

引数が `--abort` の場合は `references/abort-and-recovery.md` の手順を実行して終了する（他フェーズに進まない）。

## single-pr モード（`--single-pr`）

**バッチごとに PR を作らず、最初に切った統合ブランチ 1 本へ全部積み、最後にベースブランチへ PR を 1 本だけ出す。** 有効時は **`references/single-branch-mode.md` を読んでから**フェーズ0 に入る。フェーズ順は:

`フェーズ0（lock）→ P-0（モード・ベース確定）→ S-0（統合ブランチ作成）→ フェーズ1（キュー構築）→ フェーズ2（S-1 の差分を適用）→ 3-0（spinoff 判定）→ S-2（統合研磨・最終 PR・CI 確認）→ S-3（レポート）`

通常モードからの差分は以下の箇所だけ。他はすべてそのまま:

| 箇所 | single-pr での差し替え |
|---|---|
| P-0 の直後 | S-0 を実行。P-0 で確定したベースから統合ブランチを切って push する |
| 1-5 の提示 | 「ベースブランチ」の代わりに `base → 統合ブランチ → 最終 1 PR` を提示する |
| 1-6 の state.json | `mode` / `base_branch` / `int_branch` / `pr_number` / `integrated_count` を追加（S-0-3） |
| 2-0 の PR 一覧取得 | 不要（in-flight に PR が居ない）。heartbeat と base 最新化のみ行う |
| 2-1 の冪等性チェック | PR ではなく **ローカルブランチ `<work_branch>` の有無**で判定する。統合済み（`git merge-base --is-ancestor` が真）ならキュー行を削除して次へ |
| 2-2 の agent プロンプト | worktree の分岐元を `$int_branch` に、`gh pr create` と**手順4 の `/refine-git` を禁止**（研磨は S-2-0 で統合ブランチにまとめて 1 回）、手順5 のマージゲートは「テストと lint が通ること」に読み替え、返答 JSON は `pr_number` の代わりに `work_branch`（S-1） |
| 2-3 の判定表 | PR 状態の観測ではなく **agent 返答 → 統合 merge**。競合時は rebase agent 1 回 → 諦め（S-1） |
| 2-4 の Issue close | close しない。**最終 PR は sweep がマージしないので Issue も閉じない**。S-3 で「マージ後に close する Issue」として列挙するだけ |
| 3-1 の完了報告 | S-2 → S-3 を実行してからレポートを書く。Summary にモード・ベース・統合ブランチ・PR URL（**open のまま**）を必ず入れる |

## フェーズ0: 多重起動チェック（lock 取得）

フェーズ1の前に必ず実行する。lock は **heartbeat 方式**で stale を判定する（PID 比較は Bash 子プロセス起動関係に左右されて脆いため使わない）。

1. `$SWEEP_DIR/lock` の存在確認
2. 存在する場合: ファイル内容 `<owner_pid>:<unix-ts>` を読み取り、`unix-ts` と現在時刻を比較
   - **2時間以内** → 他セッションが sweep 実行中。`echo "他セッションが sweep 実行中（lock の最終更新は <時刻>）。停止するには /issue-sweep --abort を実行"` と表示して終了
   - **2時間以上経過** → stale lock として `rm "$SWEEP_DIR/lock"` で削除して続行
3. ロック書き込み: `echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"`
4. フェーズ2の各ラウンド冒頭で **heartbeat 更新**（2-0）
5. フェーズ3完了時 / 中断時 / `--abort` 時に必ず `rm -f "$SWEEP_DIR/lock"` する

## フェーズ P-0: モードとベースブランチの確定（必須）

**`references/branch-preflight.md` を読んでその手順どおりに実行する。スキップ不可。**
`--single-pr` / `--multi-pr` と `--base` の両方が引数で確定している場合のみ、ヒアリング（P-0-2）を省略できる。

ここで確定するもの:

- `mode`（`single-pr` = 統合ブランチ 1 本＋最終 1 PR / `multi-pr` = バッチごとに PR）
- `base_branch`（PR のマージ先。**現在の HEAD を推測で採用しない**）
- `main_worktree` と事前ガード関数 `assert_not_base`

`mode=single-pr` なら続けて S-0 へ、`multi-pr` ならフェーズ1 へ進む。

## フェーズ1: Issue キューの構築

### 1-1. 対象 Issue の取得

引数を解釈して対象を集める:

- 引数なし: `gh issue list --state open --json number,labels,title --limit 200`
- `label:<name>`: 同上に `--label <name>`
- `#<n>` 列挙: `gh issue list --state open --json number,labels,title --limit 200` を 1 回だけ叩き、その結果から指定番号を抽出する（Issue ごとに `gh issue view` を叩かない）

**親 Issue の自動展開**: `split-from:` ラベル付きの Issue を **1 コールでまとめて**取得し、ローカルで親ごとに束ねる（以前は Issue ごとに `gh issue list --search` を叩いていた）:

```bash
gh issue list --state open --search "label:split-from" \
  --json number,labels,title --limit 200
```

- 対象に含まれる `#<n>` が上記の結果に子を持っていた場合、その親は **トラッカーとみなしキューから除外**し、子 Issue 群をキューに含める
- 子を持たない `#<n>` はそれ自身をキューに残す
- これにより `/issue-sweep #100`（5 子持ちのフェーズ Issue）で「そのフェーズの 5 件だけ」を端から処理できる

### 1-2. Issue 解析（1 Issue = 1 agent = 1 パス）

**Issue 本文の読み取りはここだけ。** 以前は「依存・並列禁止の判定」「`issue-split-auto` の分割判定」「バッチ編成のスコープ読み取り」で同じ本文を 3 回読んでいた。1 回の解析でまとめて返させる。

`bug` ラベル付き、または `split-from:` ラベル付き（既に分割された子）の Issue は**分割判定だけスキップし、スコープ / 依存の解析は行う**。

`Agent(subagent_type=claude, model=sonnet)` で起動する。**モデルは `sonnet` を明示する** — 本文と関連仕様書を読んで JSON を返すだけで、コード生成も CI 突破も伴わない。**同時起動は最大 5 件**（`--parallel` とは独立の固定上限）。6 件以上あれば 5 件ずつのウェーブに分け、各ウェーブが揃ってから次を出す。

```
Issue #<n> を解析して JSON 1行だけを返してください。実装は一切しないこと。

1. 分割判定（`bug` / `split-from:` ラベルが付いている場合はこの手順をスキップ）:
   `/issue-split-auto #<n>` を Skill ツールで実行し、スコープが混在していれば子 Issue に分割する。
   **文字数や H2 数のような表層メトリクスで事前に判断しない** — 短くてもスコープが混在している
   ことはあるし、長くても単一機能で分割不要なことはある。本文と関連仕様書を実際に読んで判定する。
2. 分割後の各 Issue（分割しなかった場合は #<n> 自身）について、本文から以下を読み取る:
   - `scope`: 「## スコープ」「## 影響範囲」「## ファイル」等から読み取れる対象ファイル /
     ディレクトリのパス集合。読み取れなければ空配列
   - `depends_on`: 「依存: #N」「blocked by #N」「Depends on #N」「Closes/Fixes #N」の番号
   - `serial_only`: 次のいずれかに該当すれば true
     - `serial-only` / `no-parallel` / `isolated` ラベル
     - 本文に「並列禁止」「sequential only」「do not parallelize」等の明示記述
     - `migration` / `schema-change` / `breaking-change` ラベル
     - 本文に DB マイグレーション・依存パッケージのメジャー更新・設定ファイル
       （CI / Lint / package.json 等）変更が含まれる旨の記述
   - `priority`: `priority:p0` / `p1` 等のラベルがあればその値

返す JSON（分割しなかった場合は units が 1 要素）:
{"parent": <n>, "split": <true|false>, "units": [{"issue": <n>, "scope": ["apps/web/foo/"], "depends_on": [12], "serial_only": false, "priority": "p1"}]}

失敗時: {"parent": <n>, "error": "<1行で原因>"}

返答ルール: 上記 JSON 以外を最終メッセージに含めない。
```

`error` が返った Issue は分割せず単独バッチとして扱い、`scope` は空・`serial_only` は false とみなす（解析失敗で sweep を止めない）。

### 1-3. バッチ編成

1-2 が返した `units` を材料に、**メインスレッドは本文を読まずに**組を作る。バッチは **1 worktree / 1 ブランチ / 1 PR** で処理し、まとめてマージする:

- **`scope` が重なる unit、または同一 parent の兄弟は同じバッチにまとめる**（同じ worktree で順に実装するので conflict しない）
- **`scope` が disjoint な unit は別のバッチにする**
- **`scope` が空（読み取れなかった）unit は、同一 parent の兄弟がいればそのバッチに寄せる。兄弟もいなければ単独バッチ**（誤判定で無関係な Issue を 1 PR に混ぜるより保守的に倒す）
- `serial_only` の unit は他と混ぜず単独バッチ
- バッチ内は `depends_on` を辿って一列に並べる。循環していたら分割する
- `priority` の高いバッチを先頭に、`depends_on` の依存先バッチはその前に置く

**並列度はバッチ編成の結果として決まる。** 同じバッチ = 直列（1 worktree で順に実装）、別のバッチ = 並列。スコープの重なり判定はこの 1 箇所だけで、他のどこでもやらない。

件数の上限は設けない。ただし **6 件以上のバッチを作る場合のみ**「#a,#b,… の N 件を 1 PR にまとめます（PR が大きくなります）」と 1 行宣言してから進む（確認は取らない）。

### 1-4. キューの書き出し

`$SWEEP_DIR/queue.txt` に **1 行 = 1 バッチ**で書き出す（空行・コメント禁止）。バッチはカンマ区切り、単独はそのまま:

```
12,13,14
27
```

同時に `$SWEEP_DIR/attempts.json` を `{}` で初期化する（バッチごとの試行回数。2-7 で使う）。**行の削除は `grep -vxF` の完全一致で行うので、queue.txt の行に試行回数などを混ぜてはならない。**

### 1-5. ユーザーへの提示

1. キュー件数（バッチ数と Issue 総数）とラベル別内訳を表示する
2. P-0 で確定した `mode` と `base_branch`（single-pr なら統合ブランチ名も）を表示する。ここで `git branch --show-current` から取り直さない
3. 「中止したい時は `/issue-sweep --abort`」を1行案内する

### 1-6. state.json の初期化

```bash
queue_total=$(wc -l < "$SWEEP_DIR/queue.txt" | tr -d ' ')
max_rounds=${max_rounds:-1}   # --max-rounds 未指定時のデフォルト
jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg mode "$mode" --arg base "$base_branch" --arg int "${int_branch:-}" \
      --argjson qt "$queue_total" --argjson mr "$max_rounds" '{
  skill: "issue-sweep",
  started_at: $now, updated_at: $now,
  phase: "iterating",
  mode: $mode, base_branch: $base, int_branch: (if $int == "" then null else $int end),
  queue_total: $qt, queue_remaining: $qt,
  processed_count: 0, merged_count: 0, failed_count: 0,
  round: 0, max_rounds: $mr,
  termination_reason: null
}' > "$SWEEP_DIR/state.json"
```

**P-0 / S-0 で確定した `mode` / `base_branch` / `int_branch` をここで必ず引き継ぐ**（この初期化は state.json を上書きするので、書き落とすと P-0 の決定が消える）。

## フェーズ2: in-flight パイプライン（キューが空になるまで）

**「実装 N 件 → 全部の CI 待ち → また N 件」というバリアを作らない。** CI が 10 分かかるプロジェクトでは、そのバリアがそのまま「実装 agent が 0 本の 10 分」になる。代わりに **スロットが空いた瞬間に次のバッチを起動する**。

枠は 2 つに分ける（片方が他方を食い合わないように）:

- `--parallel N`（デフォルト 5、上限 5）= **同時に走る実装 agent の数**
- `--max-inflight M`（デフォルト 10、上限 15）= **同時に抱える未マージ PR の数**（実装中 + CI 待ち + マージ待ち）

CI 待ちの PR が溜まっても実装スロットは空くので、実装が止まらない。

**重要 — context 設計:** **1 バッチ分の実装（Develop→Commit→Push→PR 作成→研磨）は必ず `Agent` ツールに丸投げする。** メインスレッドは「キュー操作 / PR 一覧の取得 / agent 起動 / 判定 / マージ / 失敗処理」だけを行い、メイン context には PR 番号と状態だけを積む。

### in-flight テーブル

メインスレッドがラウンドをまたいで保持する（メッセージ内のテキストとして持ち回る。ファイルには落とさない）:

| 列 | 内容 |
|---|---|
| `batch_line` | queue.txt の該当行そのまま（例 `12,13,14`）。キュー削除の完全一致キー |
| `issues` | バッチの Issue 番号 |
| `branch` | `sweep/issues-<a>-<b>-…` |
| `pr` | PR 番号（未作成なら null） |
| `stage` | `implementing` / `ci` / `fixing` |
| `ci_respawns` | CI fix agent の再起動回数 |
| `worktree` | agent が返した worktree の絶対パス |
| `start_ts` | バッチ開始 unix time（metrics 用） |

### メインループ

in-flight が 0 かつキューが空になるまで、以下を上から順に 1 回ずつ実行して繰り返す。

#### 2-0. ラウンド冒頭（heartbeat / base 最新化 / PR 一覧の一括取得）

```bash
echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"
git fetch origin "$base_branch" 2>/dev/null || true
git pull --ff-only origin "$base_branch" 2>/dev/null || true

# このラウンドで使う PR 情報を **1 コールだけ** で取る。
# 冪等性チェック（2-1）と状態判定（2-3）の両方がこの結果を使う。
gh pr list --state all --limit 100 \
  --json number,headRefName,state,mergedAt,statusCheckRollup \
  | jq -c '[.[] | {
      pr: .number,
      branch: .headRefName,
      state: .state,
      merged: (.mergedAt != null),
      failed_checks: [.statusCheckRollup[]? | select(.conclusion == "FAILURE") | .name],
      waiting: ([.statusCheckRollup[]? | select(.conclusion == null and .status != "COMPLETED")] | length)
    }]'
```

fast-forward できない場合は警告だけ出して続行する。Stop Hook がキューに残行がある限り停止をブロックするので途中で止まらず流し続ける。

**PR ごと / バッチごとに `gh` を叩かない。** 以前は冪等性チェックをバッチ単位で、状態観測を PR 単位で叩いていて、ラウンドあたりのコール数が in-flight 本数に比例していた。ブランチ名は sweep が決めているので、1 回の一覧取得で全部引ける。

#### 2-1. スロット補充（launch）

`実装中 < N` かつ `in_flight < M` かつキューに**起動可能な**バッチが残っていれば、空きスロット分だけ起動する。

```bash
head -n20 "$SWEEP_DIR/queue.txt"   # 候補を眺める。1 行 = 1 バッチ
```

起動可能の条件:

- そのバッチが依存する Issue がキューにも in-flight にも残っていない
- `serial_only` バッチは **in-flight が 0 のときだけ**起動する（単独で走らせる）。逆に `serial_only` バッチが in-flight にいる間は他を起動しない

**冪等性チェック**（2-0 で取得した PR 一覧から `branch == "sweep/issues-<a>-<b>"` を探す。追加の `gh` 呼び出しはしない）:

- `merged == true` → agent を起動せず 2-4（Issue close）→ 2-5（キュー削除）へ
- `state == "OPEN"` → 既存 PR あり。agent 起動をスキップし、その PR 番号で `stage=ci` として in-flight に載せる
- 見つからない → 2-2 で起動

#### 2-2. 実装 agent の起動

`Agent` ツールを以下の指定で呼ぶ:

- `subagent_type`: `claude`
- `description`: `"Batch #<a>[,#<b>…] implementation"`
- `prompt`: 下記の**統一プロンプト**（バッチ件数 1 件でも同じものを使う）

**worktree は必ず sweep 側が 1 つ作る。** 以前は「1 件なら wt 版スキルに worktree ごと任せ、2 件以上なら sweep が作る」と分岐していたため起動プロンプトが 2 本に分裂し、「誰が worktree を作ったか分からない」ので before/after のスナップショット差分を取る必要が生じていた。常に sweep が作れば両方消える。

```
Issue #<a>[, #<b>, #<c>] を **1 つの worktree にまとめて** 処理してください。メインスレッドには JSON だけを返します。

手順:
1. worktree を 1 つ作る（以降のすべての作業をこのディレクトリ内で行う）:
   git worktree add <repo>-sweep-<a> -b sweep/issues-<a>[-<b>-<c>] <base_branch>

   作成に成功したら、作業を始める前に**必ず**確認する:
   cd <repo>-sweep-<a>
   cur=$(git rev-parse --abbrev-ref HEAD)
   [[ "$cur" != "<base_branch>" && "$cur" != "main" && "$cur" != "develop" ]] || exit 2

   worktree の作成に失敗した場合、**メインリポジトリで代わりに作業してはならない**。
   {"issues": [...], "failure": "worktree 作成に失敗: <理由>"} を返して即座に終了する。
   最初の `git commit` の前にも同じ確認をもう一度行う。
2. 各 Issue を **依存順に** 1 件ずつ処理する。Issue ごとに `gh issue view <n> --json labels` でラベルを見てスキルを選ぶ。
   **`--auto --no-pr` を必ず付ける**:
   - bug → `/bug-fix #<n> --auto --no-pr`
   - design → `/design-fix #<n> --auto --no-pr`
   - それ以外 → `/impl #<n> --auto --no-pr`
   `--auto` = 自律実行モード（確認を取って止まらない / Review は後段の refine-git に委ねる /
   スコープ明記済み Issue では Plan を軽量化する）。`--no-pr` = PR は呼び出し元が 1 本作るので作らない。
   **wt 版（/impl-wt, /bug-fix-wt）は使わない**（worktree は 1 で作成済み。wt 版を呼ぶと二重に作られる）。
   各サブスキルのその他の禁止行動（テスト省略・サイレントスキップ・スコープ外発見の未 issue 化）は厳守。
3. 全 Issue の実装が終わったら push し、`gh pr create --base <base_branch>` で **PR を 1 本だけ** 作る:
   - タイトルに全 Issue 番号を含める
   - 本文に対象 Issue を全件列挙し、各 Issue でやったことを 1 行ずつ書く
   - `gh pr edit <PR番号> --add-issue <各 Issue URL>` で全件リンクする（Closes は使わない）
4. `/refine-git --no-merge --skip-minor --max-iter 2` を Skill ツールで起動して研磨する。
   - **`--skip-minor` 必須**: sweep のマージゲートは minor を見ない。minor は直すたびに差分が広がって
     新しい minor が生えるので、minor のための反復は丸ごと無駄になる
   - **`--max-iter 2` 必須**: 1 周目で検出・修正、2 周目で確認。それで critical/major が消えないなら
     自動では直せない指摘と判定して人に返す
   - **必ず `refine` ではなく `refine-git` を使う**（`refine` はリポジトリ全体が対象。Issue と
     無関係な既存問題でマージゲートが永久に落ちる）
5. **マージゲート判定**（必須）: refine-git が返した JSON の
   `critical_remaining == 0 ∧ major_remaining == 0` を満たすなら、**マージコマンドは叩かず**
   PR 作成までで返す（マージはメインの責務）。満たさなければ failure として返す。
   `status` が `clean` でなくても（`iter_limit` / `no_progress`）この 2 つが 0 なら合格。
6. 成功時の JSON 1行:
   {"issues": [<a>,<b>,<c>], "pr_number": <N>, "pr_url": "<URL>", "branch": "sweep/issues-<a>", "worktree": "<worktree の絶対パス>", "skills": ["<Issue ごとに使ったスキル>"], "refine_status": "<clean|iter_limit|no_progress>", "refine_iters": <K>, "critical_remaining": 0, "major_remaining": 0, "minor_remaining": <N>}
7. 失敗時の JSON（**どの Issue で転んだかを必ず含める**。切り分けに使う）:
   {"failure": "<1行で原因>", "phase": "<どのフェーズ>", "failed_issue": <n>, "completed_issues": [<実装まで終わった Issue>], "worktree": "<作成済みなら絶対パス>", "pr_number": <あれば>, "pr_url": "<あれば>"}

返答ルール:
- 上記 JSON 以外を最終メッセージに含めない（メインスレッドが parse する）。
- 「ユーザーに確認してから次へ進みます」等で停止しない。失敗または完了まで進める。
- マージはメインスレッドが行う（`gh pr merge` は叩かない）。
- **critical/major が残った状態で 6 の success JSON を返してはならない**（5 のゲート判定を必ず通す）。
```

返答 JSON の `worktree` を in-flight テーブルに記録する（2-6 の掃除で使う）。

#### 2-3. 判定と実行（メインスレッド）

2-0 で取得した PR 一覧から in-flight の各 PR を引き、上から順に最初に当たったものを実行する。**判定と agent 再起動はここ（LLM 側）で行う。bash の `while` ループの中で `Agent` ツールは呼べない。**

| 条件 | 実行すること |
|---|---|
| `merged == true` | 2-4（Issue close）→ 2-5（キュー削除）→ 2-6（worktree 掃除）→ in-flight から外す |
| `state == "CLOSED" ∧ merged == false` | 手動 close。`ci_respawns == 0` なら 2-2 で再起動（2-1 の冪等性チェックが既存 PR を拾う）。1 回以上なら諦めて `sweep_notify "Manual intervention needed"`、in-flight から外し metrics に `manual_close` を記録してキューから該当行を消す |
| `failed_checks` が空でない ∧ `waiting == 0` | CI 確定失敗。`ci_respawns >= 2` なら諦め（下記）。それ未満なら `ci_respawns += 1`、`gh pr comment` で attempt を記録し、**下記の CI fix プロンプトで agent を起動**して `stage=fixing` にする |
| `waiting == 0 ∧ failed_checks 空 ∧ state == "OPEN"` | `gh pr merge <PR> --merge --delete-branch` を実行。成功なら次ラウンドで `merged` を検知。失敗なら `sweep_notify "merge failed"` して in-flight から外しユーザー報告に回す |
| それ以外 | CI 実行中。そのまま in-flight に残す |

CI を諦める場合:

```bash
gh pr comment "$pr" --body "sweep: CI が 3 回連続で失敗（checks: $failed_checks）。自動修正を諦めユーザー判断を仰ぎます。"
sweep_notify "Manual intervention needed" "PR #${pr}: CI 3回連続失敗 ($failed_checks)" ":rotating_light:"
```

諦めた PR は **その PR だけ** in-flight から外し、metrics に `ci_gave_up` を記録して**キューからも該当行を削除する**（残すと Stop Hook が永久に停止をブロックする）。他の in-flight の処理は続行する。

**CI fix 起動プロンプト**（バッチでも PR は 1 本なのでそのまま使える）:

```
PR #<PR番号>（branch: <branch>）の CI で以下の check が失敗しました:
- <check名1>: <概要>
- <check名2>: <概要>

タスク:
1. `git fetch && git checkout <branch>` で対象 branch に切り替える（既存 worktree があれば再利用）。
2. 失敗 check のログを `gh run view --log-failed --job <job-id>` 等で取得し、原因を特定する。
3. 修正コミットを push する。テストが必要なら追加する。
4. push まででよい（メインが CI 再走の緑を見て直接マージする）。
5. 完了したら以下を返す:
   {"pr_number": <N>, "fixed": true, "commit": "<sha>"}
   修正不能なら:
   {"pr_number": <N>, "failure": "<1行で原因>"}

返答ルール: 上記 JSON 以外を最終メッセージに含めない。
```

**失敗 check 名を必ず渡す。** 「とりあえず再実行して」は原因不明のまま盲目的に手を入れる事故になる。

#### 2-4. Issue を close（sweep 限定の振る舞い）

マージ完了後、**バッチ内の全 Issue を** 明示的に close する（1 PR が複数 Issue を閉じる）:

```bash
for n in $batch_issues; do
  gh issue close "$n" --comment "Closed by PR #<PR番号> (merged via /issue-sweep, CI respawns=${ci_respawns})" || true
done
sweep_notify "Merged" "#$(echo $batch_issues | tr ' ' ',') (PR #${PR}, $(( $(date +%s) - start_ts ))s)" ":white_check_mark:"
```

- 親 sub-skill 群は意図的に `Closes #N` を使わない設計だが、sweep ではマージ → close を直結したいので sweep 側で補う
- `split-from:#<parent>` ラベルが付いた子 Issue の場合、すべての兄弟が close されたかチェックし、全 close なら親も `gh issue close <parent> --comment "All split children merged"` で閉じる
- close に失敗（権限・既に closed 等）してもキュー処理は続行する

#### 2-5. キュー削除 + state.json 更新

**Issue close 完了後、そのバッチの分だけ実行する**（in-flight は完了時刻が揃わないので先頭行決め打ちで消さない）:

```bash
grep -vxF "$batch_line" "$SWEEP_DIR/queue.txt" > "$SWEEP_DIR/queue.tmp" \
  && mv "$SWEEP_DIR/queue.tmp" "$SWEEP_DIR/queue.txt"

final_status=$(tail -n1 "$SWEEP_DIR/metrics.jsonl" | jq -r '.status // "merged"')
jq --arg status "$final_status" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.queue_remaining = (.queue_remaining - 1)
    | .processed_count = (.processed_count + 1)
    | (if $status == "merged" then .merged_count = (.merged_count + 1) else .failed_count = (.failed_count + 1) end)
    | .updated_at = $now' \
   "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" \
   && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
```

#### 2-6. worktree 掃除

agent が返した JSON の `worktree` パスをそのまま消す。sweep が作らせた 1 つだけなので探索は不要:

```bash
git worktree remove --force "$wt_path" 2>/dev/null || true
```

- agent が `failure` を返した場合も**必ず**消す（同じバッチの再起動時に worktree 名が衝突する）
- 成功してマージ完了した場合、remote branch は `--delete-branch` で処理済みなので local worktree だけ消す

#### 2-7. バッチ失敗時（試行回数の永続化）

agent が `failure` を返したら、**セッションをまたいで数えられる場所**に試行回数を記録する。メモリ上のカウンタだとセッションを張り直したときに同じバッチを無限に再試行する:

```bash
attempts=$(jq -r --arg b "$batch_line" '.[$b] // 0' "$SWEEP_DIR/attempts.json")
attempts=$((attempts + 1))
jq --arg b "$batch_line" --argjson n "$attempts" '.[$b] = $n' \
   "$SWEEP_DIR/attempts.json" > "$SWEEP_DIR/attempts.tmp" \
   && mv "$SWEEP_DIR/attempts.tmp" "$SWEEP_DIR/attempts.json"
```

- `attempts < 2` → in-flight から外してキューに残す（次のラウンドの 2-1 で再度起動される）
- `attempts >= 2` → **そのバッチを諦める**:
  - `gh issue comment <n> --body "sweep: 実装失敗（$failure）。2 回試行して通らなかったため手動対応が必要です。"`
  - `sweep_notify "Agent failed" "Issue #${n}: $failure" ":x:"`
  - metrics に `status: agent_failed` を記録
  - **キューから該当行を削除する**（残すと Stop Hook が永久に停止をブロックし、sweep が終われない）
  - **他のバッチの処理は続行する。1 バッチの失敗で sweep 全体を止めない**

#### 2-8. 待機

このラウンドで何も進捗がなく（マージ 0 件・新規起動 0 件）、in-flight が残っている場合のみ `sleep 60` してから 2-0 に戻る。進捗があった場合は待たずに次のラウンドへ進む（スロットが空いたなら即補充したい）。

**待機は必ず `sleep 60` を実行して行う。「待機。」と言ってターンを終えてはならない。** Stop Hook は停止を押し戻すので、ターンを終える待ち方をすると 2〜3 秒間隔で「待機。」→ ブロック → 「待機。」を繰り返し、1 往復ごとにモデルのターンを 1 回消費する（実測で 1 セッション 1 万往復、トランスクリプトの 10% がフック文言で埋まった）。

待機中のメインは `sleep` + `gh` / `jq` のみで「思考」しないので context は増えず、Stop Hook がキューを見るので止まらない。

## 禁止行動

**ブランチ**

- **フェーズ P-0 を飛ばす / モードとベースブランチを聞かずに始める**（`references/branch-preflight.md`）
- **現在の HEAD や `develop` を推測でベースブランチに採用する**
- **worktree を作らずメインリポジトリで実装する**（ベースブランチ直コミットの主因。worktree 作成に失敗したらそのバッチを諦めて failure を返す）
- **事前ガードに引っかかった状態を `git reset` / `git checkout -f` で自動的に直して続行する**（人に返す）

**キュー / マージ**

- **PR マージ完了前にキューから該当行を削除する**（最重要 — マージ忘れの根本原因）
- **メインが CI 緑後にマージするのを忘れる / マージ完了を確認せず in-flight から外す**（agent は PR 作成までで返るため、メインが観測して直接マージしないと PR が埋もれる）
- **agent 内で `gh pr merge` を叩く**（マージはメインの責務）
- **バッチの一部 Issue だけ close してキューから消す**（2-4 で全件 close する）
- **諦めた PR / 諦めたバッチをキューに残したまま sweep を終わらせようとする**（Stop Hook が永久に停止をブロックする。諦めたら必ずキューから消して metrics に記録する）
- **`$SWEEP_DIR/queue.txt` の行に試行回数などを書き足す**（削除が `grep -vxF` の完全一致なので消せなくなる。試行回数は `attempts.json`）

**パイプライン**

- **実装 → 全 PR の CI 待ち → また実装、というバリアを作る**（CI 時間がそのまま実装 agent 0 本の空白になる。スロットが空いてキューが残っているなら即補充する）
- **bash の `while` ループの中で agent を再起動しようとする**（bash から `Agent` ツールは呼べない。2-0 で状態を取り、2-3 で LLM が判定する）
- **PR ごと / バッチごとに `gh pr view` や `gh pr list --head` を叩く**（2-0 の一覧取得 1 コールで全部引ける。ラウンドあたりのコール数を in-flight 本数に比例させない）
- **1 本の PR の CI 失敗で他の in-flight の処理を止める**（諦めるのはその PR だけ）
- **CI 失敗を検知せず待機を継続する**（無限待機の原因）
- **失敗 check 名を agent に伝えず「とりあえず再実行」を頼む**（原因不明のまま盲目的に手を入れる事故になる）
- **バッチの試行回数を in-flight テーブル（メモリ）だけで数える**（セッションを張り直すと同じバッチを無限に再試行する。`attempts.json` に永続化する）
- **1 バッチの失敗で sweep 全体を止める**（2-7 の上限に達したバッチだけ諦めて残りを流す）
- **CI 待ちの PR が溜まっているせいで実装スロットを空けない**（`--parallel` と `--max-inflight` は別枠）
- **ラウンド冒頭の base branch 最新化をスキップする**（古い base で次を実装すると競合・無駄作業の原因）
- **やることが無いときにターンを終えて待つ**（Stop Hook に押し戻されるたびにモデルのターンを 1 回消費する。実測で 1 セッション 1 万往復、トランスクリプトの 10% がフック文言だった。待つときは必ず 1 つの bash コマンドの中で `sleep 60` を挟んでブロックする）

**agent への委譲**

- **メインスレッドで直接サブスキル（`/impl` 等）を Skill ツール起動する**（context 汚染の根本原因。必ず `Agent` 経由）
- **メインスレッド自身がコードを修正する / コミットする / PR を編集する**（CTO は実装に手を出さない）
- **wt 版スキル（`/impl-wt`, `/bug-fix-wt`）を呼ぶ**（worktree は 2-3 で sweep 側が作る。wt 版を呼ぶと二重に作られる）
- **サブスキルに `--auto` を渡さない**（確認を取って止まる / Review が二重に走る / Plan が Issue の記載を再導出する。自律実行では致命的）
- **サブスキルに `--no-pr` を渡さない**（バッチの Issue ごとに PR ができてしまう。PR は agent 側の手順3 で 1 本だけ作る）
- **Issue 本文を複数のステップで読み直す**（フェーズ1-2 の解析 1 パスに集約する。メインスレッドは 1-2 が返した JSON だけで 1-3 のバッチ編成を行う）
- **agent 内で `/refine-git` をスキップする**（レビューを通さずマージゲートに進むと品質ばらつきが出る）。**以下 3 点は通常モード（multi-pr）限定** — single-pr モードでは agent 内で研磨せず、S-2-0 で統合ブランチにまとめて 1 回回す（`references/single-branch-mode.md`）
- **`refine-git` の代わりに `refine` を起動する**（全体スキャンになり、Issue と無関係な既存指摘でマージゲートが永久に落ちる）
- **`refine-git` に `--skip-minor` / `--max-iter 2` を渡さない**（sweep のマージゲートは minor を見ないので minor のための反復は丸ごと無駄。反復上限を絞らないと 1 PR の実時間が読めない）
- agent の返答 JSON 以外をメイン context に取り込む（agent 内部の Plan/Develop ログをメインに残すのは禁止）

**終了処理**

- 「ここで停止します」「次に進む前に確認してください」とユーザー判断を待って止まる（Stop Hook が押し戻す）
- **`$SWEEP_DIR/state.json` を `phase=terminal` にする前にキュー残数 = 0 と spinoff 検出済みを確認しない**
- **失敗で打ち切るときに terminal 化とレポート生成をスキップする**（`phase=iterating` のまま放置すると記録が何も残らない）
- **spinoff 検出（3-0）自体をスキップして sweep を終わらせる**（追跡しない分は必ずレポートに列挙する）
- **`max_rounds` のデフォルトを自己判断で 1 より大きくする**（増やすのはユーザーが明示指定した時だけ）
- **重要度フィルタで落ちた spinoff（`spinoff_deferred`）をレポートに書かずに捨てる**
- **「spinoff も追跡しますか？」「次の round に進みますか？」のような確認をユーザーに取る**
- **ユーザーに並列度（--parallel / --max-inflight）を確認する**（デフォルトで常に起動）
- ベースブランチを途中で変える
- フェーズ0 の lock 取得をスキップする

**single-pr モード**

- `--single-pr` 指定時に `references/single-branch-mode.md` を読まずに進める（差分表だけで手順を推測しない）
- **バッチごとに PR を作る / 統合 merge を並列に走らせる / 統合のたびに CI を待つ**（詳細は `references/single-branch-mode.md` の禁止行動）

## 通知（`.sweep/notify.url`）

各所で `sweep_notify "<title>" "<msg>" "<emoji>"` を呼ぶ。**`.sweep/notify.url` が存在しなければ通知は完全に no-op** なので、無ければ呼び出し箇所ごと無視してよい。存在する場合のみ `references/notifications.md` を読み、関数定義と通知タイミング表に従う。

## テレメトリ（`.sweep/metrics.jsonl`）

各**バッチ**の処理完了時 / 失敗時に **JSON 1行を append** する（バッチ = 1 PR）。後で `jq` で集計可能。

**書き出すタイミング:**
- 正常マージ完了（2-4 の Issue close 直後）
- agent failure（2-7 の失敗時挙動）
- CI 諦め（respawn 上限到達時）

**スキーマ:**

`issues` がバッチの全 Issue。先頭 Issue が要るときは `issues[0]` を使う（以前は後方互換の `issue` フィールドを二重に持っていた）。

```json
{"ts":"<ISO8601>","issues":[42],"skill":"impl","duration_sec":423,"agent_attempts":1,"ci_respawns":0,"pr_number":127,"pr_url":"https://...","status":"merged"}
{"ts":"<ISO8601>","issues":[12,13,14],"skill":"impl","duration_sec":2140,"agent_attempts":1,"ci_respawns":0,"pr_number":129,"pr_url":"https://...","status":"merged"}
{"ts":"<ISO8601>","issues":[51],"skill":"bug-fix","duration_sec":1820,"agent_attempts":3,"ci_respawns":2,"pr_number":131,"pr_url":"https://...","status":"ci_gave_up","failed_checks":"unit-tests,lint"}
{"ts":"<ISO8601>","issues":[53],"skill":null,"duration_sec":12,"agent_attempts":1,"ci_respawns":0,"pr_number":null,"pr_url":null,"status":"agent_failed","failure":"<理由>","failed_issue":53}
```

**status 値:** `merged` / `ci_gave_up` / `agent_failed` / `aborted` / `manual_close`

**実装:** 2-2 の起動時に `start_ts=$(date +%s)` を in-flight テーブルに記録し、2-4 / 2-7 の直前で:

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
  '{ts:$ts,issues:$issues,skill:$skill,duration_sec:$dur,agent_attempts:$att,ci_respawns:$resp,pr_number:$pr,pr_url:$url,status:$status}' \
  >> "$SWEEP_DIR/metrics.jsonl"
```

集計クエリは `references/metrics-queries.md`（フェーズ3-1 で使う）。ファイルは `.gitignore` 対象。

## フェーズ3: 完了報告と spinoff 追跡

### 3-0. spinoff 検出と再 sweep 判定

実装中の発見が `impl` / `bug-fix` のフェーズ3 で `/spinoff-issue --batch` により **キュー構築後** に起票されているため、それらを拾い直す:

```bash
# 今回 sweep が処理した親 Issue 番号一覧（フェーズ1 で展開した子 Issue を含む）
PROCESSED_IDS=$(jq -r --arg since "$sweep_start_iso" \
  'select(.ts >= $since and ((.source // "") | startswith("refine") | not))
   | .issues[]' \
  "$SWEEP_DIR/metrics.jsonl" | sort -u | tr '\n' ',' | sed 's/,$//')

# sweep 開始以降に作成された OPEN Issue を取得
new_issues=$(gh issue list --state open \
  --search "created:>=${sweep_start_iso}" \
  --json number,title,body,labels --limit 200)

# spinoff 由来を判定: /spinoff-issue が付与する `spinoff` ラベルを主シグナルとし、
# 本文 "元: #N"（spinoff-issue のテンプレ）または "Parent: #N"（後方互換）から親番号を取り出し、
# PROCESSED_IDS と一致するものを抽出
#   `high` = 再 sweep（実装フルサイクル）まで自動で回す重要度かどうか
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
  - `spinoff_ids` を新規キューとして `$SWEEP_DIR/queue.txt` に書き出す（`attempts.json` も `{}` に戻す）
  - **フェーズ2 に戻る**（ロック / 通知 URL / メトリクスは引き継ぎ、`sweep_start_iso` のみ次周開始時刻に更新）
- 上限到達（デフォルトでは 2 周目に入ろうとした時点で必ずここに来る）または `--no-follow-spinoffs` 指定時:
  - レポートに「未処理 spinoffs」セクションを追加して `spinoff_all` を列挙
  - 通知 `sweep_notify "spinoffs left unprocessed" "${#spinoff_all} 件、要手動 sweep" ":warning:"`
- `spinoff_deferred` が空でない場合は、再 sweep の有無にかかわらずレポートに **「未追跡 spinoffs（重要度フィルタで対象外）」** セクションを追加して列挙する（黙って握り潰さない）

### 3-1. 完了報告

1. 処理した Issue 番号と PR URL の一覧を表でまとめる（**全 round 通算**）
2. **`$SWEEP_DIR/metrics.jsonl` の今回 sweep 分から所要時間・失敗内訳を集計してユーザーに表示**
3. キューファイルが空（`wc -l < "$SWEEP_DIR/queue.txt"` が 0）であることを確認
4. `git worktree prune` で残存 worktree を全削除
4b. **state.json を terminal 化**:
   ```bash
   # フェーズ3 到達時点で queue_remaining が 0 でなければ manual_intervention 扱い
   remaining=$(jq -r '.queue_remaining // 0' "$SWEEP_DIR/state.json")
   if [[ "$remaining" == "0" ]]; then
     reason="queue_empty"
   else
     reason="manual_intervention"
   fi
   jq --arg reason "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.phase = "terminal" | .termination_reason = $reason | .updated_at = $now' \
      "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
   ```
5. **Markdown レポート生成** — `$SWEEP_DIR/report-sweep-<timestamp>.md` に書き出す:

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
report="$SWEEP_DIR/report-sweep-${ts}.md"
sweep_start_iso=$(date -u -d @${sweep_start_ts} +%Y-%m-%dT%H:%M:%SZ)
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
  echo "- Parallel: $parallel_n (implement) / $max_inflight (in-flight)"
  echo
  echo "## Per-Issue"
  echo
  echo "| Issues | Skill | Duration | Status | PR | Respawns |"
  echo "|---|---|---|---|---|---|"
  jq -r --arg since "$sweep_start_iso" \
    'select(.ts >= $since and ((.source // "") | startswith("refine") | not)) |
     "| \(.issues | map("#\(.)") | join(", ")) | \(.skill // "-") | \(.duration_sec)s | \(.status) | \(.pr_url // "-") | \(.ci_respawns // 0) |"' \
    "$SWEEP_DIR/metrics.jsonl"
  echo
  echo "## Failures & Manual Intervention"
  jq -r --arg since "$sweep_start_iso" \
    'select(.ts >= $since and ((.source // "") | startswith("refine") | not) and .status != "merged") |
     "- **\(.issues | map("#\(.)") | join(", "))** (\(.status))\(if .failed_issue then " — 転んだのは #\(.failed_issue)" else "" end): \(.failure // .failed_checks // "-") — PR \(.pr_url // "n/a")"' \
    "$SWEEP_DIR/metrics.jsonl"
  if [[ -f "$SWEEP_DIR/refine-metrics.jsonl" ]]; then
    echo
    echo "## Recent refine runs（直近 24h）"
    cutoff=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)
    jq -r --arg c "$cutoff" \
      'select(.ts >= $c and (.source | startswith("refine"))) |
       "- [\(.source)] PR #\(.pr_number) iter \(.iter): critical=\(.critical) major=\(.major) minor=\(.minor)"' \
      "$SWEEP_DIR/refine-metrics.jsonl"
  fi
} > "$report"
echo "Report: $report"
```

6. `rm -f "$SWEEP_DIR/lock"` でロック解除
7. **完了通知**: `sweep_notify "Sweep done" "${merged_count} merged, ${failed_count} failed (report: ${report})" ":checkered_flag:"`
8. ユーザーに最終サマリと**レポートパス**を返す

## 失敗時の挙動

`references/abort-and-recovery.md` を参照（失敗が起きたときだけ読めばよい）。
