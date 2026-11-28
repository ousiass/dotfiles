---
name: desktop-qa
description: Windows 実機のデスクトップアプリを puppet-remo（Nefos Remote）の MCP で、リポジトリの qa/desktop-checklist.md どおりに QA する
---

# desktop-qa

悠太さんの Windows 実機（tailnet の `silent`）を puppet-remo の MCP で操作し、デスクトップアプリをチェックリストどおりに 1 項目ずつ確かめる。各項目に OK/NG・根拠・スクショを付け、入れたものを片づけて報告する。

## 入力

| 値 | 例 | 既定 |
|---|---|---|
| 対象リポジトリと版 | `ousiassllc/nefos-inbox` の PR #459 head / `main` | 呼び出し元の指示 |
| `<pane>` | `T2` | 呼び出し元の名前（報告ファイル名に使う） |
| チェックリスト | 対象リポジトリの `qa/desktop-checklist.md` | — |
| 接続先 | `http://100.94.64.51:8765/mcp`（Host ヘッダー `100.94.64.51:8765`） | `scripts/remo.py` の既定 |

- 出すもの: `/tmp/swarm-console/reports/0_<pane>.md`（[templates/report.md](templates/report.md) の形）と `~/0_<pane>-qa/`（スクショ）。
- チェックリストが無いとき: [references/checklist-format.md](references/checklist-format.md) の形と例（nefos-inbox / nefos-veil）を元に下書きを作り、`ask` で項目を確かめてから始める。勝手に項目を足し引きしない。

## 守ること（違反しそうなら止めて報告）

- `PUPPET_REMO_TOKEN`（`~/.env`）の値を画面・ログ・レポート・コミットに出さない。MCP は `scripts/remo.py` 経由で呼ぶ（トークンを伏せる）。`curl -H "Authorization: Bearer $PUPPET_REMO_TOKEN"` を打たない（コマンド行が記録に残る）。
- マウス・キーボード・クリップボードは悠太さんと共有。始める前に、いま操作中でないかを `ask` で確かめる。悠太さんの入力とぶつかったら（打った文字が別のウィンドウに入った等）、すぐ `release_control` して止める。
- クリップボードの中身（悠太さんの文字のことがある）をログ・レポートに書かない。上書きする前に読んで変数にだけ持ち、終わりに戻す。
- 既存のアプリが入っていればそれを使う。検証用の複製（別名・別フォルダー）を新しく入れない。上書きするなら、その前に元のバージョンを記録する。
- 入れてよいのは確認用のアプリ（と、アプリが自分で入れる部品）だけ。それ以外の Windows 設定は変えない。悠太さんのアカウント設定・データ（メール・設定・WebView2 のデータ）は消さない。
- 送信ボタン（メール・投稿・共有）は押さない。下書きまで。アプリのデータを外に出さない（スクショはアプリのウィンドウだけを切り抜き、`~/0_<pane>-qa/` の外に置かない。PR・Issue に貼らない）。
- puppet-remo の止める対象（denylist の app_denied、elevated・own_window の blocked）は迂回しない。UAC の画面（昇格）は操作できない。要るなら悠太さんに押してもらうか止める。
- puppet-remo のリポジトリは変更しない。足りない道具は報告の「残りの判断」に書く。

## 流れ

### 1. 接続と道具の確認（操作権はまだ取らない）

```bash
R=~/.claude/skills/desktop-qa/scripts/remo.py   # dotfiles では .claude/skills/desktop-qa/scripts/remo.py
$R tools                         # 道具の一覧。下の「新しい道具」の有無をここで判断する
$R call get_control_status
$R call get_screen_info          # モニターと縮尺。座標はすべて縮小後のスクショの画素
$R call list_launchable_apps     # mode: allowlist / denylist
$R call list_windows             # 開いているウィンドウ（悠太さんの作業中のものを含む）
```

- 401 → トークンか接続の許可が無い。止めて報告する（ホスト側の GUI で許可・発行が要る）。
- `state` が `held`（他のセッション）→ 待つか止める。奪わない。
- 道具の細かい振る舞い・エラーコード・PowerShell の動かし方: [references/remo.md](references/remo.md)。

道具の分岐（`tools` の説明文で判断する。名前は変わりうる）:

| したいこと | 今の道具での手順 | 道具が足されたとき |
|---|---|---|
| 成果物を Windows へ送る | この PC で一時 HTTP サーバー（tailnet の IP にだけ bind）→ PowerShell で `Invoke-WebRequest`・`Get-FileHash` | ファイル転送の道具で送り、ハッシュを照合 |
| コマンドを動かす | PowerShell を `launch_app` → `type` → 結果を `Set-Clipboard` → `clipboard_read`（references/remo.md の「PowerShell」） | 許可コマンド実行の道具を使う（クリップボード・キー入力は使わない） |
| 画面に出るまで待つ | `wait`（最大 10 秒）と `screenshot` / `get_ui_tree` を回数上限つきで繰り返す | 「出るまで待つ」道具を使う |
| 長い画面操作 | クリック・キーを 1 つずつ。または `run_task`（`window_id` でアプリに限る） | 同左 |

`run_task` の `completed` はモデルの自己申告。結果は自分でスクショか UI ツリーで確かめる。

### 2. 操作権を取る

`ask` で悠太さんの了承（操作中でない）を得てから `$R call acquire_control`。ホストの承認待ちになることがある（`approval_denied` / `approval_timeout` なら止める）。セッションは `remo.py` が保存して使い回す（呼ぶたびに作り直すと操作権を失う）。

### 3. Windows 版の成果物を用意する

1. 対象の版の CI run から Windows 成果物を取る。`gh run list -R <repo> --commit <sha>` → `gh run download <run> -R <repo> -n <名前>`。名前は対象リポジトリの `.github/workflows/*.yml` の `upload-artifact`（例: nefos-inbox は `nefos-inbox-windows-amd64-setup`、nefos-veil は `nefos-veil-windows-amd64`）。
2. 無い・期限切れのときは、対象リポジトリの worktree で Windows 向けにクロスビルドする（コマンドは CI 定義か Taskfile のもの。独自の手順にしない）。
3. SHA-256 をこの PC で取り、報告に書く。Windows 側でも同じ値か確かめる。

### 4. 入れる前の状態を記録する

PowerShell（または許可コマンド）で、読むだけのコマンドを流す。中身（メール・設定値）は読まず、名前・版・大きさ・日時だけ記録する。

- 既存のインストール: 「アプリと機能」の登録（`HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\*` の `DisplayName`・`DisplayVersion`・`InstallLocation`）、exe の `VersionInfo`。
- データ・設定の置き場（チェックリストに書かれた `%APPDATA%`・`%LOCALAPPDATA%`・`%USERPROFILE%` の下など）の有無と、直下の名前・大きさ・更新日時。
- 動いているプロセス（名前・pid・パス）と、開いているウィンドウ（`list_windows`）。
- 起動中の既存アプリは、悠太さんに確かめてから閉じる（未保存の作業があるかもしれない）。

これが「片づけ」で戻す基準になる。記録はレポートの「入れる前の状態」に書く。

### 5. 入れる

- 既存版があれば上書き（チェックリストに手順があればそれ）。元の版を記録したことを確かめてから。
- 無ければ通常の場所に入れる。`/S` などのサイレント指定は、インストーラーが対応している場合だけ。
- 入れたもの（アプリ・部品・モデル・作った設定）は、出たそばから「入れたもの」の表に足していく。

### 6. チェックリストを 1 項目ずつ確かめる

各項目で次を繰り返す。まとめて流さない。

1. 項目の「手順」どおりに操作する。
2. 証拠を取る: スクショ（`$R shot ~/0_<pane>-qa/<NN>_<短い名前>.png --window <id> --zoom 2`。アプリのウィンドウだけ）、`get_ui_tree` の該当テキスト、PowerShell の出力。
3. 「期待」と照らして OK / NG / 未確認 を決める。根拠は「何を見て」「何が出たか」を 1〜2 行で。見ていないものを OK にしない。
4. NG は再現手順（何をしたら何が出たか）とスクショを残す。修正はこのスキルではしない（呼び出し元が別に扱う）。

画面の字が小さい（縮尺 0.4 前後）ときは `--window` で切り抜き `--zoom 2` で拡大するか、`get_ui_tree` で文字を読む。ウィンドウを最大化したら、項目が終わったら元に戻す。

### 7. 片づける

入れる前の記録と比べ、増えたものだけ消す。消す前に一覧を作り、悠太さんのデータに当たらないか確かめる。

1. 自分が起こしたプロセスを止める（記録した pid・パスで絞る。名前だけで止めない。WebView2 の `msedgewebview2.exe` は悠太さんの他のアプリも使う）。
2. 新しく入れたアプリはアンインストールする。既存版を上書きしたときは、記録した元の版に戻す（同じ版のインストーラーを Releases から取って入れ直す）。戻せないときは消さずに「残りの判断」に書く。
3. 送ったファイル・一時スクリプト・この PC の一時 HTTP サーバーを消す（`o2ctl services stop <name>`）。
4. QA 中に増えたフォルダー（例: アプリが入れた部品）は、チェックリストで「片づけで消す」とされたものだけ消す。もとからあったデータは消さない。
5. 自分で開いた PowerShell などのウィンドウを閉じる。クリップボードを戻す。`$R close`（操作権を返す）。
6. 片づけ後に手順 4 と同じコマンドで状態を取り、前と比べた差を「消したもの」「残したもの」に書く。

### 8. 報告する

[templates/report.md](templates/report.md) の形で `/tmp/swarm-console/reports/0_<pane>.md` に書く。トークン・メールの中身・クリップボードの中身は書かない。

## 途中で止めるとき

操作権を返し（`$R close`）、起こしたプロセスと入れたものの状態を報告に書いてから止める。片づけきれなかったものは「残したもの」に理由と一緒に書く。

## 参照

- [references/remo.md](references/remo.md) — MCP の振る舞い・エラー・座標・PowerShell の動かし方・成果物の送り方
- [references/checklist-format.md](references/checklist-format.md) — `qa/desktop-checklist.md` の書き方
- [references/checklist-nefos-inbox.md](references/checklist-nefos-inbox.md) — 例: Nefos Inbox（ローカル AI まわり）
- [references/checklist-nefos-veil.md](references/checklist-nefos-veil.md) — 例: Nefos Veil（ラベル・素顔・仮想デバイス名）
