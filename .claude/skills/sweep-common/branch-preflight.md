# ブランチ事前ガード（sweep 系共通）

`issue-sweep` / `refine-sweep` / `spec-sweep` / `report-sweep` が共有する **フェーズ P-0**（モードとベースブランチの確定）と
**事前ガード**（ベースブランチ直コミットの防止）の仕様。呼び出し元 SKILL.md は事前に `skill_name` を設定しておく。

防ぐ事故は 2 つ:

- ベースブランチ（`develop` / `main`）にそのままコミットしてしまう
- ベースブランチをユーザーに確認せず、現在の HEAD を推測で採用してしまう

## 前提: シェル変数は次の Bash 呼び出しまで残らない

Bash ツールは**呼び出しごとに新しいシェル**で、env var も関数も持ち越されない（cwd だけが持続する）。
`$base_branch` / `$int_branch` / `assert_not_base` を「一度定義したから以後使える」と仮定すると、
2 回目以降の呼び出しでは**空文字と undefined function** になり、ガードが無言で素通りする。

**state.json が唯一の持ち回り媒体。** 変数はそこから毎回読み直す。

### P-0-0. prelude を生成する（P-0 の最初に 1 回だけ）

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
mkdir -p "$SWEEP_DIR"
cat > "$SWEEP_DIR/prelude.sh" <<'PRELUDE'
# sweep 共通プレリュード。各 bash 呼び出しの先頭で source する。
set -uo pipefail
_sw_get() { [[ -f "$SWEEP_DIR/state.json" ]] && jq -r --arg k "$1" '.[$k] // empty' "$SWEEP_DIR/state.json" 2>/dev/null || true; }
base_branch=$(_sw_get base_branch)
int_branch=$(_sw_get int_branch)
main_worktree=$(git rev-parse --show-toplevel)
PROTECTED_BRANCHES="main master develop staging production"

# $1: 検査対象の作業ツリーのパス
assert_not_base() {
  local dir="$1" cur
  cur=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
  if [[ -z "$base_branch" ]]; then
    echo "ERROR: base_branch が未確定（P-0 未実行 / state.json 欠損）" >&2
    return 1
  fi
  if [[ "$cur" == "$base_branch" || " $PROTECTED_BRANCHES " == *" $cur "* ]]; then
    echo "ERROR: $dir が保護ブランチ $cur に居ます。作業ブランチを作ってから続行してください" >&2
    return 1
  fi
  # single-pr モードのメイン作業ツリーは統合ブランチ以外に居てはならない
  if [[ -n "$int_branch" && "$dir" == "$main_worktree" && "$cur" != "$int_branch" ]]; then
    echo "ERROR: メイン作業ツリーが $cur に居ます（期待: $int_branch）" >&2
    return 1
  fi
}
PRELUDE
```

### 各 bash 呼び出しの先頭（P-0-0 以降すべて）

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
source "$SWEEP_DIR/prelude.sh"
```

**このファイルおよび各 SKILL.md の bash スニペットは、すべてこの 2 行が先頭にある前提で書かれている。**
`$base_branch` / `$int_branch` / `$main_worktree` / `assert_not_base` を参照するスニペットで 2 行を省略してはならない。

## フェーズ P-0: モードとベースブランチの確定（必須・スキップ不可）

lock 取得（フェーズ0）の**直後**、キュー構築 / review 実行（フェーズ1）の**前**に実行する。
**最初に P-0-0（prelude 生成）を実行してから** P-0-1 に入る。
`--single-pr` / `--multi-pr` と `--base` の**両方が引数で確定している場合のみ** P-0-2 を省略できる。

### P-0-1. 候補を集める

```bash
source "$SWEEP_DIR/prelude.sh"
git fetch origin --prune
git branch -r --format='%(refname:short)' | sed 's|^origin/||' | grep -v '^HEAD$'
cur_branch=$(git rev-parse --abbrev-ref HEAD)
```

### P-0-2. `AskUserQuestion` で 2 問まとめて聞く（1 回だけ）

| 質問 | header | 選択肢 |
|---|---|---|
| この sweep の PR の出し方 | `PR モード` | **1 PR に集約（推奨）**: 統合ブランチ `sweep/<skill_name>-<ts>` に全作業を積み、最後にベースへ PR を 1 本だけ出す。複数 Issue の実装をまとめてレビューできる。**この PR は自動マージされず open のまま返る**（レビューとマージはユーザー） ／ **作業単位ごとに PR**: バッチ・Issue ごとに PR を作る。1 本あたりは小さいが本数が増え、横断レビューはできない |
| ベースブランチ（PR のマージ先） | `ベース` | P-0-1 の remote 一覧から `develop` / `main` / `$cur_branch` を優先して 3 つ提示。それ以外は「Other」の自由入力 |

**現在のブランチや `develop` を推測で採用してはならない。** 起点はユーザーが決める。

```bash
git rev-parse --verify "origin/$base_branch" >/dev/null 2>&1 \
  || { echo "ERROR: origin/$base_branch が存在しません" >&2; exit 2; }
```

### P-0-3. 決定を state.json に持たせる

```json
{ "mode": "single-pr" | "multi-pr", "base_branch": "<base>" }
```

state.json が既にあれば `jq` で更新する。**この時点でまだ state.json を作っていないスキル（issue-sweep はキュー構築の最後に初期化する）では、その初期化時にこの 2 つを必ず含める。**
後続の初期化が state.json を丸ごと上書きして P-0 の決定を消さないよう気をつける。

`mode` は以降のフェーズ分岐の唯一の根拠。引数の有無を後から読み直さない。

### P-0-4. モードごとの続き

- `single-pr` → `single-branch-mode.md` の **S-0-2** へ進む（S-0-1 のベース確定はここで済んでいる）
- `multi-pr` → 通常モードのフェーズ1 へ。メイン作業ツリーは `$base_branch` に置いたままにする

### P-0-5. メイン作業ツリーの清潔確認

```bash
source "$SWEEP_DIR/prelude.sh"
[[ -z "$(git -C "$main_worktree" status --porcelain)" ]] \
  || { echo "ERROR: メイン作業ツリーに未コミットの変更があります。退避してから再実行してください" >&2; exit 2; }
```

## 事前ガード

**事後検知・自動退避はしない。** 危険な状態を作る**前**に必ず止める。

`assert_not_base` の定義は上記 prelude にある。呼ぶ側は prelude を source するだけでよく、
**関数定義をスニペットごとにコピーしない**（定義が 2 つに割れると片方だけ直す事故になる）。

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
source "$SWEEP_DIR/prelude.sh"
if ! assert_not_base "$main_worktree"; then
  # この作業単位を諦める（metrics に status:"branch_guard"、キュー行を削除して次へ）
  exit 2
fi
```

`return 1` したら**その作業単位を諦めて** metrics に `status:"branch_guard"` を残し、キュー行を削除して次へ進む。
`git reset` / `git checkout -f` などで自動的に直そうとしない。

### 呼び出し位置

| 呼ぶ側 | タイミング | 呼び出し |
|---|---|---|
| メインスレッド（共通） | P-0 の最初 | P-0-0 で prelude を生成する |
| メインスレッド（共通） | P-0 の直後 | P-0-5 の清潔確認 |
| メインスレッド（共通） | `$base_branch` / `assert_not_base` を使う **すべての** bash 呼び出しの先頭 | `source "$SWEEP_DIR/prelude.sh"` |
| メインスレッド（single-pr） | S-0-2 の統合ブランチ作成の直後 | `assert_not_base "$main_worktree"` |
| メインスレッド（single-pr） | S-1 の統合 `git merge` / `git push` の直前 | `assert_not_base "$main_worktree"` |
| メインスレッド（spec-sweep / report-sweep の multi-pr） | `feat/#N` ブランチ作成の直後、spec-gen 実行の前 | `assert_not_base "$main_worktree"` |
| 実装 agent（issue-sweep / refine-sweep） | worktree 作成の直後、および最初の `git commit` の前 | 下記スニペットを**プロンプトに必ず埋める** |

### 実装 agent プロンプトに埋めるスニペット

```
0. 作業を始める前に必ず実行する:
   cd <worktree_path>
   cur=$(git rev-parse --abbrev-ref HEAD)
   [[ "$cur" != "<base_branch>" && "$cur" != "main" && "$cur" != "develop" ]] || exit 2

   worktree の作成に失敗した場合は、**メインリポジトリで代わりに作業してはならない**。
   {"...": ..., "failure": "worktree 作成に失敗"} を返して即座に終了する。
   最初の commit の前にも同じ確認をもう一度行う。
```

## 禁止行動

- **P-0 を飛ばしてフェーズ1 に入る**（ベースが未確定のまま worktree の分岐元が決まってしまう）
- **ベースブランチを聞かずに現在の HEAD / `develop` / `main` を採用する**
- **worktree 作成に失敗したときメインリポジトリで代替作業する**（これが直コミットの主因）
- **ガードに引っかかった状態を `git reset` / `git checkout -f` / `git stash` で自動的に「直して」続行する**（事前ガードのみの方針。人に返す）
- **`mode` を state.json に書かずに引数から都度判断する**（フェーズごとに解釈がぶれる）
- **シェル変数・関数が次の Bash 呼び出しまで残ると仮定する**（Bash ツールは毎回新しいシェル。`$base_branch` は空文字に、`assert_not_base` は未定義になってガードが無言で素通りする。毎回 prelude を source する）
- **`assert_not_base` の定義をスニペットにコピーする**（prelude の 1 箇所だけが定義）
