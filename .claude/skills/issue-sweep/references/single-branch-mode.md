# single-pr モード（1 統合ブランチ → 1 PR）

`issue-sweep` / `refine-sweep` / `spec-sweep` / `report-sweep` が共有する集約モードの仕様。
呼び出し元 SKILL.md は事前に `skill_name` を設定しておく。

**通常モードとの違いは 2 点だけ**:

1. 作業単位（バッチ / Issue / 仕様項目）ごとに PR を作らず、**最初に切った統合ブランチ 1 本に全部積み、最後にベースブランチへ PR を 1 本だけ出す**
2. **研磨（`/refine-git`）を作業単位ごとに回さず、全部積み終わってから統合ブランチに対して 1 回だけ回す**（フェーズ S-2-0）

キュー管理・lock・state.json・metrics・spinoff 追跡は通常モードのまま。

## 共通引数

- `--single-pr` — このモードを有効化（**未指定なら P-0 でユーザーに必ず聞く**。`branch-preflight.md` 参照）
- `--base <branch>` — ベースブランチ（PR のマージ先）。**未指定なら P-0 で必ず聞く**
- `--branch <name>` — 統合ブランチ名。デフォルト `sweep/<skill_name>-<YYYYmmdd-HHMMSS>`

## フェーズ S-0: 統合ブランチ作成

`branch-preflight.md` のフェーズ P-0（モードとベースブランチの確定）の直後、キュー構築（フェーズ1）の**前**に実行する。

### S-0-1. ベースブランチ

**P-0 で確定済み**（`$base_branch` と state.json の `base_branch`）。ここで聞き直さない。

### S-0-2. 統合ブランチを切って push する

```bash
int_branch="${branch_opt:-sweep/${skill_name}-$(date +%Y%m%d-%H%M%S)}"
git checkout -B "$int_branch" "origin/$base_branch"
assert_not_base "$main_worktree"   # branch-preflight.md の事前ガード
git push -u origin "$int_branch"
```

- **メイン作業ツリーは以降ずっと `$int_branch` に居る。** ベースブランチには戻らない
- 空の統合ブランチをこの時点で push しておく（作業単位の worktree がここから分岐し、途中クラッシュしても成果が remote に残る）

### S-0-3. state.json にモード情報を足す

通常モードのスキーマに以下を追加して初期化する:

```json
{ "mode": "single-pr", "base_branch": "<base>", "int_branch": "<int>", "pr_number": null, "integrated_count": 0 }
```

## フェーズ S-1: 実装系 sweep の統合（issue-sweep / refine-sweep）

通常モードのフェーズ2（in-flight パイプライン）をそのまま回す。差分は以下だけ。

### 起動時（agent プロンプトの差分）

- worktree の分岐元は **ベースブランチではなく `$int_branch`**:
  `git worktree add <path> -b <work_branch> "$int_branch"`
- **PR を作らせない。** `gh pr create` を禁止し、`--no-pr` を付けたサブスキル（`/impl #<n> --auto --no-pr` 等）で commit + push までにする
- **作業単位ごとの研磨（`/refine-git`）は起動させない。** 研磨は S-2-0 で統合ブランチにまとめて 1 回だけ回す。
  作業単位ごとに回すと、(a) 同じ指摘が作業単位の数だけ別々に検出・修正されて丸ごと無駄になり、
  (b) 各作業単位の差分しか見えないので **バッチ間の重複・API 不整合・統合起因の劣化は誰も見ない**
- 作業単位のゲートは **サブスキルが回すテストと lint が通っていること**。通らなければ success ではなく failure を返させる
- 返答 JSON は `pr_number` / `pr_url` / 研磨系フィールドの代わりに `"work_branch": "<ブランチ名>"` を返させる:
  `{"issues": [<a>,<b>], "work_branch": "<name>", "worktree": "<絶対パス>", "skills": [...]}`

### 統合（メインスレッド、**必ず 1 件ずつ直列**）

agent が success JSON を返したら、メイン作業ツリー（`$int_branch`）で取り込む:

```bash
assert_not_base "$main_worktree"   # 取り込み先が統合ブランチであることを毎回確認する
git fetch origin "$work_branch"
git merge --no-ff --no-edit "$work_branch"
```

| 結果 | 実行すること |
|---|---|
| 成功 | `git push origin "$int_branch"` → worktree 掃除 → `git branch -D "$work_branch"` と `git push origin --delete "$work_branch"` → metrics に `status:"integrated"` → Issue close はせずキュー行だけ削除（close は S-3） |
| 競合 | `git merge --abort` → 下記 rebase agent を **1 回だけ** 起動 → 再 merge |
| 再 merge も競合 | `git merge --abort` → そのバッチを諦める。Issue にコメント、metrics に `status:"merge_conflict"`、**キュー行を削除**（残すと Stop Hook が永久に停止をブロックする）。他バッチの処理は続行する |

**rebase agent プロンプト:**

```
worktree <worktree_path> のブランチ <work_branch> が統合ブランチ <int_branch> と競合しました。

1. `cd <worktree_path> && git fetch origin && git rebase origin/<int_branch>`
2. 競合を解消する。**どちらか一方を機械的に採用しない** — 双方の意図を残す形で解消する
3. テストと lint を通す
4. `git push --force-with-lease`

返答は JSON 1 行のみ:
{"work_branch": "<name>", "rebased": true}
{"work_branch": "<name>", "failure": "<1行で原因>"}
```

### CI

**各統合では CI 緑を待たない。** CI は最終 PR で 1 回だけ回す。`git push origin "$int_branch"` の結果を観測する必要はない。

## フェーズ S-1': ドキュメント系 sweep の統合（spec-sweep / report-sweep）

- 項目ごとの `feat/#<Issue番号>` ブランチは**作らない**。全項目を `$int_branch` 上で順に処理する
- 項目間の「ベースブランチに戻る」手順は**統合ブランチに居続ける**に読み替える（checkout しない）
- 各項目のコミット後に `git push origin "$int_branch"`
- Issue は open のまま残す（後で `/impl #N` に渡す設計）。最終 PR は Issue をリンクするだけで close しない

## フェーズ S-2: 統合研磨・最終 PR の作成・CI・マージ

キューが空 ∧ in-flight 0 ∧ **spinoff 追跡の round も打ち止め**（後述）になってから 1 回だけ実行する。

### S-2-0. 統合研磨（必須）

統合ブランチに積んだ全差分を **まとめて 1 回だけ** 研磨する。作業単位ごとに研磨しないのはこのため。
メインスレッドはコードに触らないので `Agent` ツール（`subagent_type: claude`）に丸投げする。

```
統合ブランチ <int_branch> に積まれた差分をまとめて研磨してください。メインスレッドには JSON だけを返します。

1. 統合ブランチの先端から worktree を 1 つ作る。**<int_branch> 自体を checkout しない**
   （メイン作業ツリーが掴んでいるため失敗する）。専用ブランチを切る:
   ts=$(date +%Y%m%d-%H%M%S)
   git fetch origin
   git worktree add <repo>-refine-$ts -b sweep/refine-$ts "origin/<int_branch>"
   cd <repo>-refine-$ts
2. `/refine-git --no-merge --skip-minor --max-iter 3 --base-ref "origin/<base_branch>"` を Skill ツールで起動する。
   - `--base-ref` は **ベースブランチ**（統合ブランチではない）。sweep が積んだ全差分が対象になる
   - `--skip-minor` 必須: マージゲートは minor を見ない。minor は直すたびに差分が広がって新しい minor が生える
   - `--max-iter 3`: 統合差分は 1 作業単位より大きいので通常の 2 では収束しない
3. 修正コミットがあれば push する: `git push -u origin sweep/refine-$ts`
4. 成功時の JSON 1 行:
   {"work_branch": "sweep/refine-<ts>", "worktree": "<絶対パス>", "refine_status": "<clean|iter_limit|no_progress>", "refine_iters": <K>, "critical_remaining": <N>, "major_remaining": <N>, "minor_remaining": <N>, "pushed": <true|false>}
   起動自体に失敗した場合: {"failure": "<1行で原因>", "worktree": "<作成済みなら絶対パス>"}

返答ルール:
- 上記 JSON 以外を最終メッセージに含めない。
- PR 作成・マージはしない（メインスレッドの責務）。
- 修正が 1 件も無かった場合は `pushed: false` で返す。
```

**取り込み**: `pushed: true` なら S-1 の統合手順（`git merge --no-ff` → `git push origin "$int_branch"` → worktree 掃除 →
作業ブランチ削除）をそのまま使う。キューが空で他に in-flight が居ないので競合は起きない。
万一競合したら S-1 と同じく rebase agent 1 回 → 諦め（諦めた場合は研磨なしとして扱う）。

**判定**:

| 結果 | 実行すること |
|---|---|
| `critical_remaining == 0 ∧ major_remaining == 0` | S-2-1 へ（PR 作成 → CI → マージ） |
| どちらかが残る | S-2-1 で **PR は作るがマージしない**。`sweep_notify "Manual intervention needed"`、`termination_reason: "manual_intervention"` で S-3 へ。PR 本文に残指摘を列挙する |
| `failure` / 取り込み断念 | 研磨なしとして S-2-1 へ進み、PR 本文とレポートに「統合研磨に失敗（理由）」を明記する |

**作業単位を落とすことはしない。** 統合済みの差分はもう戻せないので、critical/major が残った場合の唯一のゲートは
「マージせず人に返す」こと。

### S-2-1. PR 作成

```bash
git push origin "$int_branch"
gh pr create --base "$base_branch" --head "$int_branch" --title "<title>" --body-file <body>
```

- タイトル: `<type>: <sweep の目的>（#<a>, #<b>, …）`。対象が 6 件以上なら `#<a>, #<b> ほか N 件`
- 本文: 統合した作業単位を 1 行ずつ列挙（Issue 番号 + やったこと）、統合できなかったものは「未統合」として理由付きで列挙、`refine-git` の結果サマリ（critical/major/minor 残数）
- `gh pr edit <PR> --add-issue <各 Issue URL>` で全件リンクする。**`Closes #N` は使わない**（close は S-3 で明示的に行う）
- PR 番号を state.json の `pr_number` に記録する

### S-2-2. CI 待ちとマージ（**メインスレッドが行う。agent に投げない**）

```bash
gh pr view "$pr" --json state,statusCheckRollup
```

を 60 秒間隔で観測し:

- 全 check 完了 ∧ FAILURE なし ∧ `state == "OPEN"` → `gh pr merge "$pr" --merge --delete-branch`
- FAILURE あり ∧ pending 0 → **失敗 check 名を渡して** CI fix agent を起動（`$int_branch` の worktree で修正 push）。**最大 2 回**
- 上限到達 → `gh pr comment` で状況を残し、`sweep_notify "Manual intervention needed"`、`termination_reason: "manual_intervention"` で S-3 へ（PR は open のまま人に返す）

CI fix agent のプロンプトは通常モードのものをそのまま使う（branch を `$int_branch` に差し替えるだけ）。

## フェーズ S-3: Issue close とレポート

- PR がマージされた場合のみ、**統合済みの全 Issue を** close する:
  `gh issue close <n> --comment "Closed by PR #<PR>（single-pr sweep / integration branch: <int_branch>）"`
  （spec-sweep / report-sweep は close しない。S-1' 参照）
- `split-from:` の兄弟が全 close なら親も close する（通常モードと同じ）
- `git worktree prune`
- レポート冒頭の Summary に必ず入れる:
  ```
  - Mode: single-pr
  - Base branch: <base_branch>
  - Integration branch: <int_branch>
  - PR: <pr_url>（<merged|open（要手動対応）>）
  - Integrated: <N> / Not integrated: <M>
  ```
- 「未統合」セクションに `merge_conflict` / `agent_failed` の作業単位を理由付きで列挙する
- `phase=terminal` にするのは **PR のマージ確認（または手動対応行きの確定）の後**。PR を出しただけで terminal 化しない

## spinoff 追跡との関係

通常モードでは round ごとに PR が増えるが、single-pr モードでは **spinoff の round も同じ統合ブランチに積む**。

- spinoff 検出（フェーズ3-0）を **S-2 の前**に実行する
- 追跡する round がある → 新キューを書き出してフェーズ2（= S-1）に戻る。統合ブランチはそのまま使い回す
- round が打ち止めになってから S-2 に進む

## 禁止行動（single-pr モード共通）

- **P-0 を飛ばして S-0 に入る**（ベース未確定のまま統合ブランチを切ることになる。`branch-preflight.md` 参照）
- **作業単位ごとに PR を作る**（`gh pr create` はメインスレッドが S-2 で 1 回だけ叩く）
- **統合ブランチを push せずローカルだけで進める**（クラッシュで全成果が消える。S-0-2 と各統合後に push する）
- **統合 merge を並列に走らせる**（メイン作業ツリー 1 本を共有している。取り込みは必ず直列）
- **統合のたびに CI 緑を待つ**（このモードの利点を丸ごと消す。CI は最終 PR で 1 回）
- **作業単位ごとに `/refine-git` を起動する**（同じ指摘を作業単位の数だけ検出・修正することになる。研磨は S-2-0 で 1 回）
- **S-2-0 の統合研磨を飛ばして最終 PR を出す**（single-pr モードではここが唯一のレビューゲート）
- **統合研磨の `--base-ref` に統合ブランチを渡す**（差分が空になり `refine-git` が exit 2 で落ちる。渡すのは `origin/$base_branch`）
- **統合研磨をメイン作業ツリーで直接走らせる**（`$int_branch` を掴んでいるので worktree 作成に失敗する。専用ブランチを切った agent に投げる）
- **競合したバッチをキューに残したまま次へ進む**（Stop Hook が永久に停止をブロックする。諦めたら必ず消して metrics に残す）
- **最終 PR のマージ前に `phase=terminal` にする**
- **Issue を PR 本文の `Closes #N` で閉じる**（S-3 の明示 close に統一する）
- ベースブランチ / 統合ブランチを途中で変える
