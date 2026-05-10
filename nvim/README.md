# Neovim Config

LazyVim ベースの個人設定。`lazy.nvim` で `lua/ousy/plugins/` 以下を自動 import する構造。

## Requirements

- Neovim **0.11+** （`vim.lsp.config` / `vim.lsp.enable` を使用）
- `git`, `make`, C コンパイラ（telescope-fzf-native のビルド用）
- Nerd Font（`nerd_font_variant = "mono"` 前提）

## 構成

```
nvim/
├── init.lua                 # entry point
├── lua/ousy/
│   ├── core/
│   │   ├── init.lua         # core 各モジュールの require
│   │   ├── options.lua      # vim.opt
│   │   ├── keymaps.lua      # 汎用キーマップ
│   │   └── autocmds.lua     # autocmd / terminal キーマップ
│   ├── lazy.lua             # lazy.nvim bootstrap
│   └── plugins/
│       ├── init.lua         # 軽量プラグイン (plenary, vim-tmux-navigator)
│       ├── lsp/             # mason / lspconfig
│       └── *.lua            # 各プラグイン
├── lazy-lock.json
├── lazyvim.json
└── stylua.toml
```

## キーマップ一覧

リーダーキーは <kbd>Space</kbd>。

### 基本（core）

| Mode | Keys | 動作 |
| --- | --- | --- |
| i | `jk` | Insert モードを抜ける |
| n | `<leader>nh` | 検索ハイライトをクリア |
| n | `<leader>+` / `<leader>-` | 数値をインクリメント / デクリメント |

### ウィンドウ・タブ

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `<leader>sv` / `<leader>sh` | 縦 / 横分割 |
| n | `<leader>se` | 分割サイズを均等化 |
| n | `<leader>sx` | 現在の分割を閉じる |
| n | `<leader>sm` | 分割の最大化トグル（vim-maximizer） |
| n | `<leader>to` / `<leader>tx` | 新規タブ / タブを閉じる |
| n | `<leader>tn` / `<leader>tp` | 次 / 前のタブ |
| n | `<leader>tf` | 現在のバッファを新規タブで開く |

### ターミナル

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `tt` | 新規タブでターミナル起動 |
| n | `tx` | 下分割でターミナル起動 |
| t | `<C-q>` | ターミナルを終了して閉じる |

### ファイラー（nvim-tree / Oil）

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `<leader>ee` | nvim-tree トグル |
| n | `<leader>ef` | カレントファイルで nvim-tree を開く |
| n | `<leader>ec` | nvim-tree を畳む |
| n | `<leader>er` | nvim-tree リフレッシュ |
| n | `-` | Oil で親ディレクトリを開く |

Oil バッファ内: `<CR>`=開く / `<C-v>`=vsplit / `<C-s>`=split / `<C-t>`=tab / `<C-p>`=preview / `<C-c>`=close / `<C-r>`=refresh / `_`=cwd / `` ` ``=cd / `~`=tcd / `g.`=hidden 切替 / `gx`=外部で開く / `g?`=help

### Telescope

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `<leader>ff` | ファイル検索 |
| n | `<leader>fr` | 最近使ったファイル |
| n | `<leader>fs` | live_grep |
| n | `<leader>fc` | カーソル下の単語で grep |
| n | `<leader>ft` | TODO 検索 |

Telescope picker 内: `<C-k>`/`<C-j>`=移動 / `<C-q>`=qflist へ送り Trouble で開く / `<C-t>`=Trouble で開く

### LSP（LspAttach 時のみ有効）

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `gR` | 参照を Telescope で表示 |
| n | `gD` | 宣言へジャンプ |
| n | `gd` | 定義を Telescope で表示 |
| n | `gi` | 実装を Telescope で表示 |
| n | `gt` | 型定義を Telescope で表示 |
| n / v | `<leader>ca` | コードアクション |
| n | `<leader>rn` | スマートリネーム |
| n | `<leader>D` | バッファ診断を Telescope で表示 |
| n | `<leader>d` | 行診断をフロート表示 |
| n | `[d` / `]d` | 前 / 次の診断へ |
| n | `K` | ホバードキュメント |
| n | `<leader>rs` | LSP 再起動 |

### 補完（blink.cmp / Insert モード）

| Keys | 動作 |
| --- | --- |
| `<C-Space>` | 補完 / ドキュメント表示 |
| `<C-k>` / `<C-j>` | 候補を上 / 下へ |
| `<C-b>` / `<C-f>` | ドキュメントスクロール |
| `<C-e>` | 補完を閉じる |
| `<CR>` | 確定 |
| `<Tab>` / `<S-Tab>` | スニペット送り / 戻り |

### Format / Lint

| Mode | Keys | 動作 |
| --- | --- | --- |
| n / v | `<leader>mp` | conform.nvim でフォーマット |
| n | `<leader>l` | nvim-lint で lint |

保存時は `format_on_save` で自動フォーマット。

### Git（gitsigns / Snacks lazygit / Diffview）

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `]h` / `[h` | 次 / 前の hunk |
| n / v | `<leader>hs` | hunk をステージ |
| n / v | `<leader>hr` | hunk をリセット |
| n | `<leader>hS` / `<leader>hR` | バッファをステージ / リセット |
| n | `<leader>hu` | ステージ取り消し |
| n | `<leader>hp` | hunk プレビュー |
| n | `<leader>hb` / `<leader>hB` | 行 blame / 行 blame トグル |
| n | `<leader>hd` / `<leader>hD` | この変更を diff / `~` と diff |
| o / x | `ih` | hunk text object |
| n | `<leader>gg` | Lazygit |
| n | `<leader>gf` / `<leader>gl` | Lazygit ファイル履歴 / コミットログ |
| n | `<leader>gd` / `<leader>gc` | Diffview Open / Close |
| n | `<leader>gh` / `<leader>gH` | ファイル履歴 / ブランチ履歴 |

### Harpoon

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `<leader>ha` | ファイルを Harpoon に追加 |
| n | `<leader>hh` | Harpoon メニュー |
| n | `<leader>1` 〜 `<leader>4` | 1〜4番目を開く |
| n | `<leader>hP` / `<leader>hN` | 前 / 次の Harpoon |

### Trouble

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `<leader>xx` | Trouble トグル |
| n | `<leader>xw` / `<leader>xd` | workspace / document 診断 |
| n | `<leader>xq` / `<leader>xl` | quickfix / location list |
| n | `<leader>xt` | TODO を Trouble で表示 |

### Flash（ジャンプ）

| Mode | Keys | 動作 |
| --- | --- | --- |
| n / x / o | `s` | Flash jump |
| n / x / o | `S` | Flash Treesitter |
| o | `r` | Remote Flash |
| o / x | `R` | Treesitter Search |

### TODO コメント

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `]t` / `[t` | 次 / 前の TODO |

### セッション（auto-session）

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `<leader>wr` | セッションを復元 |
| n | `<leader>ws` | セッションを保存 |

### Snacks（通知 / その他）

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `<leader>sn` | 通知履歴 |
| n | `<leader>un` | 通知を閉じる |

### Undotree

| Mode | Keys | 動作 |
| --- | --- | --- |
| n | `<leader>u` | Undotree トグル |

### Treesitter incremental selection

| Keys | 動作 |
| --- | --- |
| `<C-space>` | 選択開始 / ノード拡張 |
| `<bs>` | ノード縮小 |

### Treesitter textobjects

選択（`a`=outer / `i`=inner、行内）:

| Keys | 対象 |
| --- | --- |
| `a=` / `i=` / `l=` / `r=` | 代入式（外/内/左辺/右辺） |
| `a:` / `i:` / `l:` / `r:` | オブジェクトプロパティ |
| `aa` / `ia` | パラメータ／引数 |
| `ai` / `ii` | 条件式 |
| `al` / `il` | ループ |
| `af` / `if` | 関数呼び出し |
| `am` / `im` | メソッド／関数定義 |
| `ac` / `ic` | クラス |

スワップ:

| Keys | 動作 |
| --- | --- |
| `<leader>na` / `<leader>pa` | 引数を次 / 前と入れ替え |
| `<leader>n:` / `<leader>p:` | プロパティを次 / 前と入れ替え |
| `<leader>nm` / `<leader>pm` | 関数を次 / 前と入れ替え |

ノード移動:

| Keys | 動作 |
| --- | --- |
| `]f` / `[f` (大文字=end) | 関数呼び出し開始へ |
| `]m` / `[m` (大文字=end) | メソッド/関数定義開始へ |
| `]c` / `[c` (大文字=end) | クラス開始へ |
| `]i` / `[i` (大文字=end) | 条件式開始へ |
| `]l` / `[l` (大文字=end) | ループ開始へ |
| `]s` / `]z` | 次のスコープ / fold |

`f` / `F` / `t` / `T` の往復は `;` / `,` で繰り返し可（textobjects の repeatable 化）。

## プラグイン早見表

| 用途 | プラグイン |
| --- | --- |
| プラグインマネージャ | folke/lazy.nvim |
| カラースキーム | folke/tokyonight.nvim |
| ステータスライン | nvim-lualine/lualine.nvim |
| バッファライン | akinsho/bufferline.nvim |
| ダッシュボード / 通知 / lazygit | folke/snacks.nvim |
| ファイラー | nvim-tree/nvim-tree.lua, stevearc/oil.nvim |
| Fuzzy finder | nvim-telescope/telescope.nvim |
| LSP | neovim/nvim-lspconfig + williamboman/mason.nvim |
| 補完 | saghen/blink.cmp |
| フォーマッタ | stevearc/conform.nvim |
| Linter | mfussenegger/nvim-lint |
| Treesitter | nvim-treesitter/nvim-treesitter (+ textobjects) |
| Git | lewis6991/gitsigns.nvim, sindrets/diffview.nvim |
| ジャンプ | folke/flash.nvim |
| ファイル切替 | ThePrimeagen/harpoon (harpoon2) |
| Quickfix 強化 | folke/trouble.nvim |
| TODO ハイライト | folke/todo-comments.nvim |
| ヘルパー | folke/which-key.nvim, folke/noice.nvim, stevearc/dressing.nvim |
| Undo | mbbill/undotree |
| セッション | rmagatti/auto-session |
| AI 補完 | github/copilot.vim |

## メンテナンスコマンド

| コマンド | 用途 |
| --- | --- |
| `:Lazy` | プラグイン管理 UI |
| `:Lazy sync` | install + update + clean |
| `:Mason` | LSP / formatter / linter のインストール UI |
| `:LspInfo` | アタッチ中の LSP 確認 |
| `:LspRestart` | LSP 再起動 |
| `:checkhealth` | 環境診断 |
| `:TSUpdate` | Treesitter parser 更新 |

## 注意

- terminal キー (`tt` / `tx`) は vim 標準の `t{char}`（till）を上書きしているので、`t` で文字までジャンプする操作は使えない（代わりに `;` / `,` で repeatable_move を使うか、`f`/`F` を使う）。
- LSP server 名は Neovim 0.11+ の新 API (`vim.lsp.config` / `vim.lsp.enable`) で設定しており、`solidity_ls_nomicfoundation` が必要な場合は `mason.lua` / `lspconfig.lua` の `solidity` を差し替える。
