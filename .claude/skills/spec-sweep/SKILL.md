---
name: spec-sweep
description: 複数の仕様追加を事前計画で一括ヒアリングし、Issue/ブランチごとに spec-gen を順次実行する
user-invocable: true
---

# spec-sweep

複数の仕様追加（機能追加・拡張）を 1 セッションで連続実行する。`spec-gen` の薄いラッパーで、計画段階で全項目を確定 → 各項目ごとに Issue/ブランチを切って `spec-gen` 相当の作業を順次実行する。

## いつ使うか

- 既存プロジェクトに複数の機能/仕様を追加したいとき
- 1 件ずつ `/spec-gen` を起動する手間を省きたいとき
- 機能ごとに独立した Issue/ブランチで管理し、後で `/impl #N` を流したいとき

新規プロジェクトの初期設計には使わない（`/spec-gen` を直接呼ぶ）。

## 前提条件

- Claude Code 環境
- `gh` CLI
- 既存の仕様書ディレクトリ（探索ロジックは `spec-gen` SKILL.md フェーズ1-0 参照）

## 引数

- `/spec-sweep` — 通常モード（項目ごとに Issue + `feat/#N` ブランチ）
- `/spec-sweep --single-pr` — **1 統合ブランチ集約モード**。項目ごとにブランチを切らず統合ブランチ 1 本に全仕様書を積み、最後にベースブランチへ PR を 1 本だけ出す
- `/spec-sweep --multi-pr` — 項目ごとに `feat/#N` ブランチを切る従来モード
- `/spec-sweep --base <branch>` — ベースブランチ（PR のマージ先）
- `/spec-sweep --branch <name>` — 統合ブランチ名。デフォルト `sweep/spec-sweep-<YYYYmmdd-HHMMSS>`
- `/spec-sweep --abort` — 実行中の sweep を中止し lock を削除して state.json を terminal 化する

**`--single-pr` / `--multi-pr` と `--base` は、指定がなければフェーズ P-0 で `AskUserQuestion` で必ず聞く。推測で決めない。**

## single-pr モード（`--single-pr`）

有効時は **`../sweep-common/single-branch-mode.md` を読んでから**フェーズ1 に入る（`skill_name="spec-sweep"`）。差分は以下だけ:

| 箇所 | single-pr での差し替え |
|---|---|
| 1-1 のヒアリング | 「Issue モード」の選択肢から**ブランチの持ち方を外す**（統合ブランチ 1 本で固定）。Issue を作るかどうかだけ聞く |
| P-0 の直後 | S-0 を実行。P-0 で確定したベースから統合ブランチを切って push する |
| 1-3 の計画提示 | 各項目の「ブランチ: feat/#N」を消し、先頭に `base → 統合ブランチ → 最終 1 PR` を提示する |
| フェーズ2 手順1 / 8 | 「ベースブランチに戻る」を**統合ブランチに居続ける**に読み替える（checkout しない） |
| フェーズ2 手順4 | `feat/#<Issue番号>` ブランチ作成を**行わない** |
| フェーズ2 手順6 | push 先は統合ブランチ（項目ごとに `git push origin "$int_branch"`） |
| フェーズ3 の前 | S-2 を実行して最終 PR を作り、CI 緑を確認する。**PR はマージしない**（レビューとマージはユーザー）。**Issue は close しない**（S-1' / S-3 参照。後で `/impl #N` に渡す設計） |
| フェーズ3 の報告 | ブランチ名一覧の代わりにベース / 統合ブランチ / PR URL を提示する |

## フェーズ0: lock と state.json の準備（必須）

sweep 系共通の進行状態を持つ。`prelude.sh` も `assert_not_base` もここで作る state.json を読む。

**対話フェーズでは lock を書かない。** Stop Hook (`check-sweep-state.sh`) は `phase != "terminal"` かつ lock が新鮮な間だけ停止をブロックする。計画ヒアリング中に lock があると、ユーザーへの質問でターンを終えるたびに押し戻されて進めなくなる。

1. **`$SWEEP_DIR` の確定と多重起動チェック**:

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
mkdir -p "$SWEEP_DIR"
if [[ -f "$SWEEP_DIR/lock" ]] && (( $(date +%s) - $(cut -d: -f2 "$SWEEP_DIR/lock") < 7200 )); then
  echo "他セッションが sweep 実行中。停止するには /spec-sweep --abort" >&2; exit 2
fi
rm -f "$SWEEP_DIR/lock"
```

2. **state.json を初期化**（`phase="planning"`。lock はまだ書かない）:

```bash
jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
  skill: "spec-sweep", started_at: $now, updated_at: $now,
  phase: "planning", mode: null, base_branch: null, int_branch: null, pr_number: null,
  total: 0, remaining: 0, completed_count: 0, failed_count: 0,
  termination_reason: null
}' > "$SWEEP_DIR/state.json"
```

3. `--abort` 指定時は `rm -f "$SWEEP_DIR/lock"` + `phase=terminal, termination_reason="aborted"` にして `git worktree prune` し、終了する（他フェーズに進まない）。

**lock を書くのはフェーズ2 の直前**（1-3 の承認が済み、以降ユーザーに聞かない区間に入るとき）。フェーズ3 の完了報告 / 打ち切り時に必ず `rm -f "$SWEEP_DIR/lock"` と `phase=terminal` をセットする。

## フェーズ P-0: モードとベースブランチの確定（必須）

フェーズ1 の**前**に実行する。**`~/.claude/skills/issue-sweep/references/branch-preflight.md` を読んでその手順どおりに実行する。スキップ不可。**
`--single-pr` / `--multi-pr` と `--base` の両方が引数で確定している場合のみ、ヒアリング（P-0-2）を省略できる。

ここで確定するもの:

- `mode`（`single-pr` = 統合ブランチ 1 本＋最終 1 PR / `multi-pr` = 項目ごとに `feat/#N`）
- `base_branch`（**現在の HEAD を推測で採用しない**）
- `main_worktree` と事前ガード関数 `assert_not_base`

`mode=single-pr` なら続けて S-0 へ、`multi-pr` ならフェーズ1 へ進む。以降「ベースブランチ」と書かれた箇所はすべて P-0 で確定した `$base_branch` を指す。

## フェーズ1: 計画

### 1-0: 既存仕様書の探索

`spec-gen` SKILL.md のフェーズ 1-0 と同じ手順で既存仕様書を探索し、ベースマップを Read で把握する。見つからない場合は新規プロジェクトとして扱われるべきなので、`/spec-gen` を直接使うよう案内して終了。

### 1-1: 運用方針の一括ヒアリング

`AskUserQuestion` で以下を 1 回にまとめて確認（**4 問以内**）:

1. **追加項目の名前を列挙**（自由入力。「通知機能, 権限管理拡張, …」のように 1 行で）
2. **Issue モード**: 推奨は「追加ごとに別 Issue / 別ブランチ」。ローカルのみも選択可
3. **執筆中のレビュー対話**:
   - 「中断なく書く（推奨）」: spec-gen フェーズ 2-3 のレビュー対話はスキップし、完了後に `/spec-review` で一括レビュー
   - 「項目ごとにレビュー」: 各項目で spec-gen の通常レビューサイクルを回す
4. **項目間の依存関係**: 1 で挙がった項目の実行順。「入力順でよい（推奨）」/「指定する（自由入力: `2 は 1 の後` 等）」

**依存関係は項目間の話なので、全項目の名前が揃ったここで 1 回だけ聞く。** 項目ごとのヒアリング（1-2）に混ぜると、まだ挙がっていない項目を参照させることになる。

### 1-2: 各項目の詳細を一括収集

項目ごとに 1 回の `AskUserQuestion` で以下 **4 問**をまとめて集める（項目数だけ繰り返すが、1 項目 1 質問に厳守。`AskUserQuestion` の上限が 4 問なのでこれ以上増やさない）:

1. **項目名**（1-1 で挙がった名前の確認。実装する機能名。例: 「ユーザー通知機能」）
2. **概要**（1〜2文）
3. **影響する仕様書**（既存マップから複数選択 + 新規追加候補、複数選択可）
4. **CTO 確認事項**（自由入力、任意。仕様策定前に潰しておきたい重要な論点があれば箇条書きで。spec-gen が読める形で spec に書き込まれる）

依存関係は 1-1 で確定済みなのでここでは聞かない。

これ以降は原則追加質問しない。判断に迷うことは仕様書やコードを読んで自分で決める。

### 1-3: 計画確定と一括承認

収集情報を整理して提示し、**同じ `AskUserQuestion` で承認まで完結させる**:

```
追加項目（実行順）:
1. ユーザー通知機能
   影響: requirements/functional.md, api/endpoints.md
   Issue: 新規作成 / ブランチ: feat/#N
2. 権限管理拡張
   影響: requirements/functional.md, components/overview.md
   依存: 1 の完了後 / ブランチ: feat/#N+1
```

「一括承認 / 修正指示 / 中止」を選ばせ、承認後は `TaskCreate` で各項目を 1 タスクとしてキュー化し、フェーズ 2 は割り込みなしで最後まで走らせる（「項目ごとにレビュー」モードのみ、spec-gen 内部のレビュー対話が発生する）。

## フェーズ2: 順次実行

**開始時に lock を取得し `phase=iterating` にする**（ここから先はユーザーに聞かない区間）:

```bash
source "$SWEEP_DIR/prelude.sh"
echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"
jq --argjson n "<項目数>" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.phase = "iterating" | .total = $n | .remaining = $n | .updated_at = $now' \
   "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
```

依存関係順に、各項目について以下を実行（項目の冒頭で `echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"` の heartbeat を打つ）:

1. **ベースブランチに戻る**（P-0 で確定した `$base_branch`）
2. **`TaskUpdate` で当該タスクを in_progress に**
3. **プレースホルダー Issue 作成**（Issue モードの場合）
   - タイトル: `feat: <項目名>`
   - 本文: `仕様策定中（spec-sweep 実行中）。完了後に実装内容を追記する。`
4. **`feat/#<Issue番号>` ブランチ作成** → 直後に `assert_not_base "$main_worktree"` で確認する（`branch-preflight.md`）。ブランチ作成に失敗したまま次に進むと仕様書がベースブランチに直接コミットされる
5. **`spec-gen` の既存仕様書追記モードを実行**
   - 計画段階で集めた `項目名 / 概要 / 影響仕様書` をコンテキストに含め、フェーズ 2-1 の追加ヒアリングは最小限にする
   - **「中断なく書く」モードの場合**: フェーズ 2-3 のレビュー対話はスキップ（フィードバックなしで次に進む扱い）
   - **「項目ごとにレビュー」モードの場合**: spec-gen の通常サイクル
6. **`spec-gen` のフェーズ 3 を完了**（push + Issue 本文を実装 Issue に書き換え）
7. **`TaskUpdate` で当該タスクを completed に**
8. **ベースブランチに戻る → 次項目へ**

### エラー時

- 当該項目で停止し、`TaskUpdate` で当該タスクの状態を明示
- 完了済み項目はそのまま残す
- ユーザーに `項目N で失敗 / 完了済み: 1..N-1 / 未着手: N+1..` を報告し、再開可否を確認

## フェーズ3: 完了報告

- **ユーザーに聞く前に必ず `phase=terminal` + `termination_reason="manual_intervention"` にして lock を消す**（Stop Hook が押し戻して質問できなくなるため）
サマリーをユーザーに提示:

- 全項目の Issue URL とブランチ名一覧
- スキップ/失敗があれば明記
**先に terminal 化する**（これを飛ばすと Stop Hook が停止をブロックし続ける）:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.phase = "terminal" | .termination_reason = "completed" | .updated_at = $now' \
   "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
rm -f "$SWEEP_DIR/lock"
```

- 「中断なく書く」を選んだ場合は `/spec-review <仕様書パス>` の実行を推奨

## ルール

- **フェーズ 1 で全情報を一括収集**。フェーズ 2 以降は原則追加ヒアリングしない（「項目ごとにレビュー」モード時の spec-gen 内部対話が唯一の例外）
- 質問は必ず `AskUserQuestion` を使い、1 回 4 問以内
- 既存仕様書ディレクトリを最優先（新規ディレクトリを勝手に作らない）
- 各 Issue は open のまま残す（後で `/impl #N` がそのまま使える）。single-pr モードでも最終 PR で close しない
- **フェーズ P-0 を飛ばさない**。モードとベースブランチを聞かずに始めない / 現在の HEAD を推測でベースに採用しない（`../sweep-common/branch-preflight.md`）
- **作業ブランチを作らずベースブランチ上で仕様書をコミットしない**。ブランチ作成に失敗したらその項目を諦めて人に返す（`git reset` / `git checkout -f` で自動的に直して続行しない）
- `--single-pr` 指定時は `~/.claude/skills/issue-sweep/references/single-branch-mode.md` を読んでから進める（差分表だけで手順を推測しない）
- `spec-gen` 本体のロジックは複製せず参照する（`~/.claude/skills/spec-gen/SKILL.md`）
- 計画フェーズで集めた `項目名 / 概要 / 影響仕様書 / CTO 確認事項` を渡し、spec-gen 内の追加ヒアリングは最小化
- コミットメッセージは `<type>: <説明>` 形式（CLAUDE.md 準拠）
- `git commit` / `git push` で `--no-verify` を使わない
- **対話フェーズ（0〜1）では lock を書かない / 実行フェーズ（2）に入る直前に書く**。ユーザーに質問して止まる区間で lock があると Stop Hook に押し戻される
- **終了時・打ち切り時は必ず `phase=terminal` + `rm -f lock`**。放置すると次回起動が「他 sweep 実行中」で弾かれる
