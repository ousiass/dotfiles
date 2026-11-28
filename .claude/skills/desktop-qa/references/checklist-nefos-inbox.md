# 例: Nefos Inbox デスクトップ QA チェックリスト（Windows）

nefos-inbox PR #459（ローカル AI・Ollama、Refs #458）の実機確認 11 項目を、版に依らない形にしたもの。
対象リポジトリの `qa/desktop-checklist.md` の下書きに使う。`<>` の値は対象の版の仕様書（`docs/requirements/*.md`）とコードから埋める（PR #459 時点の値を括弧に書いた）。

## 前提
- 入れ方: CI の成果物 `nefos-inbox-windows-amd64-setup`（NSIS。`/S` でサイレント）。既存の Nefos Inbox があれば上書きし、上書き前の `DisplayVersion` を記録する。検証用の別名ビルドは入れない。
- 置き場: 本体 `%LOCALAPPDATA%\Programs\Nefos Inbox`、アプリのデータ `%APPDATA%\Nefos Inbox`、WebView2 のデータ `%APPDATA%\nefos-inbox.exe`、ローカル AI の部品 `%LOCALAPPDATA%\Nefos Inbox\localai\`、Ollama の鍵 `%USERPROFILE%\.ollama`、「アプリと機能」の登録 `HKCU\...\Uninstall\jp.ousias.hitomado`。
- 片づけで消すもの: QA で増えた `localai\`（Ollama 本体・モデル）と `%USERPROFILE%\.ollama`（QA 前に無かったときだけ）。
- 消さないもの: `%APPDATA%\Nefos Inbox`（アカウント・メール・設定）、WebView2 のデータ。
- モデル: `<確認に使うモデル>`（gemma4:e2b だけ）。ほかのモデルは入れない。
- 注意: 送信ボタンは押さない。メール本文をスクショ以外に書き出さない。スクショはアプリのウィンドウだけ。

## 項目

### 1. 追加部品の取得と展開
- 手順: 設定 → AI → ローカル AI の「設定」→ 部品（Ollama）を入れる。
- 期待: 進み具合が表示され、完了後 `<部品の置き場>`（`%LOCALAPPDATA%\Nefos Inbox\localai\ollama`）に展開される。取得したファイルの SHA-256 がアプリの照合値と一致する（不一致なら入らない）。
- 証拠: 進み具合のスクショ（途中・完了）、`Get-ChildItem` の出力、ログの照合行。

### 2. 子プロセスがコンソールを出さずに起動する
- 手順: ローカル AI を使い始める（部品の起動）。
- 期待: コンソールのウィンドウが出ない（`CREATE_NO_WINDOW`）。`list_windows` に `ollama` のウィンドウが無く、`Get-Process ollama` は動いている。
- 証拠: 起動直後のスクショ、`list_windows` と `Get-Process` の出力。

### 3. アプリを閉じると子プロセスも止まる
- 手順: アプリを終了する（ウィンドウを閉じる・トレイから終了）。
- 期待: Job Object で結ばれた `ollama` が数秒以内に消える。起動直後（`CREATE_SUSPENDED` → Job → `ResumeThread`）の隙間で落としても残らない。
- 証拠: 終了前後の `Get-Process ollama`、残った場合は pid と親。

### 4. 使わないと止まる・停止ボタン
- 手順: ローカル AI を使ったあと `<無操作で止まるまでの時間>`（10 分）待つ。別に、画面の停止ボタンを押す。
- 期待: 時間が来たら子プロセスが止まり、画面の状態表示も「停止」になる。停止ボタンでもすぐ止まる。
- 証拠: 前後のスクショ、`Get-Process` の出力（時刻つき）。

### 5. 対応 PC の判定
- 手順: ローカル AI の画面を開く。
- 期待: 対応 PC（Windows のバージョン・メモリ・CPU が要件を満たす）では「この PC で動かす」が選べる。満たさない PC では理由の文言（`internal/localai/support_windows.go` の文）が出る。
- 証拠: 画面のスクショ、`[Environment]::OSVersion`・メモリ量の出力。

### 6. 生成の速さ・タイムアウト・設定値
- 手順: 「AI で下書き」を 1 回行い、開始から表示までを計る。
- 期待: `<タイムアウト秒>`（300 秒）以内に返る。リクエストの `num_ctx` が `<既定のコンテキスト長>`（16384）。
- 証拠: 計った秒数、生成後のスクショ、ログの該当行。

### 7. ユーザーフォルダーにできるファイル
- 手順: 項目 1〜6 のあと、`%USERPROFILE%\.ollama` を見る。
- 期待: できるもの（鍵 `id_ed25519` など）が仕様どおり。QA 前に無かったなら、片づけ対象として記録する。
- 証拠: `Get-ChildItem -Force` の出力（名前・大きさ・日時だけ。鍵の中身は読まない）。

### 8. 許可していない宛先へ通信しない
- 手順: 項目 6 の前後で、子プロセスの接続と DNS キャッシュを見る。
- 期待: `OLLAMA_NO_CLOUD` などの設定どおり、`<出てはいけない宛先>`（ollama.com）への接続・名前解決が無い（部品の取得元への通信は項目 1 のときだけ）。
- 証拠: `Get-NetTCPConnection -OwningProcess <pid>`、`Get-DnsClientCache | ? Entry -match '<宛先>'` の出力。

### 9. ローカル API の Host ヘッダー検査
- 手順: 子プロセスが待ち受けるポートを `Get-NetTCPConnection -State Listen -OwningProcess <pid>` で調べ、正しい Host と違う Host で 1 回ずつ要求する。
- 期待: 違う Host（例 `evil.example`）は 403、正しい Host は 200。
- 証拠: `Invoke-WebRequest ... -Headers @{Host='evil.example'}` と正しい Host の結果（状態コードだけ）。

### 10. WebView2 上の主要導線の通し
- 手順: メールを 1 通開き、「AI で下書き」→ 下書きが入るところまで。
- 期待: 下書き欄に文章が入る。エラー表示が無い。送信は押さない。
- 証拠: 下書きが入った画面のスクショ（本文が読める大きさにしない・切り抜く）。
- 注意: 下書きは確認後に破棄する（保存しない）。

### 11. アンインストール後に残るもの
- 手順: QA で新しく入れた場合だけアンインストールする（既存版を上書きした場合は元の版に戻すだけで、アンインストールしない）。
- 期待: 本体と「アプリと機能」の登録が消える。残るもの（`localai\`・`.ollama`・`%APPDATA%\Nefos Inbox`）が仕様どおりで、残すと決まっていないものが無い。
- 証拠: アンインストール前後の `Get-ChildItem`・レジストリの出力の差。
