# dotfiles

Ubuntu / macOS 両対応の個人用設定ファイル群。複数マシン間で同期する。

## 構成

```
~/dotfiles/
├── install.sh          # セットアップスクリプト（idempotent）
├── reset-tools.sh      # 言語ツール/AI CLI を一括リセットするスクリプト
├── .env.example        # .env のテンプレート
├── .env                # 実体（gitignore 済、~/.env はこれへのシンボリックリンク）
├── claude-mcp/        
│   └── mcp.json        # Claude Code MCP 設定（${VAR} で env 参照、~/.mcp.json はこれへのシンボリックリンク）
├── .claude/            # → ~/.claude（CLAUDE.md, agents/, skills/, settings.json 等）
├── .codex/
│   ├── AGENTS.md       # → ~/.codex/AGENTS.md（Codex グローバル指示、言語設定等）
│   └── skills/         # 各サブディレクトリが ~/.codex/skills/<name> に symlink される Codex 用 skill 群
├── nvim/               # → ~/.config/nvim
├── tmux/               # → ~/.config/tmux
├── gh-dash/            # → ~/.config/gh-dash (GitHub Dashboard CLI)
├── herdr/              # → ~/.config/herdr (エージェント向けターミナルマルチプレクサ、tmux 準拠 keybinding)
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
   - **Fugu** (Sakana AI の Codex 設定バンドル、公式 install スクリプト)
     - `~/.env` から `SAKANA_API_KEY` を拾えれば非対話でインストール、無ければ warn してスキップ
     - `~/.codex/skills/.system/` を経由して `codex-fugu` ランチャと設定バンドルを配置
   - **herdr** (エージェント向けターミナルマルチプレクサ、公式 curl インストーラ)
     - `~/dotfiles/herdr/config.toml` を `~/.config/herdr/config.toml` に symlink し、prefix を `ctrl+s` 等 tmux と統一
8. 各ツールのバイナリパスを `fish/conf.d/paths.fish` と `shell/paths.sh` で追加
9. 既存の `~/.config/{nvim,tmux,fish,gh-dash}`, `~/.claude`, `~/.mcp.json`, `~/.env` を `*.bak.<日付>` にバックアップ
10. dotfiles を該当パスにシンボリックリンク（`~/.env` → `~/dotfiles/.env`、`~/.mcp.json` → `~/dotfiles/claude-mcp/mcp.json`、`~/dotfiles/.codex/AGENTS.md` → `~/.codex/AGENTS.md`、`~/dotfiles/.codex/skills/<name>` → `~/.codex/skills/<name>` 等）
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
./install.sh fugu gemini_cli # 複数指定可
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
Codex や Claude Code の実行セッション中は、自分自身を壊さないように該当 CLI の self-update をスキップする。

## 各ツールをリセット（テスト/壊れた時用）

`reset-tools.sh` で言語ツール・AI CLI 一式を削除して install.sh で再インストール:

```bash
bash ~/dotfiles/reset-tools.sh
```

- `CLAUDECODE=1` を検出して Claude Code セッション中は自動的に拒否
- 削除対象: uv / bun (codex/gemini 含む) / Codex CLI standalone package / rustup / fnm + Node / Go / Claude Code
- 削除しないもの: fish/tmux/neovim/git, ~/.env, ~/.claude のデータ, シンボリックリンク

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
