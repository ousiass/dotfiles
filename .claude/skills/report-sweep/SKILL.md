---
name: report-sweep
description: 機能要望とバグ報告を一括ヒアリングし、バグは Issue のみ・機能要望は Issue+ブランチ+spec-gen まで実行する
user-invocable: true
---

# report-sweep

複数の機能要望・バグ報告を 1 セッションでまとめて処理する。

- **バグ報告**: 軽量な GitHub Issue 起票のみ（原因調査・修正は後で `/bug-fix #N`）
- **機能要望**: Issue 作成 + `feat/#N` ブランチ + `spec-gen` による仕様書追記まで自動実行

## いつ使うか

- 溜まった要望・バグをまとめて処理したいとき
- 1 件ずつ `/bug-report` `/spec-gen` を起動するのが煩わしいとき
- バグは受け皿の Issue だけあればよく、機能要望は仕様書まで一気に整えたいとき

バグ修正まで走らせたい場合は別途 `/bug-fix #N`。単発の機能追加なら `/spec-gen` を直接呼ぶ。

## 前提条件

- Claude Code 環境
- `gh` CLI と認証済みリポジトリ

## 引数

- **テキスト**（例: `/report-sweep ログインまわりのバグと通知機能追加`）: 初期メモとして扱う
- **引数なし**: 最初からヒアリング開始
- `--single-pr`: **1 統合ブランチ集約モード**。機能要望ごとに `feat/#N` ブランチを切らず、統合ブランチ 1 本に全仕様書を積み、最後にベースブランチへ PR を 1 本だけ出す
- `--multi-pr`: 機能要望ごとに `feat/#N` ブランチを切る従来モード
- `--base <branch>`: ベースブランチ（PR のマージ先）
- `--branch <name>`: 統合ブランチ名。デフォルト `sweep/report-sweep-<YYYYmmdd-HHMMSS>`

**`--single-pr` / `--multi-pr` と `--base` は、指定がなければフェーズ P-0 で `AskUserQuestion` で必ず聞く。推測で決めない。**

## single-pr モード（`--single-pr`）

有効時は **`~/.claude/skills/issue-sweep/references/single-branch-mode.md` を読んでから**フェーズ0 に入る（`skill_name="report-sweep"`）。バグ側は Issue 起票だけなので影響を受けない。**差分は機能要望（spec-gen 実行）の流し方だけ**:

| 箇所 | single-pr での差し替え |
|---|---|
| P-0 の直後 | S-0 を実行。P-0 で確定したベースから統合ブランチを切って push する |
| フェーズ2 の計画提示 | 機能要望に `→ 統合ブランチ <int_branch> 上で spec-gen` と表示し、末尾に `最終的に <base_branch> へ PR 1 本` を添える |
| 3-5 手順1 | `feat/#<Issue番号>` ブランチ作成を**行わない**（統合ブランチ上で作業する） |
| 3-5 手順3 | push 先は統合ブランチ（項目ごとに `git push origin "$int_branch"`） |
| 3-5 手順4 | 「ベースブランチに戻る」を**統合ブランチに居続ける**に読み替える |
| フェーズ4 の前 | 機能要望が 1 件以上あれば S-2 を実行して最終 PR を作り、CI 緑を待ってマージする。**Issue は close しない**（後で `/impl #N` `/bug-fix #N` に渡す設計） |
| フェーズ4 の報告 | ブランチ名の代わりにベース / 統合ブランチ / PR URL を提示する。バグ Issue の一覧は変更なし |

機能要望が 0 件（バグのみ）だった場合は統合ブランチに何も積まれないので、**PR を作らず統合ブランチを削除して終わる**（`git checkout "$base_branch" && git branch -D "$int_branch" && git push origin --delete "$int_branch"`）。

## フェーズ0: 前提スキャン

- `spec-gen` SKILL.md フェーズ 1-0 の手順で既存仕様書ディレクトリを探索し、ベースマップを Read で把握する
- ベースブランチは次のフェーズ P-0 で確定する（**現在ブランチ名をそのままベースとして記録しない**）
- 仕様書が見つからない場合、機能要望は spec-gen が新規設計モードになってしまうため、**バグのみモード**に切り替えるかユーザーに一言添えて続行（判断できなければバグのみモード＝機能要望は Issue 起票までで停止）

## フェーズ P-0: モードとベースブランチの確定（必須）

フェーズ0 の直後、フェーズ1 の**前**に実行する。**`~/.claude/skills/issue-sweep/references/branch-preflight.md` を読んでその手順どおりに実行する。スキップ不可。**
`--single-pr` / `--multi-pr` と `--base` の両方が引数で確定している場合のみ、ヒアリング（P-0-2）を省略できる。

ここで確定するもの:

- `mode`（`single-pr` = 統合ブランチ 1 本＋最終 1 PR / `multi-pr` = 機能要望ごとに `feat/#N`）
- `base_branch`（**現在の HEAD を推測で採用しない**）
- `main_worktree` と事前ガード関数 `assert_not_base`

`mode=single-pr` なら続けて S-0 へ、`multi-pr` ならフェーズ1 へ進む。以降「ベースブランチ」と書かれた箇所はすべて P-0 で確定した `$base_branch` を指す。
バグのみで終わる可能性があってもここは飛ばさない（種別はフェーズ1-2 まで確定しないため）。

## フェーズ1: 一括計画

### 1-1: 項目数と運用方針

`AskUserQuestion` で以下を確認（1 回にまとめる）:

1. **項目数**（自由入力可、1〜20 程度）
2. **重複チェック**: 「各項目で実行（推奨）」/「スキップ」
3. **プレビュー承認**: 「各項目で確認」/「一括承認（信頼モード）」
4. **機能要望の仕様策定**: 「Issue+spec-gen まで実行（推奨）」/「Issue のみで停止」

これ以降は原則追加質問しない。判断に迷うことはコードや仕様書を読んで自分で決める。

### 1-2: 各項目の詳細を一括収集

項目ごとに 1 回の `AskUserQuestion` にまとめる。バグ・機能要望共通で以下を集める:

**共通**:
1. **タイトル案**（自由入力、1 行）
2. **種別**: `バグ報告` / `機能要望`
3. **一言概要**（自由入力、1〜2 文）

**バグ選択時に併せて集める**:
- 重大度: `critical` / `high` / `medium` / `low`
- 再現手順（自由入力、任意）
- 領域ラベル（自由入力、任意）

**機能要望選択時に併せて集める**:
- 優先度: `high` / `medium` / `low`
- 目的・背景（自由入力、任意）
- 影響する仕様書（フェーズ0 のベースマップから選択 + 新規追加候補、複数選択可）
- **CTO 確認事項**（自由入力、任意。仕様策定前に潰しておきたい重要な論点があれば箇条書きで。spec-gen が読める形で spec に書き込まれる）
- 領域ラベル（自由入力、任意）

質問数が 4 を超える場合は種別だけ先に確定させ、種別ごとに残りを 1 質問にまとめて 2 回に分ける。フェーズ 2 以降での追加ヒアリングはしない。

### 1-3: 計画確定

収集した項目を番号付きリストで提示:

```
起票予定（順序＝入力順）:
1. [Bug] ログイン失敗 — 正しいPWでも認証が通らない
2. [feat] 通知機能 — メール以外に Slack 通知を追加
3. [Bug] 検索: 日本語入力で0件になる
...
```

`AskUserQuestion` で承認を取ってから、`TaskCreate` で各項目をタスクキュー化する。

## フェーズ2: 一括承認

計画を番号付きリストで提示（起票順・種別・タイトル・ラベル案）:

```
起票予定:
1. [Bug] ログイン: 正しいPWでも認証が通らない
   labels: bug, severity:high, area:auth
2. feat: Slack 通知チャンネルを追加できるようにする
   labels: enhancement, priority:medium, area:notification
   影響仕様書: requirements/functional.md, api/endpoints.md
   → spec-gen 実行あり
...
```

`AskUserQuestion` で「一括承認 / 修正指示 / 中止」を確認。承認後、`TaskCreate` で各項目をタスクキュー化し、フェーズ 3 は割り込みなしで最後まで走らせる（プレビューモードが「各項目で確認」の場合のみ Issue 直前で承認を挟む）。

## フェーズ3: 順次実行

各項目について以下を実行。ベースブランチから始める。

### 3-1: `TaskUpdate` で当該タスクを `in_progress` に

### 3-2: 重複チェック（有効な場合のみ）

```bash
gh issue list --state open --search "<キーワード>" --limit 5
```

- 類似あり → タイトルと URL を提示し、`AskUserQuestion` で「新規作成」/「既存にコメント追加」/「スキップ」から選ばせる（判断保留になる唯一の例外）
- 類似なし → 続行

### 3-3: ラベル存在チェック

Issue 作成前に:

```bash
gh label list --limit 200 --json name -q '.[].name'
```

未存在ラベルはフェーズ 2 で承認済みなら `gh label create <name>` で作成。未承認の新規ラベルが残っていればそこで承認を取る。

### 3-4: Issue 作成

**バグの場合**:

```bash
gh issue create \
  --title "[Bug] <機能>: <症状>" \
  --label bug --label "severity:<level>" [--label "area:<領域>"] \
  --body-file <bug.md 相当>
```

**機能要望の場合（Issue+spec-gen モード）**: プレースホルダーとして作成:

```bash
gh issue create \
  --title "feat: <概要>" \
  --label enhancement --label "priority:<level>" [--label "area:<領域>"] \
  --body "仕様策定中（report-sweep 実行中）。完了後に実装内容を追記する。"
```

**機能要望の場合（Issue のみモード）**: 通常の feature テンプレートで作成。

### 3-5: 機能要望のみ: spec-gen 実行

「Issue+spec-gen まで実行」モードでのみ実行:

1. `feat/#<Issue番号>` ブランチを作成してチェックアウト → 直後に `assert_not_base "$main_worktree"` で確認する（`branch-preflight.md`）。ブランチ作成に失敗したまま次に進むと仕様書がベースブランチに直接コミットされる
2. `~/.claude/skills/spec-gen/SKILL.md` の**既存仕様書追記モード**を実行
   - フェーズ 1-2 のヒアリングはフェーズ 1-2 で収集済みの `タイトル / 概要 / 目的・背景 / 影響する仕様書` を渡してスキップ
   - フェーズ 2-3 のレビュー対話はスキップ（完了後の一括 `/spec-review` を推奨）
3. spec-gen のフェーズ 3 相当（コミット + push + Issue 本文を実装 Issue 風に書き換え）を実行
4. ベースブランチに戻る

### 3-6: `TaskUpdate` で当該タスクを `completed` に

### 3-7: 次項目へ

## フェーズ4: 完了報告

サマリーを提示:

- 全項目の一覧（タイトル + URL + ブランチ名（該当時）+ ステータス: 作成 / spec-gen 完了 / コメント追記 / スキップ / 失敗）
- 失敗があれば理由と再開方法
- 次に取れるアクションの案内:
  - バグ深掘り → `/bug-fix #N`
  - 仕様レビュー → `/spec-review <仕様書パス>`（spec-gen 走らせた場合）
  - 実装着手 → `/impl #N` / `/impl-wt #N`

## タイトル・ラベル統一ルール

### タイトル形式

- **バグ**: `[Bug] <機能>: <症状>`
  - 例: `[Bug] ログイン: 正しいパスワードでも認証に失敗する`
- **機能要望**: `feat: <概要>`
  - 例: `feat: Slack 通知チャンネルを追加できるようにする`

### ラベル

**バグ**（3 種以上を付与）:

1. `bug` — 固定
2. `severity:<level>` — `critical` / `high` / `medium` / `low`
3. `area:<領域>` — ユーザーが領域ラベルを指定した場合のみ。kebab-case 英小文字

**機能要望**（2 種以上を付与）:

1. `enhancement` — 固定
2. `priority:<level>` — `high` / `medium` / `low`
3. `area:<領域>` — ユーザーが領域ラベルを指定した場合のみ

## エラー時

- 当該項目で停止し、`TaskUpdate` でタスクの状態を明示
- 完了済み項目はそのまま残す
- ユーザーに `項目 N で失敗 / 完了: 1..N-1 / 未着手: N+1..` を報告し、再開可否を確認

## ルール

- **フェーズ1 で全情報を一括収集**。フェーズ 3 以降は原則追加ヒアリングしない（重複 Issue との衝突と、承認済み `(NEW)` ラベル未承認時の 2 例外のみ）
- 質問は必ず `AskUserQuestion` を使い、1 回 4 問以内
- バグ側はコード調査しない（原因推定は書かない）。機能要望側は `spec-gen` が既存仕様書を読むためコード/仕様書スキャンは走る
- `spec-gen` 本体のロジックは複製せず `~/.claude/skills/spec-gen/SKILL.md` を参照
- 未存在ラベルはユーザー承認なしに作成しない（フェーズ 2 の一括承認に含める）
- 各 Issue は open のまま残す（後で `/impl #N` `/bug-fix #N` にそのまま渡せる）。single-pr モードでも最終 PR で close しない
- **フェーズ P-0 を飛ばさない**。モードとベースブランチを聞かずに始めない / 現在の HEAD を推測でベースに採用しない（`~/.claude/skills/issue-sweep/references/branch-preflight.md`）
- **作業ブランチを作らずベースブランチ上で仕様書をコミットしない**。ブランチ作成に失敗したらその項目を諦めて人に返す（`git reset` / `git checkout -f` で自動的に直して続行しない）
- `--single-pr` 指定時は `~/.claude/skills/issue-sweep/references/single-branch-mode.md` を読んでから進める（差分表だけで手順を推測しない）
- コミットメッセージは `<type>: <説明>` 形式（CLAUDE.md 準拠）
- `git commit` / `git push` で `--no-verify` を使わない
