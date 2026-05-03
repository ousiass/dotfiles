# dotfiles

Ubuntu 環境向けの個人用設定ファイル群。複数マシン間で同期する。

## 構成

```
~/dotfiles/
├── install.sh          # セットアップスクリプト（idempotent）
├── .env.example        # ~/.env のテンプレート（実体は .gitignore）
├── .mcp.json           # Claude Code MCP 設定（${VAR} で env 参照）
├── .claude/            # → ~/.claude（CLAUDE.md, agents/, skills/, settings.json 等）
├── nvim/               # → ~/.config/nvim
├── tmux/               # → ~/.config/tmux
└── fish/               # → ~/.config/fish
    ├── config.fish
    ├── fish_plugins
    ├── conf.d/
    │   └── secrets.fish    # ~/.env を読み込んで env 変数化する loader
    ├── completions/
    ├── functions/
    └── themes/
```

## 環境変数 (~/.env)

シェルにセットしたい環境変数は **secret / 非secret を問わず すべて `~/.env` に集約する**:

```bash
# ~/.env （gitignore 済み、dotfiles 外）
GEMINI_API_KEY=xxxxx
OPENAI_API_KEY=xxxxx
SUPABASE_ACCESS_TOKEN=xxxxx

# 非secret も同様にここに
EDITOR=nvim
SOME_TOOL_HOME=/opt/some-tool
```

- fish 起動時に `conf.d/secrets.fish` が `~/.env` を読み込んで `set -gx` する
- `.mcp.json` の `${SUPABASE_ACCESS_TOKEN}` 等の参照もこの env から解決される
- `config.fish` 等に env 変数を直書きせず、必ず `~/.env` 経由で設定する

## セットアップ（新規マシン）

```bash
git clone git@github.com:ousiass/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 1. ~/.env を作成して API キー等を記入（install.sh の前に必須）
cp .env.example ~/.env
$EDITOR ~/.env

# 2. セットアップ実行
./install.sh
```

`install.sh` は以下を行う:

1. `~/.env` の存在チェック（無ければエラーで停止）
2. `apt` で `fish` / `tmux` / `neovim` / `git` / `curl` / `xclip` / `rsync` をインストール
3. 既存の `~/.config/{nvim,tmux,fish}`, `~/.claude`, `~/.mcp.json` を `*.bak.<日付>` にバックアップ
4. dotfiles を該当パスにシンボリックリンク
5. `~/.claude` のランタイムデータ（履歴・セッション等）をバックアップから dotfiles 側に移行（既存は上書きしない）
6. fisher（fish プラグインマネージャ）をインストール → `fish_plugins` の内容を反映
7. nvim プラグインを headless で同期（`lazy.nvim`）
8. ログインシェルを fish に変更（必要時のみ）

何度実行しても安全（既にリンク済みなら再リンクのみ）。

## 更新

```bash
cd ~/dotfiles
git pull
# シンボリックリンク経由で即反映
```

## 注意

- `nvim` 設定は LazyVim starter ベース。初回起動時に `lazy.nvim` がプラグインを自動取得する
- `fish_variables*` はマシン依存の状態ファイルで git 管理外
- `.claude/{history.jsonl,projects/,sessions/,...}` はランタイムデータで git 管理外（claude-config の `.gitignore` を踏襲）
- `.mcp.json` の `${VAR}` 参照は Claude Code の env 展開機能を利用。fish 経由で起動した Claude Code は `~/.env` の値を引き継ぐ
