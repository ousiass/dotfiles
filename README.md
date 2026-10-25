# dotfiles

Ubuntu / macOS 両対応の個人用設定ファイル群。複数マシン間で同期する。

## 構成

```
~/dotfiles/
├── install.sh          # セットアップスクリプト（idempotent）
├── reset-tools.sh      # 言語ツール/AI CLI を一括リセットするスクリプト
├── cleanup.sh          # キャッシュ類を掃除するスクリプト（make clean から呼ばれる）
├── runner-host-setup.sh # GitHub Actions self-hosted runner ホストのセットアップ（make runner-setup から呼ばれる）
├── runner-bootstrap.sh # runner 本体の取得（チェックサム確認）と登録（setup が source する関数群）
├── runner-tools-install.sh # runner のジョブが使うツール（macOS は brew で colima/docker/fnm/gh/jq など）の足りないものだけ入れる（make runner-tools。macOS は runner-setup から呼ばれる）
├── runner-path-guard.sh # runner の .path を検査・修復するガード（安定 PATH の定義もここ。setup が source し、起動時にも実行される）
├── .env.example        # .env のテンプレート
├── .env                # 実体（gitignore 済、~/.env はこれへのシンボリックリンク）
├── claude-mcp/        
│   └── mcp.json        # Claude Code MCP 設定（${VAR} で env 参照、~/.mcp.json はこれへのシンボリックリンク）
├── .claude/            # → ~/.claude（CLAUDE.md, agents/, skills/, settings.json 等）
│                       # skills/ は ~/.cursor/skills/<name> にも symlink され Cursor CLI/IDE と共用
├── .cursor/
│   ├── agents/         # → ~/.cursor/agents（model: inherit。Claude 側は .claude/agents の opus）
│   └── rules/          # → ~/.cursor/rules（サブエージェントは親モデル継承）
├── .codex/
│   ├── AGENTS.md       # → ~/.codex/AGENTS.md（Codex グローバル指示、言語設定等）
│   └── skills/         # 各サブディレクトリが ~/.codex/skills/<name> に symlink される Codex 用 skill 群
├── nvim/               # → ~/.config/nvim
├── tmux/               # → ~/.config/tmux
├── gh-dash/            # → ~/.config/gh-dash (GitHub Dashboard CLI)
├── herdr/              # → ~/.config/herdr (エージェント向けターミナルマルチプレクサ、tmux 準拠 keybinding)
├── systemd/            # → ~/.config/systemd/user（週次の自動掃除 timer / service）
├── tests/              # cleanup.sh / runner-path-guard.sh / runner-host-setup.sh / runner-tools-install.sh の回帰テストと、evals/ の dry 配線テスト（make test。macOS 標準の bash 3.2 と BSD コマンドでも動く書き方）
├── evals/              # エージェント構成変更のための e2e eval 基盤（#56 Phase 0。`evals/README.md`）。モデルを呼ばない dry モードで配線を確かめられる
└── fish/               # → ~/.config/fish
    ├── config.fish
    ├── fish_plugins
    ├── conf.d/
    │   └── secrets.fish    # ~/.env を読み込んで env 変数化する loader
    ├── completions/
    ├── functions/
    └── themes/
```

## 環境変数 (~/dotfiles/.env)

シェルにセットしたい環境変数は **secret / 非secret を問わず すべて `~/dotfiles/.env` に集約する**:

```bash
# ~/dotfiles/.env （gitignore 済み、~/.env はここへのシンボリックリンク）
GEMINI_API_KEY=xxxxx
OPENAI_API_KEY=xxxxx
SAKANA_API_KEY=xxxxx   # 未設定なら install.sh の Fugu インストールはスキップされる
SUPABASE_ACCESS_TOKEN=xxxxx
TYPESAFE_API_KEY=xxxxx # 未設定なら omp の omp-jev-compaction プラグインはスキップ（従来どおり圧縮なしで動作）
OMP_JEV_PROVIDER=typesafe

# 非secret も同様にここに
EDITOR=nvim
SOME_TOOL_HOME=/opt/some-tool
```

- fish 起動時に `conf.d/secrets.fish` が `~/.env`（→ `~/dotfiles/.env`）を読み込んで `set -gx` する
- `claude-mcp/mcp.json` の `${SUPABASE_ACCESS_TOKEN}` 等の参照もこの env から解決される
- `config.fish` 等に env 変数を直書きせず、必ず `.env` 経由で設定する

## セットアップ（新規マシン）

```bash
git clone git@github.com:ousiass/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 1. .env を作成して API キー等を記入（install.sh の前に必須）
cp .env.example .env
$EDITOR .env

# 2. セットアップ実行
./install.sh
```

`install.sh` は以下を行う:

1. OS 検出（Ubuntu / macOS）
2. `~/dotfiles/.env` の存在チェック（無ければエラーで停止）
3. macOS の場合 Homebrew を未導入ならインストール
4. システムパッケージを `apt` または `brew` で
   - 共通: fish, tmux, neovim（Linux ではフォールバック）, git, curl, rsync, jq
   - Linux のみ: xclip, unzip（unzip は macOS 標準搭載のため brew には含めない）
5. Neovim を最新安定版へ
   - Linux: GitHub Releases の公式 tarball を `/opt/nvim` に展開し、`/usr/local/bin/nvim` から参照
   - macOS: Homebrew の `neovim` formula
6. 言語ツールを公式インストーラで（未導入のもののみ）:
   - **uv** (Python パッケージマネージャ)
   - **bun** (JavaScript runtime/manager)
   - **rustup** (Rust toolchain manager)
   - **fnm** (Fast Node Manager, Rust 製の nvm 代替)
   - **Go** (Linux: 公式 tarball を `/usr/local/go` へ / macOS: brew)
7. AI CLI ツール（未導入のもののみ）:
   - **Claude Code** (公式 curl インストーラ)
   - **OpenAI Codex CLI** (`bun install -g @openai/codex`)
   - **Gemini CLI** (`bun install -g @google/gemini-cli`)
   - **Cursor CLI** (`cursor-agent`、公式 curl インストーラ)
     - `~/.local/share/cursor-agent/versions/<ver>/` に展開され `~/.local/bin/{cursor-agent,agent}` から参照される
     - 認証（`~/.cursor/` 配下の資格情報）は dotfiles 管理外。新マシンでは `cursor-agent login` を実行する
     - skills も互換で `~/.claude/skills/` が読まれるが、Cloud Agents の同期対象は `~/.cursor/skills/` のみのため、install 時に自作スキルと外部 agent-skills を `~/.cursor/skills/<name>` にも symlink する
     - サブエージェントは Claude Code 用 `.claude/agents/`（`model: opus`）と Cursor 用 `.cursor/agents/`（`model: inherit`）を分け、install で `~/.cursor/agents/` にリンクする。モデル方針は `harness-model` スキル
   - **Fugu** (Sakana AI の Codex 設定バンドル、公式 install スクリプト)
     - `~/.env` から `SAKANA_API_KEY` を拾えれば非対話でインストール、無ければ warn してスキップ
     - `~/.codex/skills/.system/` を経由して `codex-fugu` ランチャと設定バンドルを配置
   - **herdr** (エージェント向けターミナルマルチプレクサ、公式 curl インストーラ)
     - `~/dotfiles/herdr/config.toml` を `~/.config/herdr/config.toml` に symlink し、prefix を `ctrl+s` 等 tmux と統一
   - **omp** (oh-my-pi、LSP/DAP を内蔵したコーディングエージェント CLI、公式 curl インストーラに `--binary`)
     - prebuilt バイナリを `~/.local/bin/omp` に配置（約 248MB）
     - bun -g 経由は避ける: keytar / onnxruntime-node の postinstall が bun にブロックされ、
       Apple Silicon で Rosetta 版 bun があると x86_64 バイナリが生成される（起動が遅く AVX 警告）
     - インストーラは再実行で最新版に入れ替わるため、update も同じ経路を使う
     - fish 補完は `fish/completions/omp.fish`（`omp completions fish` の生成物）
     - 設定は `~/dotfiles/omp/config.yml` → `~/.omp/agent/config.yml` に symlink（`link_omp`）。
     - 各設定の意図は `omp/README.md` に置く（omp は設定書き込み時に config.yml を再シリアライズしコメントを落とすため）
     - 常時適用のルールは `.claude/CLAUDE.md` → `~/.omp/agent/RULES.md`。omp は user レベルの
       `~/.claude/CLAUDE.md` を読まないため入り口だけ別に要るが、実体は 1 ファイルに統合している
       同じディレクトリの `agent.db`（セッション・認証）はマシン依存なので管理外
     - 既定から変えているのは 5 つ: `symbolPreset`（unicode → nerd）/ `task.showResolvedModelBadge`（解決モデルの可視化）/ `task.enableLsp`（サブエージェントでも LSP）/ `task.softRequestBudget`（200 → 400。sweep 系長寿命サブエージェントの予算切れ対策）/
       `skills.enableClaudeUser`（false → true。omp は `~/.claude/skills` を既定で読まないため、自作スキルを有効化）
     - `tools.approvalMode` は既定の `yolo` のまま。`write` にすると `bash` のたびに確認が入り、常用にも sweep にも耐えない
     - MCP は `~/.omp/agent/mcp.json` → `~/dotfiles/claude-mcp/mcp.json` に symlink し、Claude / Codex と定義を共有する。
       omp は `~/.mcp.json`（ホーム直下）を探索しないため明示的なリンクが要る（`~/.claude.json` は自動で継承される）
     - `~/.agents/skills` の外部 agent-skills と `CLAUDE.md` / `AGENTS.md` 等のルールは設定なしで読まれる
     - サブエージェントは `omp/agents/`（develop / review）→ `~/.omp/agent/agents/`。
       omp は `.claude/agents` を意図的にスキップする（frontmatter 契約が別物）ため専用の実体を置く。
       モデルは定義側に書かず `modelRoles` の `@task` / `@slow` で解決する
     - スキルは `omp/skills/`（sweep / impl 系と、そこから呼ばれるレビュー・生成系 26 個）→ `~/.omp/agent/skills/`。
       `sweep-common` は `SKILL.md` を持たない共有リファレンスでスキルとしては登録されないが、
       各スキルから `../sweep-common/<file>` の相対パスで参照されるため同じ階層に置く
       omp の native provider (priority 100) が claude provider (80) より優先されるため同名を上書きし、
       未移植のスキルは `~/.claude/skills` 版にフォールバックする
     - omp 版への書き換え規則: `Agent(subagent_type=X, model=Y)` → `task(agent=X)`（モデルは書かない）、
       `AskUserQuestion` → `ask`、`TaskCreate` → `todo`、ハーネス分岐（`harness-model` 参照）は削除
     - 未移植スキルを omp で呼ぶと Claude Code 前提の記述が残っている点に注意（`.codex/skills` と同じ二重管理）
     - モデルは認証済みプロバイダのみ選べる（未認証は `omp models` に出ない）ため `modelRoles` は未設定のまま。
       Anthropic / OpenAI Codex / Cursor / Copilot は `oauth` = サブスクのままサインインできる。
       `omp` 内で `/login` するか `omp setup` を回し、`omp models` で ID を確認してから `modelRoles` に書く
     - **プラグイン（TypeSafe Jev context compaction）**: `install_omp_jev`（`lib/tools/omp_jev.sh`）が
       `install.sh` に組み込み済み。`TYPESAFE_API_KEY` が `~/.env` に無ければ Fugu と同じく warn してスキップする。
       ある場合は `~/.local/share/omp-plugins/omp-jev-compaction` に clone → `npm install`（`prepare` が
       ビルド）→ `omp plugin install <path>` まで自動実行する（公式の `omp plugin install jerryfane/omp-jev-compaction`
       はこの omp バージョンでは `dist/` 未ビルドのため失敗するため自前でビルドする）。プラグイン登録は
       `~/.omp/plugins/`（machine-local）に書かれ、`omp/config.yml` は変更しない。詳細は `omp/README.md` 参照
8. 各ツールのバイナリパスを `fish/conf.d/paths.fish` と `shell/paths.sh` で追加
9. 既存の `~/.config/{nvim,tmux,fish,gh-dash}`, `~/.claude`, `~/.mcp.json`, `~/.env` を `*.bak.<日付>` にバックアップ
10. dotfiles を該当パスにシンボリックリンク（`~/.env` → `~/dotfiles/.env`、`~/.mcp.json` → `~/dotfiles/claude-mcp/mcp.json`、`~/dotfiles/.codex/AGENTS.md` → `~/.codex/AGENTS.md`、`~/dotfiles/.codex/skills/<name>` → `~/.codex/skills/<name>`、`~/dotfiles/.claude/skills/<name>` → `~/.cursor/skills/<name>` 等）
11. `~/.claude` のランタイムデータ（履歴・セッション等）をバックアップから dotfiles 側に移行（既存は上書きしない）
12. `~/dotfiles/claude-mcp/mcp.json` の MCP サーバー定義を `codex mcp add` で `~/.codex/config.toml` に同期（Claude と Codex で同じ MCP を共有。`${VAR}` 形式の env は Codex の親プロセス env 継承に任せる）
13. fisher（fish プラグインマネージャ）をインストール → `fish_plugins` の内容を反映
14. fnm 経由で Node.js LTS をインストールしデフォルトに設定
15. nvim プラグインを headless で同期（`lazy.nvim`）
16. ログインシェルを fish に変更（必要時のみ）

何度実行しても安全（既にインストール済 / リンク済みならスキップ）。

## 個別ツールの再インストール

特定のツールだけ入れ直したい場合は `install.sh` に `install_<name>` の `<name>` 部分を渡す:

```bash
./install.sh fugu            # = make fugu。Fugu pin に合わせて Codex / codex-fugu を自動整合
./install.sh codex_fugu      # fugu と同じ alias
./install.sh codex           # codex_cli と同じ alias。Fugu pin があれば自動整合
./install.sh codex_cli
./install.sh cursor          # cursor_cli と同じ alias
./install.sh fugu gemini_cli # 複数指定可
./install.sh omp_jev         # omp-jev-compaction プラグインだけ再同期（TYPESAFE_API_KEY 必須）
```

未定義の名前を渡すとエラー終了する（誤入力を握りつぶさない）。

個別 update も同じ名前で指定できる:

```bash
./update.sh codex_fugu   # Fugu pin に合わせて Codex / codex-fugu を自動整合
./update.sh codex        # Fugu pin があれば単独 update ではなく自動整合
```

## Fish エイリアス（AI CLI 一発起動）

`fish/config.fish` に登録済み。AI CLI はワンコマンドで起動でき、Claude Code / Codex 系は Permission / sandbox バイパスも付ける（`o` / `h` は対象外 — 前者は `config.yml` の `approvalMode: yolo` 既定、後者はそもそも承認プロンプトの無いツール）:

| エイリアス | 展開 |
|---|---|
| `c` | `claude --dangerously-skip-permissions` |
| `cc` | `claude --dangerously-skip-permissions --continue` |
| `cs` | `claude --dangerously-skip-permissions --settings ...sandbox=true...` |
| `x` | `codex --dangerously-bypass-approvals-and-sandbox` |
| `fugu` / `f` | `codex-fugu --dangerously-bypass-approvals-and-sandbox` |
| `fc` | `codex-fugu --dangerously-bypass-approvals-and-sandbox resume --last` |
| `cu` | `cursor-agent -f` |
| `o` | `omp`（`tools.approvalMode: yolo` が既定なのでバイパスフラグ不要） |
| `h` | `herdr` |

`codex-fugu` は内部で `codex -p fugu "$@"` を `exec` するので、`fugu` でも codex 本体の bypass フラグがそのまま効く。`fc` は Codex CLI の `resume --last` で直近セッションを再開する。

Fugu は対応済みの Codex version を config bundle 側で pin する。状態は以下で確認する:

```bash
codex-fugu --status
```

Fugu 使用中に Codex 本体だけ `codex update` で上げると、Fugu の `deployed_target` とずれて warning / rollback 対象になる。そのため `install.sh` / `update.sh` では、Fugu pin が見つかった場合に Fugu installer 経由で自動的に整合させる。

## 更新

設定ファイルだけを更新する場合:

```bash
cd ~/dotfiles
git pull
# シンボリックリンク経由で即反映
```

インストール済みツールも含めて更新する場合:

```bash
cd ~/dotfiles
./update.sh
# または make update
```

`update.sh` は Neovim / uv / bun / rustup / fnm / Go / Node LTS / AI CLI / cloud CLI / fish plugins / nvim plugins を更新する。
ただし Fugu を使っている場合、Fugu config bundle が対応 Codex version を pin しているため、Codex 本体の単独 update は行わず、Fugu installer を `--yes --force` で呼び出して plain `codex` と `codex-fugu` の両方が同じ pin version を使うよう自動整合する。
Codex / Claude Code / Cursor CLI の実行セッション中は、自分自身を壊さないように該当 CLI の self-update をスキップする（Cursor CLI は shell ツール実行時に `CURSOR_AGENT=1` が入るのでこれで判定する）。
Cursor CLI は `cursor-agent update` が無言で失敗するケース（長期間更新していないバイナリ）があるため、失敗時は公式インストーラでの再取得にフォールバックする。

## 各ツールをリセット（テスト/壊れた時用）

`reset-tools.sh` で言語ツール・AI CLI 一式を削除して install.sh で再インストール:

```bash
bash ~/dotfiles/reset-tools.sh
```

- `CLAUDECODE=1` / `CODEX_THREAD_ID` / `CURSOR_AGENT` を検出して各エージェントのセッション中は自動的に拒否
- 削除対象: uv / bun (codex/gemini 含む) / Codex CLI standalone package / rustup / fnm + Node / Go / Claude Code / Cursor CLI
- 削除しないもの: fish/tmux/neovim/git, ~/.env, ~/.claude のデータ, ~/.cursor のデータ, シンボリックリンク

## ディスク掃除

開発ツールのキャッシュは放置すると数百GB規模まで育ち、ディスク I/O を圧迫して端末全体が重くなる。
`cleanup.sh` は「消しても再生成されるもの」だけを掃除する。成果物や永続データには触らない。

```bash
cd ~/dotfiles
make diag          # 現状を表示するだけ（何も消さない）
make clean         # ユーザー権限でできる掃除
make clean-system  # sudo が要る掃除（journal / snap / fstrim）
make clean-timer   # 週次の自動掃除を systemd timer に登録（sudo 不要、初回だけ）
```

個別に実行する場合は `./cleanup.sh go docker` のようにターゲットを並べる。

### 掃除の対象

| ターゲット | 内容 |
| --- | --- |
| `go` | go-build キャッシュ。サイズが閾値を超えたときだけ全消し |
| `uv` / `pip` / `goimports` | 各パッケージ・ツールのキャッシュ |
| `docker` | 未使用イメージとビルドキャッシュ。**volume は残す** |
| `claude` | Claude Code の subagents ログのうち古いものを退避。会話履歴 (`*.jsonl`) には触らない |
| `fish` | 終了済みセッションが残した `_tide_prompt_` と `fish_variables` の残骸 |

go-build を毎回消すと次のビルドが常にやり直しになるため、閾値を超えたときだけ全消しする。
docker の volume は DB などの永続データが入るので対象外にしている（消すときは `docker volume prune` を手で実行する）。
fish の掃除が要るのは、tide が非同期プロンプト用に作る `_tide_prompt_<PID>` が、tmux や SSH の切断で fish が強制終了されると消えずに残るため。fish のユニバーサル変数は単一ファイルで、1つ書き換えるたびに全体を書き直すので、溜まると打鍵のたびに数百 KB の I/O が走って端末が重くなる。

### 定期実行

`make clean-timer` で systemd の user timer に登録すると、毎週日曜 4:00 に `cleanup.sh` が走る。
sudo は要らず、ログイン中でなくても動く（`loginctl enable-linger` 済みの場合）。

```bash
make clean-timer                                   # 登録（初回だけ）
systemctl --user list-timers dotfiles-cleanup.timer  # 次回実行の確認
journalctl --user -u dotfiles-cleanup.service       # 実行結果の確認
systemctl --user disable --now dotfiles-cleanup.timer # やめる
```

掃除が他の作業を邪魔しないよう、service 側で `Nice=10` と `IOSchedulingClass=idle` を指定している。
マシンが止まっていて実行を逃した分は `Persistent=true` により次の起動後に追いつく。
閾値は service の `Environment=` で上書きする（既定では go-build を 300GB に設定している）。

### 環境変数

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `GO_CACHE_LIMIT_GB` | `30` | go-build がこのサイズ (GB) を超えたときだけ全消しする |
| `CLAUDE_ARCHIVE_DAYS` | `7` | subagents ログをこの日数より古ければ退避する |
| `ARCHIVE_DIR` | HDD 上の `claude-subagents-archive` | subagents ログの退避先。親ディレクトリが無ければ退避をスキップする |
| `GO_TMP_AGE_DAYS` | `1` | `$TMPDIR` に残った go-build の残骸をこの日数を過ぎたら消す |

### 運用の目安

- 端末が重いと感じたらまず `make diag`。`io` の `some` が数十 % なら I/O が詰まっている
- ルート使用率が 70% を超えると SSD の書き込み性能が落ちやすいので `make clean` で空きを作る
- `fstrim` は手動で回さなくてよい。OS 標準の `fstrim.timer`（root 権限のシステムタイマー）が週次で流している。`systemctl list-timers fstrim.timer` で前回・次回の実行時刻を確認できる
- fstrim の対象は `/etc/fstab` と現在のマウント情報から決まる。ドライブを増やしたら fstab に書いておけば自動で対象に入る（NVMe を足した直後の実行は fstab 追記より前だったため、その回だけ対象外になっていた）
- `make clean-system` は journal と snap を縮める。こちらは自動化していないので月 1 回ほど回す。同梱の fstrim は「今すぐ通知したい」ときの手段で、通常は週次タイマーに任せてよい
- `go` はコンパイル中の一時ファイルを `$TMPDIR/go-build*` に置く。GOCACHE とは別物で、ビルドが kill されると消えずに残る（実際に 42 個 4.8GB 溜まっていた）。`make clean` が 1 日以上放置されたものだけを消す
- キャッシュを別ドライブへ逃がしている場合、`~/.cache/go-build` などがシンボリックリンクになる。`du` と `find` は既定で引数のリンクを辿らないため `du -D` / `find -H` を使っている（`make test` が回帰を見張る）

## GitHub Actions self-hosted runner

self-hosted runner を動かすホストで、ジョブ実行の前提（パスワード不要 sudo / Docker / Buildx / C コンパイラ。Linux はさらに docker グループ）を整えて runner をサービスとして起動する。対象は Linux + systemd の apt 系ディストリビューションと、Apple Silicon の macOS（launchd / colima。[後述](#macosapple-silicon)）。以下の説明は Linux（systemd）を基準にしている。

runner 本体がまだ無いホストでも、gh の認証さえ済んでいれば、`make runner-setup` 1 回で、本体の取得・登録（`config.sh` を手で打たない）・サービス登録まで済む。gh が入っていない新しいホスト（新品の Mac など）は、先に次の 2 手を踏む。

```bash
make runner-tools            # runner ユーザーで（sudo 不要）。gh などを入れる（Linux は apt で jq / shellcheck / fish なども入り、sudo が要る）
gh auth login -s admin:org   # runner ユーザーで 1 回だけ（org の runner を登録できる権限。トークンは gh が持つ）
make runner-setup
```

- **取得**: `RUNNER_DIR`（既定 `~/actions-runner`）に `config.sh` が無ければ、GitHub の最新の `actions/runner` リリースを OS と CPU に合わせて落とす（macOS は `osx-arm64`、Linux は `linux-x64` / `linux-arm64`。それ以外の CPU は対象外として止まる。ダウンロードは https のみ・TLS 1.2 以上）。リリースが資産ごとに持つ sha256 の digest と照合し、一致しなければ展開しない（digest が無いリリースも入れない）。展開は作業ディレクトリで検証してから `RUNNER_DIR` へ移し、`config.sh` は最後に置く（在る = 展開が完了している）。展開を始めると `.runner-extracting` を置き、`config.sh` の後に消す。展開先に今回の展開物と無関係なもの（展開物と同名でも、マーカーが無ければ）があれば、何も消さず止まる（`RUNNER_DIR` の指定ミスで他のディレクトリを壊さない）。マーカーが残っていれば前回の途中で止まった残りなので、展開物と同名のものは入れ子にならないよう置き換える。ディレクトリは親が在るときだけ新しく作り、そのときだけ所有者を runner ユーザーにする（既存のディレクトリは書き込めるかだけ確かめる）。Linux は `bin/installdependencies.sh`（apt。root）を、未登録のあいだ毎回流す（冪等。前回 apt が失敗して止まっても、再実行で入る）。
- **登録**: `.runner` が無ければ `config.sh --unattended` で登録する。登録トークンは `gh api -X POST orgs/<org>/actions/runners/registration-token` でその場で発行し、`config.sh` の環境変数 `ACTIONS_RUNNER_INPUT_TOKEN` にだけ渡す（`--token` 引数・ファイル・ログに出ず、`ps` の引数にも出ない。`GH_DEBUG` / `DEBUG` は gh に渡さない）。**限界**: 環境変数は `config.sh` が終わるまで、同じユーザーと root からは読める（`/proc/<pid>/environ` や `ps eww`）。トークンは 1 時間で失効し、登録 1 回にしか使えない。org・名前・group は変数で指定する（下記）。**`--replace` は既定で付けない**: `RUNNER_DIR` の指定ミスや 2 台目の登録で、稼働中の既存 runner を黙って追い出さないため。同名の runner が org に既にあると `config.sh` が失敗するので、別の `RUNNER_NAME` を指定するか、置き換えてよいなら `RUNNER_REPLACE=1` を付けて再実行する（失敗時にこの案内を出す）。登録済み（`.runner` がある）ときは、取得も登録も、入力の検証も飛ばして従来どおり進む。`RUNNER_DIR` は絶対パスで指定する（取得・登録は runner ユーザーが `/` を cwd にして実行するため）。
- **ラベル**: 既定ラベルは使わず（`--no-default-labels`）、OS と CPU から付ける。macOS は `self-hosted, macOS, ARM64`、Linux は `self-hosted, linux, x64`（arm64 の Linux は `linux, arm64`）。
- **権限**: ディレクトリの作成・`chown`・Linux の依存パッケージ・サービス化（Linux の `svc.sh`）は root（sudo）。取得・展開・`gh`・`config.sh` は runner ユーザーで実行する（`config.sh` は root を拒否し、`gh` の認証も runner ユーザーのもの）。macOS の `svc.sh` は従来どおり runner ユーザー。
- **前提**: runner ユーザーの `gh` が org の runner を登録できる権限（`admin:org`）で認証済みであること。足りなければ、Linux は sudoers・apt を触る前に、macOS は 2/5（brew でツールを入れた直後。colima を起動して待つ前）に、入れ方・ログイン方法を案内して止まる。`gh` が PATH に無い場所にあるときは `RUNNER_GH_BIN=/path/to/gh` で指す（`sudo bash runner-host-setup.sh` で直接実行するとき）。なお `gh auth status` は scope まで見ないので、scope 不足は登録時（403）まで分からない。

runner のユーザー・ディレクトリ・登録先は変数で上書きできる。既定は sudo を呼び出したユーザーと、そのホーム配下の `actions-runner`、org `ousiassllc`、runner 名はホスト名（`hostname -s`）、runner group は `Default`。

```bash
make runner-setup RUNNER_USER=ci-runner RUNNER_DIR=/opt/runners/foo
make runner-setup RUNNER_ORG=my-org RUNNER_NAME=my-mac RUNNER_GROUP=Default
make runner-setup RUNNER_REPLACE=1   # 同名の runner が org にあるとき、置き換えて登録する（既定は置き換えない）
```

何度実行しても同じ結果になる（idempotent）。登録済みなら何も取得・登録しない。runner 名の既定はホスト名で、macOS は DHCP などで変わることがあるので、固定したいなら `RUNNER_NAME` を指定する。runner group の対象リポジトリはスクリプトからは検証できないため、実行後の案内に従って手動で確認する（ラベルは自動で付く）。とくに `NOPASSWD: ALL` を入れる以上、runner group を「選択したリポジトリ」に限定し public リポジトリへ提供しないことが、fork PR 経由で第三者のコードがこのホストで走るのを防ぐ唯一の層になる。

ジョブの shell は非ログイン・最小環境で起動し、fish の `fnm env` も `shell/paths.sh` も読まれないため、そのままだと fnm の `node` / `npx` が見えず `node: コマンドが見つかりません`（exit 127）で落ちる。さらに runner の systemd サービス（`runsvc.sh`）は、起動時に `<runner dir>/.path` があれば `PATH` を丸ごとそれで上書きする。**`.env` の `PATH=` より後に効くので、`.path` が PATH の正になる。** `.path` は `config.sh` / `svc.sh install` を実行したシェルの PATH が一度だけ書かれ、fish のログイン中に実行すると fnm の一時パス（`/run/user/<uid>/fnm_multishells/...`）が記録されて、再起動やログアウトで node が消える。

そこで `runner-host-setup.sh` は、一時パスを含めない安定 PATH（`<home>/.local/share/fnm/aliases/default/bin:/opt/nvim/bin:...`。定義は `runner-path-guard.sh` の `runner_stable_path` に 1 つだけ）を次の 2 か所へ書く。`aliases/default` は node の更新に追従する。

- `<runner dir>/.path`: 実効的に効く側。`fnm_multishells` を含む / `aliases/default/bin` を含まない / その PATH で `node` `npx` が引けない、のどれかに当たるときだけ安定 PATH へ書き直す（正常な `.path` は触らない。書き直す前に `.path.bak-<日時>` を残す）
- `<runner dir>/.env`: `PATH=` 行を置き換える（重複しない）。`.path` と二重化になるが害は少ない

`.path` / `.env` は runner の起動時にしか読まれないため、どちらかを変えたとき、稼働中の runner は、ジョブ（`Runner.Worker`）が走っていなければスクリプトが再起動し、走っていれば再起動を促すメッセージだけ出す。

**起動時の自動修復**: 上記の後でまた `.path` が外れても直るように、`runner-host-setup.sh` は `<runner dir>/path-guard.sh`（`runner-path-guard.sh` のコピー）を置き、systemd の drop-in `/etc/systemd/system/<unit>.d/path-guard.conf` の `ExecStartPre=` で runner の起動のたびに実行する。ガードは上の条件で `.path` を検査して、外れていれば書き直し、修復内容を journal に出す（`journalctl -u <unit> | grep path-guard`）。修復しても node が見つからない（fnm default 未設定など）ときはエラーを出すが、`ExecStartPre` は常に成功を返すので runner の起動は止めない。

「5/5 確認」では、稼働中の `Runner.Listener` の実 PATH（`/proc/<pid>/environ`）に `aliases/default/bin` が入っていてその PATH で `node` / `npx` が見えることと、Docker コンテナ内から名前解決できること（`docker run --rm alpine nslookup proxy.golang.org`）を確認する。`.env` だけを見ても `.path` による上書きは検知できないため、実プロセスを見る。後者が NG のときは、`docker build` 中のコンテナがホストの DNS に届いていない。自動修正はしない（`/etc/docker/daemon.json` の `"dns"` はホスト固有のため）。次の順で切り分ける。

```bash
nslookup proxy.golang.org                      # ホスト自体は引けるか
docker run --rm alpine cat /etc/resolv.conf    # コンテナが使う DNS サーバー
docker run --rm --network=host alpine nslookup proxy.golang.org  # bridge だけの問題か
```

ホストは引けるが bridge からだけ届かない場合は、`/etc/docker/daemon.json` に `{"dns": ["<引ける DNS サーバー>"]}` を書き、`sudo systemctl restart docker` する。ホスト自体が引けない場合は OS 側の DNS 設定を直す。

`runner-host-setup.sh` と `runner-path-guard.sh` は [ousiassllc/actions-runner-setup-base](https://github.com/ousiassllc/actions-runner-setup-base) から取り込んだコピー。詳細な背景（何が欠けるとどのエラーが出るか等）は上流の README を参照。上流を更新したらこれらのファイルも追従させる。macOS 対応（下記）と、runner 本体の取得・登録（`runner-bootstrap.sh`。上流に無いこのリポジトリ独自のファイルで、`runner-host-setup.sh` が source する）はこのコピー側で先に入れているので、上流へ取り込むときは差分に注意する。

### macOS（Apple Silicon）

同じ `make runner-setup` が macOS でも動く。`uname -s` で OS を見て Linux と macOS の処理を分けており、Linux のサービス化・PATH・docker の流れは変わらない（runner 本体の取得・登録は両 OS 共通で、冒頭の節のとおり）。対象は Apple Silicon（arm64）の Mac だけで、Intel の Mac では対象外であることを示して止まる（Rosetta 下の端末は `sysctl -n hw.optional.arm64` で見分ける）。Docker は colima を使い、Docker Desktop は対象外。

**前提（決まっている運用）**

- runner は 1 人のユーザー（例: `yuhta`）の **GUI ログインを開いたまま**動かす。runner は LaunchAgent（`~/Library/LaunchAgents/`）で、GUI ログイン中のセッションにしか登録できないため。`make runner-setup` は `stat -f %Su /dev/console` で、いまログインしているユーザーが runner ユーザーと同じかを確かめ、違う（別ユーザーがログイン中・ログイン画面のまま・SSH だけ）ときは「対象外」と表示して止まる。別ユーザーでの実行や、ログインしていないホストは対象外。
- **再起動後の自動ログインは、スクリプトでは設定しない。** 再起動のあとも runner を動かしたいなら、システム設定の「ユーザとグループ」で自動ログインを自分で設定する（FileVault が有効だと自動ログインは使えない）。
- colima の CPU・メモリ・ディスクは、スクリプトでは指定せず colima の既定値のまま（`brew services start colima` で起動する）。変えたいときは `colima start --edit` などで colima 側の設定を直す。

先に次の 2 つだけ済ませておく（Xcode CLT と Homebrew は、足りなければ入れ方を案内して止まり、スクリプトは入れない）。さらに、runner 本体が無い新品の Mac では、gh の認証（`make runner-tools` → `gh auth login -s admin:org`）が 3 つ目の前提になる。gh は 2/5 で入るが未認証なので、未認証のまま `make runner-setup` を流すと、2/5 の直後（colima を起動する前）に案内して止まる。認証してから、もう一度流す。

```bash
xcode-select --install   # C コンパイラ（cc）。go test -race の cgo に必要。GUI の確認が出るので自動化しない
# Homebrew は https://brew.sh の手順で入れる（Apple Silicon は /opt/homebrew）。スクリプトは自動で入れない
```

colima / docker / docker-buildx / docker-compose / fnm / gh / jq / shellcheck / fish / zstd と、fnm の default の Node.js LTS は、足りなければ `make runner-setup` が runner ユーザーとして入れる（下の「ツールのインストール」）。

Linux との違い:

| 項目 | Linux | macOS |
|---|---|---|
| ユーザーのホーム | `getent passwd` | `dscl . -read /Users/<user> NFSHomeDirectory` |
| `/etc/sudoers.d/github-runner` のグループ | `root` | `wheel`（`visudo -c` で検証してから置くのは同じ） |
| 依存 | 常に `apt-get install build-essential zstd`。Docker 公式 apt の `docker-ce` / `docker-ce-cli` が入っているホストでは、`docker.io` と、`docker.io` に Depends する `docker-buildx`・Recommends する `docker-compose-v2` は入れない（`docker-ce` は `docker.io` と Conflicts で、`apt-get -s install docker.io` はエラーで終わる）。buildx / compose は公式の `docker-buildx-plugin` / `docker-compose-plugin` を使い、無ければ 5/5 で NG を案内する（入れるのは手動）。`docker-ce` が removed で設定だけ残る（rc）ホストは対象外で、通常の経路になる。入っていないホストでは `docker.io` と `docker-buildx` も入れ、`docker compose version` が通らないときだけ `docker-compose-v2` も入れる | Xcode CLT・Homebrew の有無を確かめ（無ければ案内して止まる）、colima / docker / docker-buildx / docker-compose / zstd などは `runner-tools-install.sh` が brew で入れる |
| Docker の起動 | `systemctl enable --now docker` と docker グループ | runner ユーザーで `brew services start colima`（runner ユーザーのログイン後に自動で上がる）。`docker info` が通るまで最大 2 分待つ。docker CLI は `~/.docker/config.json` の docker context `colima` で colima に繋ぐ（下記） |
| サービス | systemd（`svc.sh` が unit を作る） | launchd（`svc.sh` が `~/Library/LaunchAgents/` に plist を作る。`svc.sh` は root を拒否するので runner ユーザーとして呼ぶ） |
| `.path` のガード | drop-in の `ExecStartPre=` | plist の `ProgramArguments` を `path-guard.sh --exec <runner dir> <home>` に差し替える。ガードが `.path` を直してから `runsvc.sh` へ `exec` する。起動のたびに走り、修復内容は `~/Library/Logs/<label>/stdout.log` に出る |
| 安定 PATH | `/opt/nvim/bin`・`/usr/games`・`/snap/bin` など | `/opt/homebrew/bin`・`/opt/homebrew/sbin` を入れ、Linux 専用のものを外す（定義は `runner_stable_path`） |
| 5/5 確認 | `/proc` の `Runner.Listener` の PATH と docker グループ。`docker --version` と、`docker buildx version` / `docker compose version`（通らなければ NG を案内するだけで止めない） | `/proc` も docker グループも無いので、runner ユーザーの最小環境で `docker info` / `docker buildx version` / `docker compose version` と、`.path` の PATH で `node` / `npx` / `cc` が引けるかを確かめる |
| runner のラベル | `[self-hosted, linux, x64]` | `[self-hosted, macOS, ARM64]` |

稼働中の runner に `.path` / `.env` / plist の変更を反映するときは、ジョブが無ければ `svc.sh stop` / `start` で再起動する（ジョブ実行中は再起動せず、手順を案内する）。`svc.sh start` の中身は `launchctl load -w` で、読み込み済みのときの挙動は実機で確かめていないため、稼働中は `start` を呼ばない設計にした。2 回続けて回しても、plist・`.path` は書き換わらず、再起動もしない（これもスタブでの確認のみ）。

注意:

- **docker の接続と buildx / compose**: colima の docker は `~/.colima/default/docker.sock` で待ち受けるが、docker CLI の既定は `/var/run/docker.sock` なので、そのままでは `docker info` が失敗する。brew の `docker-buildx` と `docker-compose` も、CLI の探索先に無いため `docker buildx` / `docker compose` が unknown command になる（実機の Mac で `docker compose version` が通らないことを確認）。そこで `runner-tools-install.sh` が、runner ユーザーの `~/.docker/config.json` に次を書く（sudo も環境変数も要らず、再起動後も残る。他のキーは残し、設定済みなら何も書かない）。
  - docker context `colima`（socket は `~/.colima/default/docker.sock`。colima が作っていればそのまま使う）を作り、`currentContext` にする。runner 専用ホストの前提で、別の context が選ばれていても `colima` に切り替える。
  - `cliPluginsExtraDirs` に `$(brew --prefix)/lib/docker/cli-plugins` を足す。brew の `docker-buildx` と `docker-compose` はどちらもここに入る（`docker-compose` の caveats も同じ場所）ので、1 件で両方が見える。
  `config.json` が JSON として壊れているときは上書きせず、失敗として報告する。colima を既定以外のプロファイルで動かす構成は対象外。
- fnm の `aliases/default/bin` は、macOS では公式インストーラの既定（`~/Library/Application Support/fnm`。`lib/tools/fnm.sh` が使う）と、Linux と同じ `~/.local/share/fnm` の両方を安定 PATH に入れ、ガードもどちらかにあれば正常とみなす。Homebrew 版の fnm（`/opt/homebrew/bin/fnm`）は `aliases/default/bin` の場所が上と同じになるかを実機で確かめていない。
- `tests/runner_host_setup_test.sh` / `tests/runner_tools_install_test.sh` は Linux 上で uname / sudo / brew / launchctl などをスタブに差し替えて分岐を確かめる（実際のインストールはしない）。launchd・colima・brew services の実機での動きは確かめていない。

#### ツールのインストール（`make runner-tools`）

`runner-tools-install.sh`（`make runner-tools`）は、runner のジョブが使うツールのうち**入っていないものだけ**を入れる。入っているものは飛ばすので、何度実行しても同じ結果になる。sudo は付けず、runner を動かすユーザー自身で実行する（root では拒否する。brew は root を拒否し、fnm / Node はホームに入るため）。macOS では `make runner-setup` が、runner ユーザーとして自動で呼ぶ。

| OS | 入れるもの |
|---|---|
| macOS | Homebrew で `colima` `docker` `docker-buildx` `docker-compose` `fnm` `gh` `jq` `shellcheck` `fish` `zstd`、fnm で Node.js LTS（default に設定。runner の安定 PATH は fnm の `aliases/default/bin` を指すため）、`~/.docker/config.json` の docker context と `cliPluginsExtraDirs`（上の「docker の接続と buildx / compose」） |
| Linux | `apt` で `jq` `shellcheck` `fish`、`install.sh` と同じ関数（`lib/tools/fnm.sh` / `lib/tools/gh.sh`）で `fnm` と `gh`、fnm で Node.js LTS。build-essential / zstd と、docker.io ホストの Docker / Buildx / Compose は `runner-host-setup.sh` が入れる（docker-ce ホストでは docker 系は入れない）ので、`make runner-setup` からは呼ばず、単体で `make runner-tools` したときだけ使う |

入れない（案内か表示だけ）もの:

- **Homebrew 自体**: 無ければ自動では入れず、`https://brew.sh` の手順を案内して止まる。
- **Xcode コマンドラインツール**: 無ければ `xcode-select --install` を案内して止まる（GUI の確認が出るため）。
- **Xcode 本体（`/Applications/Xcode.app`）とコード署名の証明書**: スクリプトでは入れず、あるか／無いかを表示するだけ（無くても失敗にはしない）。必要なジョブがあれば手動で入れる。

1 つ入れるのに失敗しても残りは試し、最後に失敗したものを列挙して失敗で終わる。

## 注意

- `nvim` 設定は LazyVim starter ベース。初回起動時に `lazy.nvim` がプラグインを自動取得する
- Linux の Neovim は Ubuntu LTS の古い apt 版を避けるため、公式 release tarball を `/opt/nvim` に入れる
- `fish_variables*` はマシン依存の状態ファイルで git 管理外
- `.claude/{history.jsonl,projects/,sessions/,...}` はランタイムデータで git 管理外（claude-config の `.gitignore` を踏襲）
- `claude-mcp/mcp.json` の `${VAR}` 参照は Claude Code の env 展開機能を利用。fish 経由で起動した Claude Code は `~/.env`（→ `~/dotfiles/.env`）の値を引き継ぐ
- Node.js は `fnm`（Rust 製、nvm 代替）で管理。`fish/conf.d/fnm.fish` が `fnm env --use-on-cd` を読み込み、`.nvmrc` / `.node-version` のあるディレクトリで自動切替
- tmux クリップボードは OS 自動分岐（Linux: `xclip` / macOS: `pbcopy`）

## ライセンスとコントリビューション

MIT License（[LICENSE](LICENSE)）。fork して自由に流用できます。

個人用 dotfiles のため取り込める変更の範囲は限られます。PR を出す前に [CONTRIBUTING.md](CONTRIBUTING.md) を確認してください。
