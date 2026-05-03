# dotfiles

Ubuntu 環境向けの個人用設定ファイル群。`nvim` / `tmux` / `fish` を `~/.config/` 配下にシンボリックリンクで配置し、複数マシン間で同期する。

## 構成

```
~/dotfiles/
├── install.sh                 # セットアップスクリプト（idempotent）
├── nvim/                      # → ~/.config/nvim
├── tmux/                      # → ~/.config/tmux
└── fish/                      # → ~/.config/fish
    ├── config.fish
    ├── fish_plugins           # fisher 用プラグインリスト
    ├── conf.d/
    │   └── secrets.fish.example  # コピーして secrets.fish にする
    ├── completions/
    ├── functions/
    └── themes/
```

## セットアップ（新規マシン）

```bash
git clone git@github.com:ousiass/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 1. secrets.fish を作成して API キー等を記入（install.sh の前に必須）
cp fish/conf.d/secrets.fish.example fish/conf.d/secrets.fish
$EDITOR fish/conf.d/secrets.fish

# 2. セットアップ実行
./install.sh
```

`install.sh` は以下を行う:

1. `secrets.fish` の存在チェック（無ければエラーで停止）
2. `apt` で `fish` / `tmux` / `neovim` / `git` / `curl` / `xclip` をインストール
3. 既存の `~/.config/{nvim,tmux,fish}` を `*.bak.<日付>` にバックアップ
4. `~/dotfiles/{nvim,tmux,fish}` を `~/.config/` にシンボリックリンク
5. fisher（fish プラグインマネージャ）をインストール → `fish_plugins` の内容を反映
6. nvim プラグインを headless で同期（`lazy.nvim`）
7. ログインシェルを fish に変更（必要時のみ）

何度実行しても安全（既にリンク済みなら再リンクのみ）。

## Secrets

API キー等のマシンごとの機密値は `~/.config/fish/conf.d/secrets.fish` に記述する。このファイルは `.gitignore` 済みでコミットされない。テンプレートは `secrets.fish.example` を参照。

## 更新

```bash
cd ~/dotfiles
git pull
# シンボリックリンク経由で即反映
```

新しいマシンに変更を反映するときも `git pull` のみ。

## 注意

- nvim 設定は LazyVim starter ベース。初回起動時に `lazy.nvim` がプラグインを自動取得する
- `fish_variables*` はマシン依存の状態ファイルで git 管理外
