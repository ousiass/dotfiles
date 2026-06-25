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
│   └── skills/         # 各サブディレクトリが ~/.codex/skills/<name> に symlink される Codex 用 skill 群
├── nvim/               # → ~/.config/nvim
├── tmux/               # → ~/.config/tmux
├── gh-dash/            # → ~/.config/gh-dash (GitHub Dashboard CLI)
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
4. システムパッケージ（fish, tmux, neovim, git, curl, rsync, Linux のみ xclip）を `apt` または `brew` で
5. 言語ツールを公式インストーラで（未導入のもののみ）:
   - **uv** (Python パッケージマネージャ)
   - **bun** (JavaScript runtime/manager)
   - **rustup** (Rust toolchain manager)
   - **fnm** (Fast Node Manager, Rust 製の nvm 代替)
   - **Go** (Linux: 公式 tarball を `/usr/local/go` へ / macOS: brew)
6. AI CLI ツール（未導入のもののみ）:
   - **Claude Code** (公式 curl インストーラ)
   - **OpenAI Codex CLI** (`bun install -g @openai/codex`)
   - **Gemini CLI** (`bun install -g @google/gemini-cli`)
   - **Fugu** (Sakana AI の Codex 設定バンドル、公式 install スクリプト)
     - `~/.env` から `SAKANA_API_KEY` を拾えれば非対話でインストール、無ければ warn してスキップ
     - `~/.codex/skills/.system/` を経由して `codex-fugu` ランチャと設定バンドルを配置
7. 各ツールのバイナリパスを fish の `fish_user_paths` (universal) に追加
8. 既存の `~/.config/{nvim,tmux,fish,gh-dash}`, `~/.claude`, `~/.mcp.json`, `~/.env` を `*.bak.<日付>` にバックアップ
9. dotfiles を該当パスにシンボリックリンク（`~/.env` → `~/dotfiles/.env`、`~/.mcp.json` → `~/dotfiles/claude-mcp/mcp.json`、`~/dotfiles/.codex/skills/<name>` → `~/.codex/skills/<name>` 等）
10. `~/.claude` のランタイムデータ（履歴・セッション等）をバックアップから dotfiles 側に移行（既存は上書きしない）
11. fisher（fish プラグインマネージャ）をインストール → `fish_plugins` の内容を反映
12. fnm 経由で Node.js LTS をインストールしデフォルトに設定
13. nvim プラグインを headless で同期（`lazy.nvim`）
14. ログインシェルを fish に変更（必要時のみ）

何度実行しても安全（既にインストール済 / リンク済みならスキップ）。

## 個別ツールの再インストール

特定のツールだけ入れ直したい場合は `install.sh` に `install_<name>` の `<name>` 部分を渡す:

```bash
./install.sh fugu          # = make fugu
./install.sh codex_cli
./install.sh fugu gemini_cli  # 複数指定可
```

未定義の名前を渡すとエラー終了する（誤入力を握りつぶさない）。

## Fish エイリアス（AI CLI 一発起動）

`fish/config.fish` に登録済み。Permission / sandbox バイパスを付けた状態でワンコマンド起動できる:

| エイリアス | 展開 |
|---|---|
| `c` | `claude --dangerously-skip-permissions` |
| `cc` | `claude --dangerously-skip-permissions --continue` |
| `cs` | `claude --dangerously-skip-permissions --settings ...sandbox=true...` |
| `x` | `codex --dangerously-bypass-approvals-and-sandbox` |
| `fugu` | `codex-fugu --dangerously-bypass-approvals-and-sandbox` |

`codex-fugu` は内部で `codex -p fugu "$@"` を `exec` するので、`fugu` でも codex 本体の bypass フラグがそのまま効く。

## 更新

```bash
cd ~/dotfiles
git pull
# シンボリックリンク経由で即反映
```

## 各ツールをリセット（テスト/壊れた時用）

`reset-tools.sh` で言語ツール・AI CLI 一式を削除して install.sh で再インストール:

```bash
bash ~/dotfiles/reset-tools.sh
```

- `CLAUDECODE=1` を検出して Claude Code セッション中は自動的に拒否
- 削除対象: uv / bun (codex/gemini 含む) / rustup / fnm + Node / Go / Claude Code
- 削除しないもの: fish/tmux/neovim/git, ~/.env, ~/.claude のデータ, シンボリックリンク

## 注意

- `nvim` 設定は LazyVim starter ベース。初回起動時に `lazy.nvim` がプラグインを自動取得する
- `fish_variables*` はマシン依存の状態ファイルで git 管理外
- `.claude/{history.jsonl,projects/,sessions/,...}` はランタイムデータで git 管理外（claude-config の `.gitignore` を踏襲）
- `claude-mcp/mcp.json` の `${VAR}` 参照は Claude Code の env 展開機能を利用。fish 経由で起動した Claude Code は `~/.env`（→ `~/dotfiles/.env`）の値を引き継ぐ
- Node.js は `fnm`（Rust 製、nvm 代替）で管理。`fish/conf.d/fnm.fish` が `fnm env --use-on-cd` を読み込み、`.nvmrc` / `.node-version` のあるディレクトリで自動切替
- tmux クリップボードは OS 自動分岐（Linux: `xclip` / macOS: `pbcopy`）
