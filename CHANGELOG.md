> 注: このファイルは `~/dotfiles` リポジトリ全体（fish / nvim / tmux / install scripts / `.claude/` 配下のスキル類すべて）の変更履歴です。

## [v0.7.0] - 2026-08-31

Slidev 資料の生成・レビュー用スキル（`slide-gen` / `slide-review`）の追加と、sweep 系スキルの「1 統合ブランチ → 1 PR」集約モードを中心にしたリリース。意匠まわりは配色・スタイルを CSS トークンへ切り出し、コントラストと装飾方針を機械検査できるようにした。

### ✨ New Features / 新機能

- Add `slide-gen` skill / 仕様書などのドキュメントから `slide/` に Slidev のビジュアル資料を生成する `slide-gen` を追加。テンプレート（`slides.md` / `visual.css` / Makefile / wrangler.toml）と検査スクリプト一式を同梱する
- Add `slide-review` skill / Slidev のスライドをレビューし、指摘を 1 件ずつ確認しながら修正する `slide-review` を追加。デザインモードは「機械 + 目視」で、目視の前にコントラストを実測する
- Add `--single-pr` aggregation mode to sweep skills / `issue-sweep` / `refine-sweep` / `spec-sweep` / `report-sweep` に 1 統合ブランチ集約モードを追加。作業単位ごとに PR を作らず、最初に切った統合ブランチ 1 本へ全部積み、最後にベースブランチへ PR を 1 本だけ出す。ベースブランチは `--base <branch>` か開始時の選択式ヒアリングで必ず確定させる（推測で `develop` / `main` を採らない）。手順は共有 reference `issue-sweep/references/single-branch-mode.md` に集約し、各 SKILL.md には差分表を 1 ブロックだけ置いた
- Add `--base-ref <ref>` to `refine-git` / 差分の比較先を明示指定するフラグを追加。集約モードで統合ブランチ基準の差分をレビューさせるための必須プラミングで、明示指定時は `origin/main` へ fallback せずエラーにする
- Add style presets to `slide-gen` / 角丸・カードの地/枠/影・見出しの太さと字間・kicker の横線などを `:root` の意匠トークンへ切り出し、Editorial（既定）/ Soft / Minimal の 3 プリセットを追加。スタイルと配色を独立して選べるようにした
- Add `derive-palette.mjs` / プライマリカラー 1 色から配色トークンを導出するスクリプトを追加。light / dark 双方で本文 4.5:1・構造色 3:1 を満たすまで明度を自動調整し、実測値を出力する
- Add `check-contrast.mjs` / `visual.css` の `:root` から文字色と背景色の組み合わせを実測する検査を追加。`var()` 参照を解決し複数の `:root` を後勝ちで畳むため、プリセットを末尾に追記した状態でも測れる
- Add `check-style.mjs` / グラデーション塗り・光彩・すりガラス・文字の影・絵文字アイコン・ページ内アニメーション・インラインスタイル・色の直書きを機械検出する検査を追加。セレクタを追跡し、画像上の減光など機能的なオーバーレイは通す

### 🐛 Bug Fixes / バグ修正

- Fix dark text tokens scattered across 6 values / dark 背景のテキスト色が 6 段階に散らばっていたのを 3 トークンへ集約
- Fix self-referencing `--v-card-border` / 自己参照になっており既定スタイルでカードの枠線が消えていた問題を修正
- Fix footer contrast below threshold / フッターの色が直書きでコントラストが 2.43:1 と基準未満だった問題を修正
- Fix footer placeholder colliding with Vue interpolation / `global-bottom.vue` のプレースホルダを `___ORG_NAME___` に変更。`{{ORG_NAME}}` は Vue の補間構文と衝突し、置換し忘れてもエラーにならずフッターが空になっていた
- Fix `h2` demoted from title / `h2` をタイトルに戻し、`slide-gen` の入力受け渡しを拡張

### 🔧 Improvements / 改善

- Split `:root` into palette and design blocks / `:root` を配色用と意匠用の 2 ブロックに分け、プリセットの差し替えが互いを壊さないようにした
- Ban decoration-only expression / 情報を 1 つも足さないのに資料を安く見せる装飾を禁止し、機械検査でガードするようにした。例外は画像の上に文字を載せるための減光と破線などのパターンのみ
- Require meaning for emphasis / 意味のない強調を禁止。`.accent` は既定で使わず、付ける理由を presenter note に書けないなら外す。カードの色は区切りの構造であって情報ではないため、カードごとに色を変えない
- Define logo placement / ロゴの置き場所を表紙・フッター・締めの 3 つに定め、dark 背景では白抜き版が要る点を手順に含めた。レビュー観点にも「dark 背景でロゴが沈む」「扱いが不統一 / 主張しすぎ」を追加
- Align `slide-gen` visual checklist with `slide-review` / `slide-gen` の目視チェックリストを強調・装飾の方針に揃えた

### 🏗️ Infrastructure / インフラ

- Make `slide-gen` build web-only / `build` は Cloudflare Workers で配信する静的サイトだけを作るようにし、PDF / PNG 出力を Makefile のターゲットへ分離。Chromium に依存しなくなり Workers Builds でそのまま通る
- Add `make contrast` / コントラスト実測を Makefile のターゲットとして追加

## [v0.6.0] - 2026-08-22

自律実行フロー（`issue-sweep` → `impl` → `refine-git`）の収束性とスループットの作り直しを中心にしたリリース。あわせて `refine` の差分版分離、`spec-audit-git` / `mock-drift` の追加、herdr の導入、install/update スクリプトのツール単位分割を含む。

### ⚠️ Breaking Changes / 破壊的変更

- Split `refine` into `refine` (whole repo) and `refine-git` (diff only) / `refine` を「リポジトリ全体対象」と「PR 差分対象」に分割。`impl` / `impl-wt` / `issue-sweep` が作った PR の研磨は `refine-git` の担当になり、`refine` を機能 PR に使うとスコープが膨張して閾値に到達しなくなる
- Rename `impl-type-r` / `impl-type-wr` to `impl-r` / `impl-wt-r` / `impl-type-r` / `impl-type-wr` を `impl-r` / `impl-wt-r` に改名。旧名では起動できない
- Require explicit `--no-pr` for PR-less sub-skill runs / `impl` / `bug-fix` / `design-fix` の PR 作成スキップを「呼び出し元が明示指示すれば可」という運用から `--no-pr` フラグ必須に変更
- Unify `refine` status vocabulary / `refine` 系の終了 status を `clean` / `iter_limit` / `no_progress` / `agent_failed` / `merge_failed` / `ci_gave_up` の enum に統一（`stuck` 等の独自文字列を廃止）。status を parse する呼び出し元に影響する
- Drop `evidence` from `.sweep/state.json` and `issue` from metrics / `.sweep/state.json` の `evidence` 配列と null 固定だった `last_counts`、`metrics.jsonl` の後方互換 `issue` フィールドを廃止（`issues[0]` で代替）

### ✨ New Features / 新機能

- Add `--auto` autonomous mode to `impl` / `bug-fix` / `design-fix` / 自律実行モード `--auto` を追加。assignee 確認・不足情報のヒアリング・不確定仕様の確認・破壊的変更の確認で停止せず、採用した前提を PR 本文に列挙して進む。Review フェーズは後段の `refine-git` に委ねる（テスト・Format & Lint・Commit・回帰テスト・デザイン検証の省略は禁止のまま）
- Add `--skip-minor` to `refine-git` / minor 指摘を閾値判定と修正対象から外すフラグを追加。`issue-sweep` からの呼び出しは常にこれを渡す
- Add `--max-inflight` to `issue-sweep` / 同時に抱える未マージ PR 数の上限を `--parallel`（実装同時数）から分離
- Add batch implementation to `issue-sweep` / 関連 Issue を 1 worktree / 1 ブランチ / 1 PR にまとめて実装するバッチモードを追加
- Add `spec-audit-git` skill / 差分スコープで仕様乖離・TODO・スキップテストを検知する `spec-audit-git` を追加
- Add `mock-drift` skill / モックと実装の乖離をコンポーネント単位でチェックする `mock-drift` を追加
- Add herdr integration / herdr をインストール対象に追加し、tmux 準拠キーバインドと Claude Code 連携フックを導入
- Add copilot fish completions / GitHub Copilot CLI の fish 補完を追加
- Add `f` / `fc` fish aliases / fugu 起動・再開用の `f` / `fc` エイリアスを追加
- Assign self on start in `impl` / `bug-fix` / 着手時に Issue の assignee へ自分を追加する挙動を追加
- Add `unzip` / `jq` to `install_packages` / インストール対象パッケージに `unzip` と `jq` を追加

### 🐛 Bug Fixes / バグ修正

- Fix non-converging refine loop caused by doc/spec findings / `doc-drift-git` / `spec-audit-git` の指摘は本質的に差分外のドキュメント修正を要求するのに、fix agent が差分内ファイルしか編集できず `out_of_scope_required` で必ず失敗していた問題を修正。`docs/**` / `*.md` / 仕様書は差分外でも編集可にし、修正に差分外の非ドキュメントファイルが必要な指摘は `out_of_scope` に分類する
- Fix unbounded improvement loop in `impl` / `impl` の改善サイクルが「指摘なしまで繰り返す」で上限なしだった問題を修正（上限 3 周、残指摘は PR 本文の「## 残課題」に列挙）
- Fix unreachable CI failure handling in `issue-sweep` / bash の `while` ループ内から `Agent` ツールを呼ぶ実行不能な擬似コードになっており、CI 失敗を検知しても何も起きずに待機が続く問題を修正。状態取得（bash）と判定・agent 再起動（LLM）を分離
- Fix `.sweep/` splitting between worktree and main repo / `.sweep/` を `CLAUDE_PROJECT_DIR` 固定にし、worktree 削除で `refine-metrics.jsonl` と `spinoff-draft.jsonl` が消えていた問題を修正
- Fix `refine-git` silently terminating the caller's sweep / `refine-git` が `issue-sweep` と同じ `state.json` を上書きして `phase=terminal` にし、Stop Hook のブロックが解除されて sweep がキュー途中で終わる経路を所有権ガードで封じた
- Fix Atomic Design guard aborting entire sweeps / フロントエンドで Atomic Design 構造が検出できないと `refine-git` が起動直後に `exit 2` し、全 Issue のマージゲートが落ちていた問題を修正（sweep 経由では警告に降格）
- Fix infinite batch retry across sessions / バッチの試行回数がメモリ上のみで、セッションを張り直すと同じバッチを無限に再試行していた問題を `attempts.json` への永続化で修正（上限 2 回）
- Fix sweep unable to terminate after giving up / 諦めたバッチ / PR をキューに残していたため Stop Hook が停止をブロックし続ける問題を修正。失敗打ち切り時も terminal 化とレポート生成を行う
- Fix `agent-skills` install aborting mid-run / `install_agent_skills` の中断を修正し、MCP 登録の失敗理由を表示するようにした
- Fix Node LTS install ordering / Node LTS のインストールを node 製 CLI より前に移動
- Fix tmux clipboard handling / tmux のクリップボードを OSC 52 送出に一本化（passthrough 有効化を含む）
- Fix `set_default_shell` reliability / `chsh` の反映検証と sudo フォールバックを追加
- Fix Stop hook path resolution / Stop hook のパスを `$HOME` 側に切り替え、未セットアップのプロジェクトでの not found を解消
- Fix `refine-sweep` engineer prompt / merge + Issue close を明示的に指示するよう修正
- Fix herdr split keybindings / herdr の split バインドを tmux 既定の `"` / `%` に統一
- Fix fugu resume alias / fugu 再開エイリアスを修正
- Fix nvim checkhealth warnings / nvim の checkhealth warning を整理
- Fix invalid permission rule / 無効な `Write(.sweep/**)` 許可ルールを削除
- Fix shellcheck warnings / shellcheck の warning 指摘を解消

### 🔧 Improvements / 改善

- Rebuild `issue-sweep` phase 2 as an in-flight pipeline / 「実装 N 件 → 全 PR の CI 待ち → また N 件」というバリアを撤去し、スロットが空いた瞬間に次のバッチを起動する方式に変更。CI 時間が実装 agent 0 本の空白にならない
- Cut review iterations in `refine-git` / 2 周目以降は前回 critical/major を出した観点のみ再走、`doc-drift-git` / `spec-audit-git` はドキュメントを触った反復のみ、`--no-merge` 時の最終 re-review を廃止。`issue-sweep` からは `--max-iter 2` を渡す。1 PR あたりのレビュー agent 起動数が最悪ケースで約 45〜65 本から約 6〜9 本になる
- Collapse duplicate Issue body reads in `issue-sweep` / 依存判定・分割判定・スコープ読み取りで Issue 本文を 3 回読んでいたのを「1 Issue = 1 agent = 1 パス」の解析に統合
- Remove `gh` N+1 calls / 親 Issue 展開を 1 コールに、PR の冪等性チェックと状態判定を 1 回の PR 一覧取得に統合。ラウンドあたりの `gh` 呼び出しが in-flight 本数に比例しなくなった
- Unify batch scope calculation / 「disjoint なら並列」と「重なるならバッチ」の逆向きの二重判定をやめ、バッチ編成 1 箇所に統合（同じバッチ = 直列、別のバッチ = 並列）
- Unify `issue-sweep` launch prompt / 1 件用とバッチ用に分裂していた起動プロンプトを 1 本に統合し、worktree は常に sweep 側が作る形にした（worktree の before/after スナップショット差分が不要になった）
- Lighten `Plan` for scoped Issues / `--auto` 時、Issue 本文にスコープ記載があれば `Plan` エージェントを起動せずその記載を実装計画として使う。仕様書探索も worktree ごと 1 回に
- Cap `issue-split-auto` fan-out / Issue 数ぶん同時起動していた分割判定を 5 件ずつのウェーブに制限
- Redesign `refine-sweep` around Issue-driven `impl-wt` / `refine-sweep` を Issue 化 → `impl-wt` で消化するフローに再設計
- Consolidate spinoff issue creation / スコープ外発見の起票をフェーズ3 の `--batch` 1 回に集約し、`issue-sweep` の spinoff 追跡既定を 1 周に絞った
- Change `issue-sweep` split judgment to content-based / 文字数や H2 数のような表層メトリクスによる事前フィルタをやめ、本文と関連仕様書を読んで判定する形に変更
- Remove external taste-skill and trim `issue-sweep` / 外部 taste-skill を除去し `issue-sweep` の冗長な記述を削減
- Split install/update scripts per tool / install / update スクリプトをツール単位に分割し、common ヘルパーも責務単位に分割
- Improve dotfiles update flow / dotfiles 更新処理を改善
- Track copilot CLI options / copilot の fish 補完を最新の CLI オプションに追随
- Revert verbose MCP registration logging / MCP 登録失敗時の詳細ログを削除

### 📝 Documentation / ドキュメント

- Add MIT LICENSE and CONTRIBUTING.md / MIT LICENSE と CONTRIBUTING.md を追加
- Add PR / Issue templates / PR / Issue テンプレートを追加
- Add license and contribution links to README / README にライセンスとコントリビューションの導線を追加

### 🏗️ Infrastructure / インフラ

- Add PR syntax checks / PR 向けに shellcheck / fish / JSON の構文チェックを追加
- Bump `actions/checkout` to v5 / `actions/checkout` を v5 に更新
- Ignore runtime artifacts / ランタイム生成物と marketplace 導入 skill を gitignore に追加

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
