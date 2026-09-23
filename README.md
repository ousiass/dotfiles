# dotfiles

Ubuntu / macOS 両対応の個人用設定ファイル群。複数マシン間で同期する。

## 構成

```
~/dotfiles/
├── install.sh          # セットアップスクリプト（idempotent）
├── reset-tools.sh      # 言語ツール/AI CLI を一括リセットするスクリプト
├── cleanup.sh          # キャッシュ類を掃除するスクリプト（make clean から呼ばれる）
├── runner-host-setup.sh # GitHub Actions self-hosted runner ホストのセットアップ（make runner-setup から呼ばれる）
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
├── tests/              # cleanup.sh の回帰テスト（make test）
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

`fish/config.fish` に登録済み。Permission / sandbox バイパスを付けた状態でワンコマンド起動できる:

| エイリアス | 展開 |
|---|---|
| `c` | `claude --dangerously-skip-permissions` |
| `cc` | `claude --dangerously-skip-permissions --continue` |
| `cs` | `claude --dangerously-skip-permissions --settings ...sandbox=true...` |
| `x` | `codex --dangerously-bypass-approvals-and-sandbox` |
| `fugu` / `f` | `codex-fugu --dangerously-bypass-approvals-and-sandbox` |
| `fc` | `codex-fugu --dangerously-bypass-approvals-and-sandbox resume --last` |
| `cu` | `cursor-agent -f` |
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

self-hosted runner を動かすホストで、ジョブ実行の前提（パスワード不要 sudo / Docker / Buildx / docker グループ / C コンパイラ）を整えて runner を systemd サービスとして起動する。対象は Linux + systemd の apt 系ディストリビューション。

先に runner の登録（`config.sh`）を済ませておく。

```bash
cd ~/actions-runner
./config.sh --url https://github.com/<org> --token <TOKEN>

cd ~/dotfiles
make runner-setup
```

runner のユーザーとディレクトリは変数で上書きできる。既定は sudo を呼び出したユーザーと、そのホーム配下の `actions-runner`。

```bash
make runner-setup RUNNER_USER=ci-runner RUNNER_DIR=/opt/runners/foo
```

何度実行しても同じ結果になる（idempotent）。ラベル（`linux` / `x64`）と runner group の対象リポジトリはスクリプトからは検証できないため、実行後の案内に従って手動で確認する。とくに `NOPASSWD: ALL` を入れる以上、runner group を「選択したリポジトリ」に限定し public リポジトリへ提供しないことが、fork PR 経由で第三者のコードがこのホストで走るのを防ぐ唯一の層になる。

`runner-host-setup.sh` は [ousiassllc/actions-runner-setup-base](https://github.com/ousiassllc/actions-runner-setup-base) から取り込んだコピー。詳細な背景（何が欠けるとどのエラーが出るか等）は上流の README を参照。上流を更新したらこのファイルも追従させる。

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
