# コントリビューションガイド

このリポジトリは **個人用の dotfiles** です。汎用のセットアップフレームワークを目指しているわけではないので、
「自分の環境ではこうしたい」という設定変更よりも、**壊れているものを直す PR** の方が取り込まれやすいです。

自分好みに改造したい場合は fork して使ってください。MIT ライセンスなので自由に流用できます。

## 歓迎する変更

- バグ修正（特定 OS で `install.sh` が失敗する、シェル関数が壊れている等）
- 上流ツールの仕様変更への追従（インストーラの URL 変更、CLI のフラグ廃止など）
- 移植性の改善（Ubuntu / macOS のどちらか一方でしか動かない箇所の是正）
- README / コメントの誤りの訂正

## 取り込みにくい変更

- 個人的な好みに属する設定変更（キーバインド、プロンプト、エイリアスの追加など）
- 新しいツールの追加（自分が使わないツールはメンテナンスできないため）
- 大規模なリファクタリング（レビューコストが利益を上回るため）

判断に迷う場合は、PR を書く前に Issue で相談してください。

## 前提知識

- `install.sh` と `update.sh` は **idempotent**（何度実行しても安全）であることが必須の設計制約です。
  「既にインストール済みならスキップする」判定を必ず入れてください。
- Ubuntu と macOS の両方で動く必要があります。片方でしか動かない処理は `lib/core/os.sh` の OS 判定で分岐させてください。
- シェルスクリプトは **bash** で書きます。ログインシェルは fish ですが、インストーラ側は bash に統一しています。
- `shell/paths.sh` だけは POSIX sh です（`~/.profile` から source されるため）。

## ディレクトリ構成の規約

| パス | 役割 |
|---|---|
| `install.sh` | エントリポイント。個別インストールの引数解決もここ |
| `lib/load.sh` | `lib/` 配下の読み込み |
| `lib/common.sh` | 共通ヘルパーの集約 |
| `lib/core/` | OS 判定・ログ・symlink・パッケージなど、ツール非依存の基盤 |
| `lib/tools/` | ツール 1 つにつき 1 ファイル |

`lib/tools/<name>.sh` には `install_<name>()` を定義してください。この命名により `./install.sh <name>` で
個別インストールできるようになります（`install.sh` が関数名を解決します）。
`# shellcheck shell=bash` をファイル先頭に置くのも既存ファイルに合わせてください（shebang は付けません）。

## 秘密情報の扱い

- API キー等はすべて `~/dotfiles/.env` に集約します。`.env` は `.gitignore` 済みです。
- **設定ファイルに秘密値を直書きしないでください。** 新しい変数が必要なら `.env.example` にプレースホルダを追加します。
- `claude-mcp/mcp.json` などから参照する場合は `${VAR}` 形式を使い、値そのものはコミットしません。

## ローカルでの検証

CI と同じチェックを手元で回せます。

```bash
# bash 構文チェック
git ls-files '*.sh' | xargs -n1 bash -n

# shellcheck（warning 以上でエラー）
git ls-files '*.sh' | xargs shellcheck -x --severity=warning

# fish 構文チェック
git ls-files '*.fish' | xargs -n1 fish --no-execute

# JSON の妥当性
git ls-files '*.json' | xargs -n1 jq empty
```

`install.sh` に手を入れた場合は、**2 回連続で実行して 2 回目が何も壊さないこと**（idempotent）を確認してください。

## コミットとブランチ

- コミットメッセージは `<type>: <日本語の説明>` の形式です。
  - type は英語（`feat` / `fix` / `update` / `refactor` / `docs` / `test` / `chore` など）
  - 例: `fix: macOS で fnm のパスが通らない問題を修正`
- `main` に直接 push せず、ブランチを切って PR を出してください。
- マージは **merge commit** 方式です（squash / rebase は使いません）。

## PR を出す前のチェック

- [ ] 上記のローカル検証がすべて通る
- [ ] `install.sh` を変更した場合、idempotent であることを確認した
- [ ] 秘密情報を含んでいない
- [ ] 変更が README の記述と矛盾しない（矛盾するなら README も更新した）
