> 注: このファイルは `~/dotfiles` リポジトリ全体（fish / nvim / tmux / install scripts / `.claude/` 配下のスキル類すべて）の変更履歴です。

## [v0.5.0] - 2026-07-08

Atomic Design レビューの導入、sweep 系スキルの UX 統一、外部 agent-skills のマニフェスト化、Codex 環境整備を中心にしたリリース。

### ✨ New Features / 新機能

- Add `atomic-review` skill for Atomic Design compliance / Atomic Design 準拠レビュー用 `atomic-review` スキルを Claude / Codex 両方に追加。Next.js / Nuxt v3・v4 / 素の React / 素の Vue を自動判定し、依存方向・配置妥当性・layout 使用・命名・prop drilling・FW 固有ルール（'use client' 境界、Nuxt auto-import、v3→v4 srcDir 差異）をチェック
- Enforce Atomic Design in refine for frontend projects / `refine` / `refine-sweep` のフェーズ 1 に HAS_ATOMIC 検知と `atomic-review` 並列起動を追加。フロントエンド (react/vue/next/nuxt) かつ Atomic 未採用の場合は `termination_reason=atomic_design_required` で中断
- Add `impl-type-r` / `impl-type-wr` skills / `impl → refine` を連続実行し、実装から研磨・CI 緑マージまで一気通貫するスキルを追加（`impl-type-wr` は worktree 隔離版）
- Add `report-sweep` skill / 機能要望とバグ報告を一括ヒアリングし、バグは Issue のみ・機能要望は Issue+ブランチ+`spec-gen` 実行まで走らせる `report-sweep` スキルを追加
- Add `spec-sweep` skill / 複数仕様追加を事前計画で一括ヒアリングし、Issue/ブランチごとに `spec-gen` を順次実行する `spec-sweep` スキルを追加
- Add manifest-based external agent-skills management / 外部 agent-skills をマニフェスト方式（`agent-skills.txt`）で管理する仕組みと `install_agent_skills` を追加
- Add `sync_codex_mcp` helper / Claude の MCP 設定 (`claude-mcp/mcp.json`) を Codex 用 (`~/.codex/config.toml`) に同期する `sync_codex_mcp` を install.sh に追加
- Add global `.codex/AGENTS.md` / Codex 用グローバル指示ファイル `.codex/AGENTS.md` を追加し `install.sh` で `~/.codex/AGENTS.md` に symlink

### 🐛 Bug Fixes / バグ修正

- Fix agent-skills conflict guard to follow symlinks / `install_agent_skills` の Codex 側衝突ガードを symlink 先で判定する形に修正し、既存 symlink スキルとの誤検知を回避
- Fix supabase MCP env loading / supabase MCP の env を sh ラッパー経由で `~/.env` から読む形に変更し、Claude Code / Codex 起動時に env が抜ける問題を修正

### 🔧 Improvements / 改善

- Unify sweep skills on upfront hearing / sweep 系スキル（`issue-sweep` / `refine-sweep` / `report-sweep` / `spec-sweep`）を「初回一括ヒアリング＋以降割り込みなし」の UX に統一
- Extend report-sweep to run spec-gen for feature requests / `report-sweep` の機能要望フローを Issue 作成だけでなく `spec-gen` 実行まで走らせる形に拡張
- Bump supabase MCP 0.5.10 → 0.8.2 / supabase MCP を 0.5.10 から 0.8.2 にバンプ
- Loosen issue-sweep split-from sequential rule / `issue-sweep` の split-from sequential ルールを、並列セーフな条件を満たす場合に限り上書き可能に緩和

### 📝 Documentation / ドキュメント

- Update README with Fugu / Codex skills / partial install / fish aliases / README に Fugu、Codex 用スキル、`./install.sh <name>` 個別実行、fish エイリアス (`x` / `fugu`) の説明を追記
- Trim redundant intros / `SKILL.md` / `AGENTS.md` 冒頭の冗長な紹介文を削除して本題からすぐ読めるように整理

### 🏗️ Infrastructure / インフラ

- Ignore runtime state and plugin lock files / `.sweep/` などのランタイム状態ファイル、`fish_plugins.lock` などのプラグインロックファイルを `.gitignore` に追加

## [v0.4.0] - 2026-06-25

Claude Code 用に育てたスキル一式を Codex CLI / Fugu からも使えるように移植したリリース。

### ✨ New Features / 新機能

- Port 35 Claude skills to Codex CLI format / `~/dotfiles/.claude/skills/` 配下のスキル 35 件（`bug-fix` / `impl` / `refine` / `issue-sweep` / `spec-gen` / `release` 等）を Codex CLI 用フォーマット (frontmatter は `name` / `description` のみ、本文は harness 非依存の自然言語) で `~/dotfiles/.codex/skills/` に再構成。Codex / Fugu でも同じワークフローを呼び出し可能に
- Add `link_codex_skills` helper to install.sh / `lib/common.sh` に `link_codex_skills` を追加し、`install.sh` の `main` から呼んで `~/dotfiles/.codex/skills/<name>` → `~/.codex/skills/<name>` の symlink を idempotent に作成。Codex 公式バンドル (`.system/` 配下) は除外
- Naturalize Claude-specific tool vocabulary / `AskUserQuestion` / `TaskCreate` / `Agent(subagent_type=...)` / `Skill()` / `WebFetch` 等の Claude 固有ツール参照を「選択式で確認」「進捗を管理」「サブエージェントを起動して並列実行」のような harness 非依存表現に置換
- Preserve auxiliary resources verbatim / `templates/` / `references/` / `scripts/` などの補助ファイルは harness 非依存のためそのままコピー（spec-to-hugo の Hugo / Cloudflare Worker テンプレ群、halt-review のチェック基準集、code-review の観点別 references など含む）

## [v0.3.0] - 2026-06-25

Fugu (Sakana AI の Codex 設定バンドル) の install パイプライン統合と、sweep / refine 系スキルの安定化リリース。

### ✨ New Features / 新機能

- Add `install_fugu` to install.sh / `curl -fsSL https://sakana.ai/fugu/install | bash` を install パイプラインに統合。`~/.env` の `SAKANA_API_KEY` を拾えれば非対話で導入、無ければ warn してスキップ
- Add `./install.sh <name>` partial-run mode / 引数指定で個別 `install_*` 関数だけ走らせるモードを追加。全体セットアップを通さず 1 ツールだけ入れ直せる
- Add `make fugu` target / Fugu だけ単独でインストールするための Makefile ターゲットを追加
- Add fish aliases `x` / `fugu` / fish に `codex` / `codex-fugu` を `--dangerously-bypass-approvals-and-sandbox` 付きで叩く `x` / `fugu` エイリアスを追加（Claude の `c` と同じ感覚で起動）
- Add `SAKANA_API_KEY` to `.env.example` / `.env.example` に `SAKANA_API_KEY` のコメント例を追加
- Track all open issues for spinoff in refine-sweep / `/refine-sweep` の 3-0 を spinoff 限定から全 open Issue 追跡に拡張し、残 Issue を `/issue-sweep` へ自動委譲（`impl-wt` 直接起動に変更）
- Add hard_cap and double-confirm review in refine-sweep / `/refine-sweep` に hard_cap と double-confirm review を追加して暴走を抑制
- Add allow_auto_merge preflight and direct merge mode / sweep 系スキルに allow_auto_merge の preflight と direct merge モードを追加
- Auto-continue spinoff tracking until queue empty / sweep の spinoff 追跡を全 Issue 消費するまで自動継続するデフォルトに変更
- Add `.sweep/state.json` and Stop Hook terminal enforcement / sweep 系スキルに `.sweep/state.json` と Stop Hook による terminal 強制を追加

### 🐛 Bug Fixes / バグ修正

- Fix spinoff detection in sweep / sweep の spinoff 検出を `spinoff-issue` 出力に合わせて修正
- Fix fix_ineffective judgement in refine-sweep / `/refine-sweep` の fix_ineffective 判定を件数比較から fingerprint set 比較に変更（同件数でも fingerprint が変わっていれば前進とみなす）

### 🔧 Improvements / 改善

- Unify sweep skills on direct merge / sweep 系スキルを direct merge 一本化（auto-merge を廃止）
- Drop `--max-iter` soft cap in refine-sweep / `/refine-sweep` の周回数ソフト上限 `--max-iter` を廃止し hard_cap に集約
- Switch global gitignore to symlink-based / global gitignore を cp ベースから symlink (`~/.gitignore`) ベースに変更
- Move global gitignore setup to install time / SessionStart hook 方式をやめて dotfiles install 時に global gitignore を設定する方式へ
- Raise refine-sweep `max_minor` default to 5 / `/refine-sweep` の `max_minor` デフォルトを 0 → 5 に変更（`/refine` / `/issue-sweep` と揃える）

## [v0.2.0] - 2026-06-21

`/issue-sweep` / `/refine` / `/refine-sweep` の三点セットを中心とした **自律 Sweep & Refine ワークフロー** の追加。

### ✨ New Features / 新機能

- Add `/issue-sweep` skill for autonomous Issue-to-merge loop / 複数 OPEN Issue をキュー化し Stop Hook と連動して自律的に実装→auto-merge→Issue close まで進める司令塔スキルを追加
- Add `/refine` skill for iterative review-fix-merge polishing / review→修正→再 review を回して critical/major=0 ∧ minor≤閾値 まで PR を磨き上げ auto-merge と Issue close まで実行するスキルを追加
- Add `/refine-sweep` skill for repo-wide continuous polishing / リポジトリ全体に対して 4 観点 review→fix→PR→auto-merge を反復し critical/major=0 まで持っていく全体版 refine を追加
- Add `/issue-split-auto` for non-interactive Issue splitting / 大型 Issue を自律的にサブ Issue へ分割する非対話版スキルを追加（issue-sweep のフェーズ1 から呼ばれる）
- Add Stop Hook + SessionStart Hook for sweep continuity / `.sweep/queue.txt` 残時に停止をブロックする Stop Hook と、セッション開始時にオープン Issue 一覧を注入する SessionStart Hook を追加
- Parallel processing with `--parallel N` / 独立 Issue を最大 5 並列で処理する並列モードを追加
- 4-perspective parallel review / 各反復で `/code-review` / `/doc-drift` / `/spec-audit`（HALT 検知時は `/halt-review`）を並列起動して findings を集約
- Domain-staged parallel PRs in refine-sweep / 仕様書からドメイン一覧（frontend / backend / db / ci 等）を抽出し各反復でドメインごとに別 PR を並列起動、db → backend/frontend/ci の依存ウェーブで実行
- Spinoff Issue auto-tracking / sweep 開始後に作成された Parent ラベル/本文を持つ Issue を spinoff として検出、デフォルト 2 周まで自動再 sweep（`--max-rounds N` で制御、最大 5）
- refine-sweep auto-delegates spinoffs to issue-sweep / refine-sweep のフェーズ3 で spinoff を検出し `Agent(claude)` 経由で `/issue-sweep` を自動起動して実装まで委譲
- Heartbeat-based stale lock recovery / `.sweep/lock` の鮮度判定（2h）で stale を救済し誤ブロックを防止
- Telemetry to `.sweep/metrics.jsonl` and `.sweep/refine-metrics.jsonl` / 各 Issue / 反復の処理結果を JSON 1 行追記
- Project-scoped webhook notifications / `.sweep/notify.url` で Slack / Discord / ntfy.sh を URL パターンから自動判別して通知
- Auto-generated Markdown reports / フェーズ3 終了時に `.sweep/report-{sweep,refine,refine-sweep}-<ts>.md` を自動生成
- Worktree-isolated execution / 各 Issue を独立 worktree で実行、起動前後に差分検知して orphan を毎反復削除、フェーズ3 完了時に `git worktree prune`
- HALT project auto-detection / `*.templ` ファイル存在または仕様書の HALT 記述で自動検知し `/halt-review` を追加
- Parent issue auto-expansion / `/issue-sweep #<parent>` 指定時、`split-from:#<parent>` ラベル付き子 Issue を持つなら子に展開してそのフェーズだけ実装
- Merge gate via refine results / refine 結果を見て critical/major 残ありなら auto-merge を予約せず failure として手動対応へ falls back

### 🔧 Improvements / 改善

- Move sweep runtime state from `.claude/` to `.sweep/` / Claude Code の sensitive-file ガード回避のため sweep 系のキュー・lock・テレメトリを `.sweep/` ディレクトリに移動
- Refresh base branch on each Issue / 各 Issue 着手前に base branch を最新化し、直前のマージ分を取り込んでから次の修正を始める
- Auto-sequential for dangerous cases / 並列度はユーザー確認せず、危険ケースのみ自動で sequential 化
- Enforce CTO discipline in refine-sweep engineer agent / fix → PR → CI 待ちを engineer agent 内に閉じ込めメインスレッドはオーケストレーションに専念
- Set `defaultMode` to `bypassPermissions` for unattended operation / 完全無人化のため defaultMode を bypassPermissions に変更し Skill 許可漏れを補填
- Specify gh/git subcommand-level permission patterns / 許可パターンを具体化（gh/git のサブコマンド単位 + `.claude/` への書き込み）
- Expand `permissions.allow` for sweep operations / `gh pr/issue/run/api/label/workflow/repo/release/auth`, `git status/log/diff/branch/checkout/switch/fetch/pull/push/add/commit/merge/worktree/remote/stash/rev-parse/ls-files/config --local`, POSIX 各種, `curl`, `mkdir/cp/mv/test/kill -0/ps` を事前承認
- Allow `Write/Edit/Read(.sweep/**)` / sweep ランタイムの書き込みを一括許可

### 🐛 Bug Fixes / バグ修正

- Ensure `/refine` always runs inside a worktree / `/refine` も常に worktree 内で動作することを明示
- Move `/refine` from git-diff version to full version / `/refine` を git 版から通常版に切り替え、issue-sweep にも refine を統合

### File layout

| パス | 役割 |
|---|---|
| `.claude/skills/issue-sweep/SKILL.md` | sweep スキル本体 |
| `.claude/skills/refine/SKILL.md` | refine スキル本体 |
| `.claude/skills/refine-sweep/SKILL.md` | refine-sweep スキル本体 |
| `.claude/skills/issue-split-auto/SKILL.md` | 非対話的 Issue 分割スキル |
| `.claude/hooks/check-issue-queue.sh` | Stop Hook 実装 |
| `.sweep/queue.txt` | sweep キュー（gitignore） |
| `.sweep/lock` | 多重起動防止 lock（gitignore） |
| `.sweep/metrics.jsonl` | sweep テレメトリ（gitignore） |
| `.sweep/refine-metrics.jsonl` | refine テレメトリ（gitignore） |
| `.sweep/notify.url` | Webhook URL（gitignore） |
| `.sweep/report-{sweep,refine,refine-sweep}-*.md` | 自動生成レポート（gitignore） |

### Usage example

```bash
# Slack 通知をプロジェクトで有効化
echo "https://hooks.slack.com/services/T0XXX/B0XXX/xxxx" > .sweep/notify.url

# 全 OPEN Issue を端から実装→マージ→close まで
/issue-sweep

# sprint-1 ラベルだけ、並列 3
/issue-sweep label:sprint-1 --parallel 3

# 特定 PR を「軽微指摘 5 個以下」まで研磨
/refine #127

# コードベース全体を critical+major=0 まで磨く
/refine-sweep
```

---

## [v0.1.0] - 2026-05-11

初回ベースラインリリース。Mac / Ubuntu 両対応の dotfiles 一式（シェル・エディタ・言語ツールチェイン・Claude Code スキル群）。

### ✨ New Features / 新機能

#### Install / Update / Reset

- Cross-platform install for Mac and Ubuntu / Mac/Ubuntu 両対応化と言語ツール（uv/bun/rustup/fnm/Go）の自動インストール
- `install.sh` modularization into `lib/` / `install.sh` を `lib/` 配下に責務別分割
- Install `gh` and `gcloud` / `install.sh` に `gh` / `gcloud` のインストール処理を追加
- Install MolePort and Linterly / `install.sh` に MolePort / Linterly のインストールを追加
- Install cloudflared / wrangler / netlify-cli / pm2 / Cloudflare 系 + Node デプロイ系ツール群を追加
- Install Claude Code / Codex CLI / Gemini CLI / 主要 AI CLI を `install.sh` に統合
- `update.sh` and `make update` / 各ツールの update 関数と `update.sh` / `make update` を追加
- `reset-tools.sh` to reset language/AI tools / 言語ツール/AI CLI をリセットして再インストールする `reset-tools.sh` を追加
- Makefile install/update/reset/help targets / Makefile に install/update/reset/help ターゲットを追加

#### Shell / Editor

- Initial nvim / tmux / fish dump and setup / nvim/tmux/fish の初回ダンプとセットアップスクリプトを追加
- gh-dash configuration / gh-dash の設定を dotfiles に追加
- `tide-config.fish` to carry the tide prompt across machines / tide プロンプト設定を新マシンに引き継ぐ `tide-config.fish` を追加
- `cc` alias for `claude --continue` / claude --continue 用の cc エイリアスを追加
- Dotfiles-managed PATH (fish/bash) / PATH 設定を fish/bash 両対応で dotfiles 管理化
- Auto-pull dotfiles on interactive shell start / 対話シェル起動時に dotfiles を自動 pull する fish 設定を追加（後に throttle 削除）

#### Configs / Secrets

- Consolidate `~/.env` as the single env-var store / `~/.env` はsecret/非secret問わず全 env 変数の保管場所
- `.env` body moved to dotfiles, `.mcp.json` reorganized to `claude-mcp/` / `.env` 実体を dotfiles に移動し `.mcp.json` を `claude-mcp/` ディレクトリに整理
- `.claude/` and `.mcp.json` integrated into dotfiles / `.claude/` と `.mcp.json` を取り込み `~/.env` 集約方式に変更

#### Claude Code Skills

- `spec-gen` with project overview document generation / spec-gen にプロジェクト概要ドキュメント生成を追加
- `spec-review` per-finding commit flow / spec-review で指摘 1 件ごとにコミットする手順を追加
- `env-setup` pins TS/JS package manager to bun / env-setup で TS/JS のパッケージマネージャを bun に固定
- `issue-split` copies related spec into sub-issue body / issue-split でサブ Issue 本文に関連仕様を転記
- `spinoff-issue` / `spinoff-issue-en` skills + impl integration / spinoff-issue 系スキルを追加し impl 系から呼び出せるよう接続
- `impl` skills force immediate spinoff Issue creation / impl 系スキルで spinoff-issue の即時作成を強制
- `bug-report` Issue title/label unified rules / bug-report スキルに Issue タイトル・ラベルの統一ルールを追加
- `spec-to-hugo` with Cloudflare Workers + Static Assets deploy / spec-to-hugo に Cloudflare Workers + Static Assets デプロイ設定を追加
- `spec-to-hugo` Basic auth via env / spec-to-hugo に env ベースの Basic 認証を追加

#### Claude Code Settings

- `skipAutoPermissionPrompt` in `settings.json` / `settings.json` に `skipAutoPermissionPrompt` を追加
- `AskUserQuestion` usage principles in CLAUDE.md / CLAUDE.md に AskUserQuestion 利用原則を追加

### 🔧 Improvements / 改善

- Simplify `spec-to-hugo` Cloudflare deploy for UI integration / spec-to-hugo の Cloudflare デプロイを UI 連携前提に簡素化
- Add runtime data entries to `.claude/.gitignore` / `.claude/.gitignore` にランタイムデータ項目を追加
- Remove dotfiles auto-pull throttle / dotfiles 自動 pull のスロットルを削除し毎回実行に変更
- Make `secrets.fish` missing a fatal error in install.sh / secrets.fish が無い場合は `install.sh` をエラー終了させる
- README with command list / README にコマンド一覧を整備

### 🐛 Bug Fixes / バグ修正

- fish PATH adds system paths (`/usr/local/bin` etc.) / fish の PATH に `/usr/local/bin` 等のシステムパスを追加
- `brew install/upgrade` per-package loop for fault tolerance / brew install/upgrade を per-package ループで耐障害化
- `install_go` warns on version-fetch failure instead of aborting / `install_go` の version 取得失敗時に script abort せず警告で継続
- Unfreeze fisher plugin commits for new-machine install / fisher プラグインの commit を解除し新マシンでの install.sh 失敗を修正
- nvim plugin sync uses `Lazy! restore` / install.sh の nvim プラグイン同期を `Lazy! sync` から `Lazy! restore` に変更
- `fnm.fish` loads before `paths.fish` / `fnm.fish` が `paths.fish` より先にロードされる順序問題を修正
- nvim config inconsistencies / nvim 設定の不整合を修正
- `spec-to-hugo` root → /docs/ redirect on edge / spec-to-hugo のルート→/docs/ リダイレクトをエッジ側で処理
- `spec-to-hugo` unified on bun for Cloudflare deploy / spec-to-hugo を bun ベースに統一し Cloudflare デプロイを通す

### 📝 Documentation / ドキュメント

- `~/.env` is the storage location for all env vars / `~/.env` はsecret/非secret問わず全 env 変数の保管場所であることを明記
