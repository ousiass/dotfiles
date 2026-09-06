> 注: このファイルは `~/dotfiles` リポジトリ全体（fish / nvim / tmux / install scripts / `.claude/` 配下のスキル類すべて）の変更履歴です。

## [v0.11.0] - 2026-09-06

E2E テストと品質監査のスキル群（`e2e-turbo` / `e2e-record` / `test-audit` / `kuuhaku`）を追加し、あわせて sweep 系スキルの共有 reference を `sweep-common/` に切り出して実行時に無言で失われていたガードを塞いだリリース。sweep 側の修正は「シェル変数が Bash 呼び出しをまたいで持ち越される」という誤った前提が根にあり、ベースブランチ直コミット防止のガードが常に素通りしていた。

### ✨ New Features / 新機能

- Add `e2e-turbo` skill / Playwright E2E を並列前提の構造から設計し、全量を数分で完走させるスキルを追加。**3軸 project 分割 + 二段並列**、**storageState 事前生成**（全テストから UI ログインを消す）、**per-test Factory + teardown**（テスト間共有状態を構造的に禁止し `fullyParallel` を成立させる）、**impact-map**（PR では影響 spec のみ実行）の4本柱で構成し、並列度だけ上げると flaky が爆発するため Iron Law とセットで適用する
- Add `e2e-record` skill / テスターの画面録画を対話形式で Playwright E2E テストに変換し、PR 作成まで行うスキルを追加。録画対象はローカル / ステージングから選べる
- Add `test-audit` skill / テスト・カバレッジ・CI の抜け漏れを3軸（テストが存在し意味を持つか / 計測と閾値の仕組みがあるか / PR で強制されるか）で監査し、レポートまたは Issue を生成するスキルを追加。判定基準を「ジョブが存在するか」ではなく**「落ちてもマージできるか」**に置き、required status check 未登録・`continue-on-error: true`・`|| true`・`--passWithNoTests`・E2E が `schedule` のみ、といったゲートの形骸化を検出する。コードと CI 設定は変更しない
- Add `kuuhaku` skill / 仕様書の1画面分を HTML に変換し、疑問への回答往復を通じて仕様の空白を検出するスキルを追加 (#4)
- Add verification gate to `impl` skills / `verify-scope.sh` をコミット前ゲート（2-6）として必須実行にし、未実装パターン / `fix` 型の回帰テスト有無 / テストと lint の exit code を機械チェックする。FAIL 時は失敗ログを develop に渡して緑になるまで再試行し、同じ FAIL が2回続いたら別アプローチを強制する。あわせて repo プロファイルを `~/.claude/cache/` にリポジトリ別キャッシュ（git common dir がキーなので worktree 間で共有）し、実装前のコンテキストパックをサブエージェントを立てず impl 自身が作成する
- Add lock and state.json lifecycle to `spec-sweep` / `report-sweep` / 両スキルは state.json も lock も作らないまま single-pr 経路で `single-branch-mode.md` の state.json 更新手順を使う建て付けで、prelude も state.json から `base_branch` を読むためガードが実質無効だった。`issue-sweep` と同じフェーズ0（多重起動チェック + 初期化）と `--abort` を追加し、対話が主体のため lock は実行フェーズ直前でのみ取得する

### 🔧 Improvements / 改善

- Extract shared sweep references into `sweep-common/` / 4つの sweep スキルが共有する `branch-preflight.md` / `single-branch-mode.md` / `notifications.md` が `issue-sweep` 配下に置かれ、他スキルから `~/.claude/skills/...` のハードコードで参照されていた。プロジェクト同梱の `.claude/skills/` に置かれると壊れるため、専用ディレクトリへ移して参照を相対パスに統一した
- Rework `refine-sweep` issue consumption into an in-flight pipeline / worktree の所有者とマージの責任者が `issue-sweep` と逆だった（同じ `.sweep/` を共有し同じ Stop Hook に監視される2スキルで前提が逆）のを、sweep 側が worktree を作りパスを埋めて渡し、agent は `/impl --auto --no-pr` → PR 作成までで返す方式に統一。メインが in-flight テーブルを持ち、ラウンド冒頭の `gh pr list` 1コールで全 PR を観測してマージする。wave バリアを廃してスロット補充方式にし、CI 待ちが実装スロットを食い潰さないようにした
- Stop auto-merging the final PR in single-pr mode / 統合ブランチからベースブランチへ出す最終 PR を sweep 側でマージせず、CI 緑を確認したら Ready to merge 通知のみ出して open のままユーザーに返すようにした。レビューとマージは人が行う。`issue-sweep` の multi-pr モードと `refine-sweep` の各 Issue agent の自動マージは従来どおり維持する
- Restructure `e2e-turbo` into feature-vertical directories / ディレクトリ構成を feature 縦割りに変更し、`.linterly.yml` があれば行数上限を spec 分割基準に反映することを明記した

### 🐛 Bug Fixes / バグ修正

- Fix shell variables assumed to persist across Bash calls / Bash ツールは呼び出しごとに新しいシェルのため、P-0 で定義した `$base_branch` / `$int_branch` / `assert_not_base` が2回目以降は空文字と未定義関数になっていた。`set -u` もないため `assert_not_base` は `cur == ""` との比較になって常に素通りし、**ベースブランチ直コミット防止というガードの存在理由が無言で失われていた**。P-0-0 で `$SWEEP_DIR/prelude.sh` を生成し、変数と関数を毎回読み直す方式に統一した
- Fix `issue-sweep` merging PRs with no CI runs / マージ条件が `waiting == 0` ∧ `failed_checks` 空 ∧ `state == OPEN` だけだったため、PR 作成直後で `statusCheckRollup` が空配列のときも成立していた。agent が PR を作った直後のラウンドで必ずここを通るため、このレースは常態だった。`checks_total ≥ 1` を条件に加え、CI を持たないリポジトリ向けに2ラウンド連続で0件なら CI 無しと判定する
- Fix `issue-sweep` PR listing dropping its own PRs / `gh pr list --state all --limit 100` は closed/merged も含むため、活動的なリポジトリでは in-flight の PR が窓から押し出され、「CI 実行中」のまま永久に残るか同じバッチを二重起動していた
- Fix spinoff detection keyed on an undefined variable / `$sweep_start_iso` の代入が参照より後にあり、その元の `$sweep_start_ts` はスキル中のどこにも代入がなかった。`created:>=` が空になり全 open Issue が返るため、spinoff 追跡が無関係な Issue を再 sweep するか0件で握り潰すかに倒れていた。`state.json` に `round_started_at` を持たせ、周回カウンタも `.round` に一本化した
- Fix spinoff count measuring string length / `${#spinoff_ids}` が改行区切り文字列の文字数を返していたため、通知の件数が実際と食い違っていた
- Fix `refine-sweep` severity mapping and threshold check / major に対応する severity ラベルが未定義で、`severity:medium` がどのバケツにも入らず `--max-minor` の勘定からも `critical/major == 0` の判定からも漏れていた。critical = `severity:critical` / major = `severity:high` / minor = それ以外、という対応表をフェーズ1に置いて唯一の定義とした
- Fix `refine-sweep` state.json schema diverging from `issue-sweep` / 同じ見出しで「sweep 系スキル共通の進行状態ファイル」を宣言しているのに、片方が廃止した `evidence` / `last_counts` をもう片方が持ち、空なら次フェーズへ進むことを禁止行動にしていた。証跡を `refine-metrics.jsonl` 一本に統一した
- Fix `refine-sweep` referring to `.sweep/` by relative path / `issue-sweep` が29箇所すべてで `$SWEEP_DIR` を使うのに対し `refine-sweep` は全て相対パスで、メインスレッドが cwd を動かすと別の場所を見ていた
- Fix `sweep_notify` reading `.sweep/` by relative path / cwd が worktree のとき通知が無言で no-op になっていた（`|| return 0` のため気づけない）
- Fix `spec-sweep` / `report-sweep` leaving the lock behind / エラー時の再開可否ヒアリングと完了報告の経路で terminal 化と lock 削除が抜けており、Stop Hook に押し戻されて質問できなくなるか、次回起動が「他 sweep 実行中」で弾かれていた
- Fix `spec-sweep` 1-2 exceeding the 4-question limit / 「1項目1質問に厳守」と書きながら5項目を聞いていた。項目間の話である依存関係を、全項目名が揃う 1-1 へ移した
- Fix `report-sweep` double approval / 1-3「計画確定」とフェーズ2「一括承認」がどちらも 提示 → `AskUserQuestion` → `TaskCreate` をしており、一括承認を選んでいても同じ承認を2度求めていた
- Fix `report-sweep` not referencing its bundled templates / `templates/bug.md` / `feature.md` が存在するのに 3-4 にパスの記載がなく、Claude がテンプレを読まず自前で本文を書いていた。起票経路によって Issue の形が変わると後段の `/bug-fix` `/impl` が読み取れなくなる
- Fix sweep-common references pointing at non-existent phase numbers / reference は必要なときだけ読む設計のため、読んだ側が存在しない手順を探しに戻っていた。番号参照をイベント名に置き換え、番号は本体だけが持つようにした
- Fix `issue-sweep` metrics using a singular `skill` field / agent は `skills` 配列を返すのにスキーマは単数で変換規則がなく、先頭1つに潰すと `bug-fix` と `impl` が混在したバッチの集計が壊れていた

### 📝 Documentation / ドキュメント

- Trim sweep prohibition lists to non-obvious traps / 「実測で1セッション1万往復」が4箇所、「諦めたらキューから消す」が7箇所に全文で重複し、禁止行動の大半が本文の手順の言い換えになっていた。「手順どおりに読んでも踏みうる罠」だけに絞り、`issue-sweep` 45 → 30行、`refine-sweep` 33 → 22行に削減
- Document `--parallel` as decrease-only / デフォルト5・上限5で実質下げることしかできないのに「上限」と書かれ上げられるように読めていた。あわせて `parallel` / `max_inflight` を state.json に持たせ、判定式が実際の値を指すようにした
- Document the GNU coreutils requirement / `date -u -d @ts` と `timeout` は GNU 依存で macOS では動かないのに、24h 前の算出だけ BSD フォールバックがあるという中途半端な状態だった。前提条件に明記し、中途半端なフォールバックは削除した

## [v0.10.0] - 2026-09-03

sweep 系スキルの研磨タイミングを見直し、Stop Hook との往復で context を浪費していた問題を塞いだリリース。single-pr モードでは作業単位ごとに `refine-git` を回していたが、同じ指摘が作業単位の数だけ重複検出されるうえ、バッチ間の重複・不整合は誰も検出できていなかったため、統合ブランチにすべて積んだ後にまとめて 1 回研磨する方式に変更した。

### 🐛 Bug Fixes / バグ修正

- Fix context burned by Stop Hook round-trips / CI 待ちなどで「待機。」と言ってターンを終える待ち方をすると Stop Hook に押し戻され、1 往復ごとにモデルのターンを 1 回消費していた。過去セッションの実測でブロック 10,946 回（33,120 行中 1/3、2〜3 秒間隔）、フック文言だけでトランスクリプトの 5〜12% を占めていた。待機は 1 つの bash コマンド内で `sleep` を挟んでブロックするよう全 sweep 系スキルに明記した
- Fix duplicated Stop Hook output / `check-issue-queue.sh` と `check-sweep-state.sh` が同じ状況で同じ内容を二重に出力していたのをやめ、`queue.txt` が非空の場面では後者を無言で exit 0 にした
- Fix dead fields printed by `check-sweep-state.sh` / スキーマに存在しない `.iteration`（実際は `round`）と廃止済みの `.last_counts` を毎回出力していたのを削除。issue-sweep の 1 停止あたりのフック出力を 500 → 141 文字に削減

### 🔧 Improvements / 改善

- Move polishing after integration in single-pr mode / 作業単位ごとの `/refine-git` 起動を廃止し、統合ブランチの全差分に対して 1 回だけ研磨するフェーズ S-2-0 を新設。作業単位のマージゲートはテストと lint の通過に変更し、統合研磨で critical/major が残った場合は PR を作るがマージせず人に返す。統合差分は 1 作業単位より大きいため `--max-iter` を 2 → 3 に引き上げた
- Specify blocking CI wait explicitly / 「`gh pr view` を 60 秒間隔で観測」という手段未指定の記述を、`timeout` + `while` + `sleep` で 1 コマンド内にブロックする具体コードへ差し替え（`single-branch-mode.md` S-2-2 / `refine-sweep` の engineer agent）

## [v0.9.0] - 2026-09-01

Playwright で実際にレンダリングした画面のスクリーンショットを見てレビューする `visual-review` スキルを追加したリリース。コードの静的解析（`design-review`）やモックとのコード比較（`mock-drift`）では検出できない、実描画での崩れ・重なり・コントラスト不足を対象にする。HALT（HTMX + Templ + Lit）のようなサーバー内蔵型構成にも対応する。

### ✨ New Features / 新機能

- Add `visual-review` skill / Playwright で画面を実描画してスクリーンショットを撮影し、**デザイン品質・モック乖離・仕様乖離**の3観点をレビューするスキルを追加。`design-review`（コードの静的解析）と `mock-drift`（モック↔実装のコード比較）に対し、「ブラウザで実際にどう見えるか」だけに責務を限定する (#10)
- Add cross-source drift detection / 収集元6種（設定ファイル / Storybook / クライアントルーティング / サーバーサイドルーティング / 仕様書の画面一覧 / モック）を突き合わせ、未実装・仕様未記載・モック未整備・モック取り残し・story 欠落・到達不能を検出する (#10)
- Add visual mock comparison / HTML モックを実装と同じビューポートで撮影して画像同士を並べて比較する。画像カンプはそのまま読み込み、Markdown モックは本文と実描画を照合する (#10)
- Support HALT / HTMX / Web Components / `HX-Request` 付きで取得した部分 HTML をラッパーに埋め込んで撮る**フラグメント撮影**（Storybook が無い構成でのコンポーネント単体レビュー手段）、HTMX のスワップ完了と `customElements.whenDefined()` + `updateComplete` の待機、shadow DOM を貫通する動的要素の隠蔽、`static/dist/` 等のビルド成果物の鮮度確認を実装。待機が無いとカスタム要素が空のまま撮影され、デザイン欠陥として誤報告される (#10)
- Add server-side route collection / Gin / Echo / chi、Rails、Laravel、Django のルート定義から撮影対象を収集する。GET のページルートのみを対象とし、API ルートと**副作用のあるアクションルート（POST / PUT / DELETE）は撮影しない** (#10)
- Add staged image loading to cap token usage / 画像1枚あたり約 1.5k トークンを消費するため、撮影は一括・レビューは段階的読み込み（desktop×light 全件 → モック照合 → 問題があった画面のみ mobile → dark → tablet）を規定。全件読み込みは `--full` 明示時のみ。縦長ページはビューポート単位に自動スライスし、1枚が巨大画像になるのを防ぐ (#10)

## [v0.8.0] - 2026-09-01

sweep 系スキル（`issue-sweep` / `refine-sweep` / `spec-sweep` / `report-sweep`）が作業ブランチを作らないままベースブランチへ直接コミットする事故と、ベースブランチをユーザーに確認せず現在の HEAD を推測で採用する事故を塞いだリリース。

### 🐛 Bug Fixes / バグ修正

- Fix sweep skills committing directly onto the base branch / worktree や作業ブランチの作成に失敗したとき、メインリポジトリでそのまま実装を続けて `develop` / `main` に直接コミットしてしまう経路を塞いだ。作成に失敗した作業単位は諦めて failure を返す
- Fix base branch inferred from the current HEAD / `git branch --show-current` の結果や `develop` を推測でベースブランチに採用していたのをやめ、フェーズ P-0 の選択式ヒアリングで必ず確定させるようにした
- Fix `mode` / `base_branch` wiped by state.json init / `issue-sweep` のフェーズ1-6 が state.json を丸ごと上書きし、P-0 で確定したモードとベースブランチを消していた問題を修正

### ✨ New Features / 新機能

- Add branch preflight phase to sweep skills / 共有 reference `issue-sweep/references/branch-preflight.md` を追加。lock 取得の直後・キュー構築の前に走る**スキップ不可**のフェーズ P-0 で、PR モード（1 PR に集約 / 作業単位ごとに PR）とベースブランチを `AskUserQuestion` で 1 回にまとめて聞く。決定は state.json の `mode` に持たせ、以降のフェーズ分岐の唯一の根拠にする
- Add `assert_not_base` pre-guard / 保護ブランチ（`main` / `master` / `develop` / `staging` / `production`）と `$int_branch` を検査する事前ガードを追加。統合ブランチ作成の直後、統合 merge の直前、`feat/#N` 作成の直後、実装 agent の worktree 作成の直後と初回コミット前に呼ぶ。**事後検知や `git reset` による自動退避はしない**（引っかかったら人に返す）
- Add `--multi-pr` to sweep skills / 作業単位ごとに PR を作る従来モードを明示するフラグを 4 スキルに追加。`--single-pr` と `--base` を含め、指定がなければ P-0 で必ず聞く

### 🔧 Improvements / 改善

- Consolidate base branch selection into P-0 / `single-branch-mode.md` の S-0-1（ベースブランチ確定）を P-0 へ移譲し、同じヒアリング手順が 2 箇所にあった重複を解消。S-0 は統合ブランチの作成だけを担う

## [v0.7.0] - 2026-08-31

Slidev 資料の生成・レビュー用スキル（`slide-gen` / `slide-review`）の追加と、sweep 系スキルの「1 統合ブランチ → 1 PR」集約モードを中心にしたリリース。意匠まわりは配色・スタイルを CSS トークンへ切り出し、コントラストと装飾方針を機械検査できるようにした。

### ✨ New Features / 新機能

- Add `slide-gen` skill / 仕様書などのドキュメントから `slide/` に Slidev のビジュアル資料を生成する `slide-gen` を追加。テンプレート（`slides.md` / `visual.css` / Makefile / wrangler.toml）と検査スクリプト一式を同梱する
- Add `slide-review` skill / Slidev のスライドをレビューし、指摘を 1 件ずつ確認しながら修正する `slide-review` を追加。デザインモードは「機械 + 目視」で、目視の前にコントラストを実測する
- Add `--single-pr` aggregation mode to sweep skills / `issue-sweep` / `refine-sweep` / `spec-sweep` / `report-sweep` に 1 統合ブランチ集約モードを追加。作業単位ごとに PR を作らず、最初に切った統合ブランチ 1 本へ全部積み、最後にベースブランチへ PR を 1 本だけ出す。ベースブランチは `--base <branch>` か開始時の選択式ヒアリングで必ず確定させる（推測で `develop` / `main` を採らない）。手順は共有 reference `issue-sweep/references/single-branch-mode.md` に集約し、各 SKILL.md には差分表を 1 ブロックだけ置いた
- Add `--base-ref <ref>` to `refine-git` / 差分の比較先を明示指定するフラグを追加。集約モードで統合ブランチ基準の差分をレビューさせるための必須プラミングで、明示指定時は `origin/main` へ fallback せずエラーにする
- Add style presets to `slide-gen` / 角丸・カードの地/枠/影・見出しの太さと字間・kicker の横線などを `:root` の意匠トークンへ切り出し、Editorial（既定）/ Soft / Minimal の 3 プリセットを追加。スタイルと配色を独立して選べるようにした
- Add `derive-palette.mjs` / プライマリカラー 1 色から配色トークンを導出するスクリプトを追加。light / dark 双方で本文 4.5:1・構造色 3:1 を満たすまで明度を自動調整し、実測値を出力する
- Add `check-contrast.mjs` / `visual.css` の `:root` から文字色と背景色の組み合わせを実測する検査を追加。`var()` 参照を解決し複数の `:root` を後勝ちで畳むため、プリセットを末尾に追記した状態でも測れる
- Add `check-style.mjs` / グラデーション塗り・光彩・すりガラス・文字の影・絵文字アイコン・ページ内アニメーション・インラインスタイル・色の直書きを機械検出する検査を追加。セレクタを追跡し、画像上の減光など機能的なオーバーレイは通す

### 🐛 Bug Fixes / バグ修正

- Fix dark text tokens scattered across 6 values / dark 背景のテキスト色が 6 段階に散らばっていたのを 3 トークンへ集約
- Fix self-referencing `--v-card-border` / 自己参照になっており既定スタイルでカードの枠線が消えていた問題を修正
- Fix footer contrast below threshold / フッターの色が直書きでコントラストが 2.43:1 と基準未満だった問題を修正
- Fix footer placeholder colliding with Vue interpolation / `global-bottom.vue` のプレースホルダを `___ORG_NAME___` に変更。`{{ORG_NAME}}` は Vue の補間構文と衝突し、置換し忘れてもエラーにならずフッターが空になっていた
- Fix `h2` demoted from title / `h2` をタイトルに戻し、`slide-gen` の入力受け渡しを拡張

### 🔧 Improvements / 改善

- Split `:root` into palette and design blocks / `:root` を配色用と意匠用の 2 ブロックに分け、プリセットの差し替えが互いを壊さないようにした
- Ban decoration-only expression / 情報を 1 つも足さないのに資料を安く見せる装飾を禁止し、機械検査でガードするようにした。例外は画像の上に文字を載せるための減光と破線などのパターンのみ
- Require meaning for emphasis / 意味のない強調を禁止。`.accent` は既定で使わず、付ける理由を presenter note に書けないなら外す。カードの色は区切りの構造であって情報ではないため、カードごとに色を変えない
- Define logo placement / ロゴの置き場所を表紙・フッター・締めの 3 つに定め、dark 背景では白抜き版が要る点を手順に含めた。レビュー観点にも「dark 背景でロゴが沈む」「扱いが不統一 / 主張しすぎ」を追加
- Align `slide-gen` visual checklist with `slide-review` / `slide-gen` の目視チェックリストを強調・装飾の方針に揃えた

### 🏗️ Infrastructure / インフラ

- Make `slide-gen` build web-only / `build` は Cloudflare Workers で配信する静的サイトだけを作るようにし、PDF / PNG 出力を Makefile のターゲットへ分離。Chromium に依存しなくなり Workers Builds でそのまま通る
- Add `make contrast` / コントラスト実測を Makefile のターゲットとして追加

## [v0.6.0] - 2026-08-22

自律実行フロー（`issue-sweep` → `impl` → `refine-git`）の収束性とスループットの作り直しを中心にしたリリース。あわせて `refine` の差分版分離、`spec-audit-git` / `mock-drift` の追加、herdr の導入、install/update スクリプトのツール単位分割を含む。

### ⚠️ Breaking Changes / 破壊的変更

- Split `refine` into `refine` (whole repo) and `refine-git` (diff only) / `refine` を「リポジトリ全体対象」と「PR 差分対象」に分割。`impl` / `impl-wt` / `issue-sweep` が作った PR の研磨は `refine-git` の担当になり、`refine` を機能 PR に使うとスコープが膨張して閾値に到達しなくなる
- Rename `impl-type-r` / `impl-type-wr` to `impl-r` / `impl-wt-r` / `impl-type-r` / `impl-type-wr` を `impl-r` / `impl-wt-r` に改名。旧名では起動できない
- Require explicit `--no-pr` for PR-less sub-skill runs / `impl` / `bug-fix` / `design-fix` の PR 作成スキップを「呼び出し元が明示指示すれば可」という運用から `--no-pr` フラグ必須に変更
- Unify `refine` status vocabulary / `refine` 系の終了 status を `clean` / `iter_limit` / `no_progress` / `agent_failed` / `merge_failed` / `ci_gave_up` の enum に統一（`stuck` 等の独自文字列を廃止）。status を parse する呼び出し元に影響する
- Drop `evidence` from `.sweep/state.json` and `issue` from metrics / `.sweep/state.json` の `evidence` 配列と null 固定だった `last_counts`、`metrics.jsonl` の後方互換 `issue` フィールドを廃止（`issues[0]` で代替）

### ✨ New Features / 新機能

- Add `--auto` autonomous mode to `impl` / `bug-fix` / `design-fix` / 自律実行モード `--auto` を追加。assignee 確認・不足情報のヒアリング・不確定仕様の確認・破壊的変更の確認で停止せず、採用した前提を PR 本文に列挙して進む。Review フェーズは後段の `refine-git` に委ねる（テスト・Format & Lint・Commit・回帰テスト・デザイン検証の省略は禁止のまま）
- Add `--skip-minor` to `refine-git` / minor 指摘を閾値判定と修正対象から外すフラグを追加。`issue-sweep` からの呼び出しは常にこれを渡す
- Add `--max-inflight` to `issue-sweep` / 同時に抱える未マージ PR 数の上限を `--parallel`（実装同時数）から分離
- Add batch implementation to `issue-sweep` / 関連 Issue を 1 worktree / 1 ブランチ / 1 PR にまとめて実装するバッチモードを追加
- Add `spec-audit-git` skill / 差分スコープで仕様乖離・TODO・スキップテストを検知する `spec-audit-git` を追加
- Add `mock-drift` skill / モックと実装の乖離をコンポーネント単位でチェックする `mock-drift` を追加
- Add herdr integration / herdr をインストール対象に追加し、tmux 準拠キーバインドと Claude Code 連携フックを導入
- Add copilot fish completions / GitHub Copilot CLI の fish 補完を追加
- Add `f` / `fc` fish aliases / fugu 起動・再開用の `f` / `fc` エイリアスを追加
- Assign self on start in `impl` / `bug-fix` / 着手時に Issue の assignee へ自分を追加する挙動を追加
- Add `unzip` / `jq` to `install_packages` / インストール対象パッケージに `unzip` と `jq` を追加

### 🐛 Bug Fixes / バグ修正

- Fix non-converging refine loop caused by doc/spec findings / `doc-drift-git` / `spec-audit-git` の指摘は本質的に差分外のドキュメント修正を要求するのに、fix agent が差分内ファイルしか編集できず `out_of_scope_required` で必ず失敗していた問題を修正。`docs/**` / `*.md` / 仕様書は差分外でも編集可にし、修正に差分外の非ドキュメントファイルが必要な指摘は `out_of_scope` に分類する
- Fix unbounded improvement loop in `impl` / `impl` の改善サイクルが「指摘なしまで繰り返す」で上限なしだった問題を修正（上限 3 周、残指摘は PR 本文の「## 残課題」に列挙）
- Fix unreachable CI failure handling in `issue-sweep` / bash の `while` ループ内から `Agent` ツールを呼ぶ実行不能な擬似コードになっており、CI 失敗を検知しても何も起きずに待機が続く問題を修正。状態取得（bash）と判定・agent 再起動（LLM）を分離
- Fix `.sweep/` splitting between worktree and main repo / `.sweep/` を `CLAUDE_PROJECT_DIR` 固定にし、worktree 削除で `refine-metrics.jsonl` と `spinoff-draft.jsonl` が消えていた問題を修正
- Fix `refine-git` silently terminating the caller's sweep / `refine-git` が `issue-sweep` と同じ `state.json` を上書きして `phase=terminal` にし、Stop Hook のブロックが解除されて sweep がキュー途中で終わる経路を所有権ガードで封じた
- Fix Atomic Design guard aborting entire sweeps / フロントエンドで Atomic Design 構造が検出できないと `refine-git` が起動直後に `exit 2` し、全 Issue のマージゲートが落ちていた問題を修正（sweep 経由では警告に降格）
- Fix infinite batch retry across sessions / バッチの試行回数がメモリ上のみで、セッションを張り直すと同じバッチを無限に再試行していた問題を `attempts.json` への永続化で修正（上限 2 回）
- Fix sweep unable to terminate after giving up / 諦めたバッチ / PR をキューに残していたため Stop Hook が停止をブロックし続ける問題を修正。失敗打ち切り時も terminal 化とレポート生成を行う
- Fix `agent-skills` install aborting mid-run / `install_agent_skills` の中断を修正し、MCP 登録の失敗理由を表示するようにした
- Fix Node LTS install ordering / Node LTS のインストールを node 製 CLI より前に移動
- Fix tmux clipboard handling / tmux のクリップボードを OSC 52 送出に一本化（passthrough 有効化を含む）
- Fix `set_default_shell` reliability / `chsh` の反映検証と sudo フォールバックを追加
- Fix Stop hook path resolution / Stop hook のパスを `$HOME` 側に切り替え、未セットアップのプロジェクトでの not found を解消
- Fix `refine-sweep` engineer prompt / merge + Issue close を明示的に指示するよう修正
- Fix herdr split keybindings / herdr の split バインドを tmux 既定の `"` / `%` に統一
- Fix fugu resume alias / fugu 再開エイリアスを修正
- Fix nvim checkhealth warnings / nvim の checkhealth warning を整理
- Fix invalid permission rule / 無効な `Write(.sweep/**)` 許可ルールを削除
- Fix shellcheck warnings / shellcheck の warning 指摘を解消

### 🔧 Improvements / 改善

- Rebuild `issue-sweep` phase 2 as an in-flight pipeline / 「実装 N 件 → 全 PR の CI 待ち → また N 件」というバリアを撤去し、スロットが空いた瞬間に次のバッチを起動する方式に変更。CI 時間が実装 agent 0 本の空白にならない
- Cut review iterations in `refine-git` / 2 周目以降は前回 critical/major を出した観点のみ再走、`doc-drift-git` / `spec-audit-git` はドキュメントを触った反復のみ、`--no-merge` 時の最終 re-review を廃止。`issue-sweep` からは `--max-iter 2` を渡す。1 PR あたりのレビュー agent 起動数が最悪ケースで約 45〜65 本から約 6〜9 本になる
- Collapse duplicate Issue body reads in `issue-sweep` / 依存判定・分割判定・スコープ読み取りで Issue 本文を 3 回読んでいたのを「1 Issue = 1 agent = 1 パス」の解析に統合
- Remove `gh` N+1 calls / 親 Issue 展開を 1 コールに、PR の冪等性チェックと状態判定を 1 回の PR 一覧取得に統合。ラウンドあたりの `gh` 呼び出しが in-flight 本数に比例しなくなった
- Unify batch scope calculation / 「disjoint なら並列」と「重なるならバッチ」の逆向きの二重判定をやめ、バッチ編成 1 箇所に統合（同じバッチ = 直列、別のバッチ = 並列）
- Unify `issue-sweep` launch prompt / 1 件用とバッチ用に分裂していた起動プロンプトを 1 本に統合し、worktree は常に sweep 側が作る形にした（worktree の before/after スナップショット差分が不要になった）
- Lighten `Plan` for scoped Issues / `--auto` 時、Issue 本文にスコープ記載があれば `Plan` エージェントを起動せずその記載を実装計画として使う。仕様書探索も worktree ごと 1 回に
- Cap `issue-split-auto` fan-out / Issue 数ぶん同時起動していた分割判定を 5 件ずつのウェーブに制限
- Redesign `refine-sweep` around Issue-driven `impl-wt` / `refine-sweep` を Issue 化 → `impl-wt` で消化するフローに再設計
- Consolidate spinoff issue creation / スコープ外発見の起票をフェーズ3 の `--batch` 1 回に集約し、`issue-sweep` の spinoff 追跡既定を 1 周に絞った
- Change `issue-sweep` split judgment to content-based / 文字数や H2 数のような表層メトリクスによる事前フィルタをやめ、本文と関連仕様書を読んで判定する形に変更
- Remove external taste-skill and trim `issue-sweep` / 外部 taste-skill を除去し `issue-sweep` の冗長な記述を削減
- Split install/update scripts per tool / install / update スクリプトをツール単位に分割し、common ヘルパーも責務単位に分割
- Improve dotfiles update flow / dotfiles 更新処理を改善
- Track copilot CLI options / copilot の fish 補完を最新の CLI オプションに追随
- Revert verbose MCP registration logging / MCP 登録失敗時の詳細ログを削除

### 📝 Documentation / ドキュメント

- Add MIT LICENSE and CONTRIBUTING.md / MIT LICENSE と CONTRIBUTING.md を追加
- Add PR / Issue templates / PR / Issue テンプレートを追加
- Add license and contribution links to README / README にライセンスとコントリビューションの導線を追加

### 🏗️ Infrastructure / インフラ

- Add PR syntax checks / PR 向けに shellcheck / fish / JSON の構文チェックを追加
- Bump `actions/checkout` to v5 / `actions/checkout` を v5 に更新
- Ignore runtime artifacts / ランタイム生成物と marketplace 導入 skill を gitignore に追加

## [v0.5.0] - 2026-07-08

Atomic Design レビューの導入、sweep 系スキルの UX 統一、外部 agent-skills のマニフェスト化、Codex 環境整備を中心にしたリリース。

### ✨ New Features / 新機能

- Add `atomic-review` skill for Atomic Design compliance / Atomic Design 準拠レビュー用 `atomic-review` スキルを Claude / Codex 両方に追加。Next.js / Nuxt v3・v4 / 素の React / 素の Vue を自動判定し、依存方向・配置妥当性・layout 使用・命名・prop drilling・FW 固有ルール（'use client' 境界、Nuxt auto-import、v3→v4 srcDir 差異）をチェック
- Enforce Atomic Design in refine for frontend projects / `refine` / `refine-sweep` のフェーズ 1 に HAS_ATOMIC 検知と `atomic-review` 並列起動を追加。フロントエンド (react/vue/next/nuxt) かつ Atomic 未採用の場合は `termination_reason=atomic_design_required` で中断
- Add `impl-type-r` / `impl-type-wr` skills / `impl → refine` を連続実行し、実装から研磨・CI 緑マージまで一気通貫するスキルを追加（`impl-type-wr` は worktree 隔離版）
- Add `report-sweep` skill / 機能要望とバグ報告を一括ヒアリングし、バグは Issue のみ・機能要望は Issue+ブランチ+`spec-gen` 実行まで走らせる `report-sweep` スキルを追加
- Add `spec-sweep` skill / 複数仕様追加を事前計画で一括ヒアリングし、Issue/ブランチごとに `spec-gen` を順次実行する `spec-sweep` スキルを追加
- Add manifest-based external agent-skills management / 外部 agent-skills をマニフェスト方式（`agent-skills.txt`）で管理する仕組みと `install_agent_skills` を追加
- Add `sync_codex_mcp` helper / Claude の MCP 設定 (`claude-mcp/mcp.json`) を Codex 用 (`~/.codex/config.toml`) に同期する `sync_codex_mcp` を install.sh に追加
- Add global `.codex/AGENTS.md` / Codex 用グローバル指示ファイル `.codex/AGENTS.md` を追加し `install.sh` で `~/.codex/AGENTS.md` に symlink

### 🐛 Bug Fixes / バグ修正

- Fix agent-skills conflict guard to follow symlinks / `install_agent_skills` の Codex 側衝突ガードを symlink 先で判定する形に修正し、既存 symlink スキルとの誤検知を回避
- Fix supabase MCP env loading / supabase MCP の env を sh ラッパー経由で `~/.env` から読む形に変更し、Claude Code / Codex 起動時に env が抜ける問題を修正

### 🔧 Improvements / 改善

- Unify sweep skills on upfront hearing / sweep 系スキル（`issue-sweep` / `refine-sweep` / `report-sweep` / `spec-sweep`）を「初回一括ヒアリング＋以降割り込みなし」の UX に統一
- Extend report-sweep to run spec-gen for feature requests / `report-sweep` の機能要望フローを Issue 作成だけでなく `spec-gen` 実行まで走らせる形に拡張
- Bump supabase MCP 0.5.10 → 0.8.2 / supabase MCP を 0.5.10 から 0.8.2 にバンプ
- Loosen issue-sweep split-from sequential rule / `issue-sweep` の split-from sequential ルールを、並列セーフな条件を満たす場合に限り上書き可能に緩和

### 📝 Documentation / ドキュメント

- Update README with Fugu / Codex skills / partial install / fish aliases / README に Fugu、Codex 用スキル、`./install.sh <name>` 個別実行、fish エイリアス (`x` / `fugu`) の説明を追記
- Trim redundant intros / `SKILL.md` / `AGENTS.md` 冒頭の冗長な紹介文を削除して本題からすぐ読めるように整理

### 🏗️ Infrastructure / インフラ

- Ignore runtime state and plugin lock files / `.sweep/` などのランタイム状態ファイル、`fish_plugins.lock` などのプラグインロックファイルを `.gitignore` に追加

## [v0.4.0] - 2026-06-25

Claude Code 用に育てたスキル一式を Codex CLI / Fugu からも使えるように移植したリリース。

### ✨ New Features / 新機能

- Port 35 Claude skills to Codex CLI format / `~/dotfiles/.claude/skills/` 配下のスキル 35 件（`bug-fix` / `impl` / `refine` / `issue-sweep` / `spec-gen` / `release` 等）を Codex CLI 用フォーマット (frontmatter は `name` / `description` のみ、本文は harness 非依存の自然言語) で `~/dotfiles/.codex/skills/` に再構成。Codex / Fugu でも同じワークフローを呼び出し可能に
- Add `link_codex_skills` helper to install.sh / `lib/common.sh` に `link_codex_skills` を追加し、`install.sh` の `main` から呼んで `~/dotfiles/.codex/skills/<name>` → `~/.codex/skills/<name>` の symlink を idempotent に作成。Codex 公式バンドル (`.system/` 配下) は除外
- Naturalize Claude-specific tool vocabulary / `AskUserQuestion` / `TaskCreate` / `Agent(subagent_type=...)` / `Skill()` / `WebFetch` 等の Claude 固有ツール参照を「選択式で確認」「進捗を管理」「サブエージェントを起動して並列実行」のような harness 非依存表現に置換
- Preserve auxiliary resources verbatim / `templates/` / `references/` / `scripts/` などの補助ファイルは harness 非依存のためそのままコピー（spec-to-hugo の Hugo / Cloudflare Worker テンプレ群、halt-review のチェック基準集、code-review の観点別 references など含む）

## [v0.3.0] - 2026-06-25

Fugu (Sakana AI の Codex 設定バンドル) の install パイプライン統合と、sweep / refine 系スキルの安定化リリース。

### ✨ New Features / 新機能

- Add `install_fugu` to install.sh / `curl -fsSL https://sakana.ai/fugu/install | bash` を install パイプラインに統合。`~/.env` の `SAKANA_API_KEY` を拾えれば非対話で導入、無ければ warn してスキップ
- Add `./install.sh <name>` partial-run mode / 引数指定で個別 `install_*` 関数だけ走らせるモードを追加。全体セットアップを通さず 1 ツールだけ入れ直せる
- Add `make fugu` target / Fugu だけ単独でインストールするための Makefile ターゲットを追加
- Add fish aliases `x` / `fugu` / fish に `codex` / `codex-fugu` を `--dangerously-bypass-approvals-and-sandbox` 付きで叩く `x` / `fugu` エイリアスを追加（Claude の `c` と同じ感覚で起動）
- Add `SAKANA_API_KEY` to `.env.example` / `.env.example` に `SAKANA_API_KEY` のコメント例を追加
- Track all open issues for spinoff in refine-sweep / `/refine-sweep` の 3-0 を spinoff 限定から全 open Issue 追跡に拡張し、残 Issue を `/issue-sweep` へ自動委譲（`impl-wt` 直接起動に変更）
- Add hard_cap and double-confirm review in refine-sweep / `/refine-sweep` に hard_cap と double-confirm review を追加して暴走を抑制
- Add allow_auto_merge preflight and direct merge mode / sweep 系スキルに allow_auto_merge の preflight と direct merge モードを追加
- Auto-continue spinoff tracking until queue empty / sweep の spinoff 追跡を全 Issue 消費するまで自動継続するデフォルトに変更
- Add `.sweep/state.json` and Stop Hook terminal enforcement / sweep 系スキルに `.sweep/state.json` と Stop Hook による terminal 強制を追加

### 🐛 Bug Fixes / バグ修正

- Fix spinoff detection in sweep / sweep の spinoff 検出を `spinoff-issue` 出力に合わせて修正
- Fix fix_ineffective judgement in refine-sweep / `/refine-sweep` の fix_ineffective 判定を件数比較から fingerprint set 比較に変更（同件数でも fingerprint が変わっていれば前進とみなす）

### 🔧 Improvements / 改善

- Unify sweep skills on direct merge / sweep 系スキルを direct merge 一本化（auto-merge を廃止）
- Drop `--max-iter` soft cap in refine-sweep / `/refine-sweep` の周回数ソフト上限 `--max-iter` を廃止し hard_cap に集約
- Switch global gitignore to symlink-based / global gitignore を cp ベースから symlink (`~/.gitignore`) ベースに変更
- Move global gitignore setup to install time / SessionStart hook 方式をやめて dotfiles install 時に global gitignore を設定する方式へ
- Raise refine-sweep `max_minor` default to 5 / `/refine-sweep` の `max_minor` デフォルトを 0 → 5 に変更（`/refine` / `/issue-sweep` と揃える）

## [v0.2.0] - 2026-06-21

`/issue-sweep` / `/refine` / `/refine-sweep` の三点セットを中心とした **自律 Sweep & Refine ワークフロー** の追加。

### ✨ New Features / 新機能

- Add `/issue-sweep` skill for autonomous Issue-to-merge loop / 複数 OPEN Issue をキュー化し Stop Hook と連動して自律的に実装→auto-merge→Issue close まで進める司令塔スキルを追加
- Add `/refine` skill for iterative review-fix-merge polishing / review→修正→再 review を回して critical/major=0 ∧ minor≤閾値 まで PR を磨き上げ auto-merge と Issue close まで実行するスキルを追加
- Add `/refine-sweep` skill for repo-wide continuous polishing / リポジトリ全体に対して 4 観点 review→fix→PR→auto-merge を反復し critical/major=0 まで持っていく全体版 refine を追加
- Add `/issue-split-auto` for non-interactive Issue splitting / 大型 Issue を自律的にサブ Issue へ分割する非対話版スキルを追加（issue-sweep のフェーズ1 から呼ばれる）
- Add Stop Hook + SessionStart Hook for sweep continuity / `.sweep/queue.txt` 残時に停止をブロックする Stop Hook と、セッション開始時にオープン Issue 一覧を注入する SessionStart Hook を追加
- Parallel processing with `--parallel N` / 独立 Issue を最大 5 並列で処理する並列モードを追加
- 4-perspective parallel review / 各反復で `/code-review` / `/doc-drift` / `/spec-audit`（HALT 検知時は `/halt-review`）を並列起動して findings を集約
- Domain-staged parallel PRs in refine-sweep / 仕様書からドメイン一覧（frontend / backend / db / ci 等）を抽出し各反復でドメインごとに別 PR を並列起動、db → backend/frontend/ci の依存ウェーブで実行
- Spinoff Issue auto-tracking / sweep 開始後に作成された Parent ラベル/本文を持つ Issue を spinoff として検出、デフォルト 2 周まで自動再 sweep（`--max-rounds N` で制御、最大 5）
- refine-sweep auto-delegates spinoffs to issue-sweep / refine-sweep のフェーズ3 で spinoff を検出し `Agent(claude)` 経由で `/issue-sweep` を自動起動して実装まで委譲
- Heartbeat-based stale lock recovery / `.sweep/lock` の鮮度判定（2h）で stale を救済し誤ブロックを防止
- Telemetry to `.sweep/metrics.jsonl` and `.sweep/refine-metrics.jsonl` / 各 Issue / 反復の処理結果を JSON 1 行追記
- Project-scoped webhook notifications / `.sweep/notify.url` で Slack / Discord / ntfy.sh を URL パターンから自動判別して通知
- Auto-generated Markdown reports / フェーズ3 終了時に `.sweep/report-{sweep,refine,refine-sweep}-<ts>.md` を自動生成
- Worktree-isolated execution / 各 Issue を独立 worktree で実行、起動前後に差分検知して orphan を毎反復削除、フェーズ3 完了時に `git worktree prune`
- HALT project auto-detection / `*.templ` ファイル存在または仕様書の HALT 記述で自動検知し `/halt-review` を追加
- Parent issue auto-expansion / `/issue-sweep #<parent>` 指定時、`split-from:#<parent>` ラベル付き子 Issue を持つなら子に展開してそのフェーズだけ実装
- Merge gate via refine results / refine 結果を見て critical/major 残ありなら auto-merge を予約せず failure として手動対応へ falls back

### 🔧 Improvements / 改善

- Move sweep runtime state from `.claude/` to `.sweep/` / Claude Code の sensitive-file ガード回避のため sweep 系のキュー・lock・テレメトリを `.sweep/` ディレクトリに移動
- Refresh base branch on each Issue / 各 Issue 着手前に base branch を最新化し、直前のマージ分を取り込んでから次の修正を始める
- Auto-sequential for dangerous cases / 並列度はユーザー確認せず、危険ケースのみ自動で sequential 化
- Enforce CTO discipline in refine-sweep engineer agent / fix → PR → CI 待ちを engineer agent 内に閉じ込めメインスレッドはオーケストレーションに専念
- Set `defaultMode` to `bypassPermissions` for unattended operation / 完全無人化のため defaultMode を bypassPermissions に変更し Skill 許可漏れを補填
- Specify gh/git subcommand-level permission patterns / 許可パターンを具体化（gh/git のサブコマンド単位 + `.claude/` への書き込み）
- Expand `permissions.allow` for sweep operations / `gh pr/issue/run/api/label/workflow/repo/release/auth`, `git status/log/diff/branch/checkout/switch/fetch/pull/push/add/commit/merge/worktree/remote/stash/rev-parse/ls-files/config --local`, POSIX 各種, `curl`, `mkdir/cp/mv/test/kill -0/ps` を事前承認
- Allow `Write/Edit/Read(.sweep/**)` / sweep ランタイムの書き込みを一括許可

### 🐛 Bug Fixes / バグ修正

- Ensure `/refine` always runs inside a worktree / `/refine` も常に worktree 内で動作することを明示
- Move `/refine` from git-diff version to full version / `/refine` を git 版から通常版に切り替え、issue-sweep にも refine を統合

### File layout

| パス | 役割 |
|---|---|
| `.claude/skills/issue-sweep/SKILL.md` | sweep スキル本体 |
| `.claude/skills/refine/SKILL.md` | refine スキル本体 |
| `.claude/skills/refine-sweep/SKILL.md` | refine-sweep スキル本体 |
| `.claude/skills/issue-split-auto/SKILL.md` | 非対話的 Issue 分割スキル |
| `.claude/hooks/check-issue-queue.sh` | Stop Hook 実装 |
| `.sweep/queue.txt` | sweep キュー（gitignore） |
| `.sweep/lock` | 多重起動防止 lock（gitignore） |
| `.sweep/metrics.jsonl` | sweep テレメトリ（gitignore） |
| `.sweep/refine-metrics.jsonl` | refine テレメトリ（gitignore） |
| `.sweep/notify.url` | Webhook URL（gitignore） |
| `.sweep/report-{sweep,refine,refine-sweep}-*.md` | 自動生成レポート（gitignore） |

### Usage example

```bash
# Slack 通知をプロジェクトで有効化
echo "https://hooks.slack.com/services/T0XXX/B0XXX/xxxx" > .sweep/notify.url

# 全 OPEN Issue を端から実装→マージ→close まで
/issue-sweep

# sprint-1 ラベルだけ、並列 3
/issue-sweep label:sprint-1 --parallel 3

# 特定 PR を「軽微指摘 5 個以下」まで研磨
/refine #127

# コードベース全体を critical+major=0 まで磨く
/refine-sweep
```

---

## [v0.1.0] - 2026-05-11

初回ベースラインリリース。Mac / Ubuntu 両対応の dotfiles 一式（シェル・エディタ・言語ツールチェイン・Claude Code スキル群）。

### ✨ New Features / 新機能

#### Install / Update / Reset

- Cross-platform install for Mac and Ubuntu / Mac/Ubuntu 両対応化と言語ツール（uv/bun/rustup/fnm/Go）の自動インストール
- `install.sh` modularization into `lib/` / `install.sh` を `lib/` 配下に責務別分割
- Install `gh` and `gcloud` / `install.sh` に `gh` / `gcloud` のインストール処理を追加
- Install MolePort and Linterly / `install.sh` に MolePort / Linterly のインストールを追加
- Install cloudflared / wrangler / netlify-cli / pm2 / Cloudflare 系 + Node デプロイ系ツール群を追加
- Install Claude Code / Codex CLI / Gemini CLI / 主要 AI CLI を `install.sh` に統合
- `update.sh` and `make update` / 各ツールの update 関数と `update.sh` / `make update` を追加
- `reset-tools.sh` to reset language/AI tools / 言語ツール/AI CLI をリセットして再インストールする `reset-tools.sh` を追加
- Makefile install/update/reset/help targets / Makefile に install/update/reset/help ターゲットを追加

#### Shell / Editor

- Initial nvim / tmux / fish dump and setup / nvim/tmux/fish の初回ダンプとセットアップスクリプトを追加
- gh-dash configuration / gh-dash の設定を dotfiles に追加
- `tide-config.fish` to carry the tide prompt across machines / tide プロンプト設定を新マシンに引き継ぐ `tide-config.fish` を追加
- `cc` alias for `claude --continue` / claude --continue 用の cc エイリアスを追加
- Dotfiles-managed PATH (fish/bash) / PATH 設定を fish/bash 両対応で dotfiles 管理化
- Auto-pull dotfiles on interactive shell start / 対話シェル起動時に dotfiles を自動 pull する fish 設定を追加（後に throttle 削除）

#### Configs / Secrets

- Consolidate `~/.env` as the single env-var store / `~/.env` はsecret/非secret問わず全 env 変数の保管場所
- `.env` body moved to dotfiles, `.mcp.json` reorganized to `claude-mcp/` / `.env` 実体を dotfiles に移動し `.mcp.json` を `claude-mcp/` ディレクトリに整理
- `.claude/` and `.mcp.json` integrated into dotfiles / `.claude/` と `.mcp.json` を取り込み `~/.env` 集約方式に変更

#### Claude Code Skills

- `spec-gen` with project overview document generation / spec-gen にプロジェクト概要ドキュメント生成を追加
- `spec-review` per-finding commit flow / spec-review で指摘 1 件ごとにコミットする手順を追加
- `env-setup` pins TS/JS package manager to bun / env-setup で TS/JS のパッケージマネージャを bun に固定
- `issue-split` copies related spec into sub-issue body / issue-split でサブ Issue 本文に関連仕様を転記
- `spinoff-issue` / `spinoff-issue-en` skills + impl integration / spinoff-issue 系スキルを追加し impl 系から呼び出せるよう接続
- `impl` skills force immediate spinoff Issue creation / impl 系スキルで spinoff-issue の即時作成を強制
- `bug-report` Issue title/label unified rules / bug-report スキルに Issue タイトル・ラベルの統一ルールを追加
- `spec-to-hugo` with Cloudflare Workers + Static Assets deploy / spec-to-hugo に Cloudflare Workers + Static Assets デプロイ設定を追加
- `spec-to-hugo` Basic auth via env / spec-to-hugo に env ベースの Basic 認証を追加

#### Claude Code Settings

- `skipAutoPermissionPrompt` in `settings.json` / `settings.json` に `skipAutoPermissionPrompt` を追加
- `AskUserQuestion` usage principles in CLAUDE.md / CLAUDE.md に AskUserQuestion 利用原則を追加

### 🔧 Improvements / 改善

- Simplify `spec-to-hugo` Cloudflare deploy for UI integration / spec-to-hugo の Cloudflare デプロイを UI 連携前提に簡素化
- Add runtime data entries to `.claude/.gitignore` / `.claude/.gitignore` にランタイムデータ項目を追加
- Remove dotfiles auto-pull throttle / dotfiles 自動 pull のスロットルを削除し毎回実行に変更
- Make `secrets.fish` missing a fatal error in install.sh / secrets.fish が無い場合は `install.sh` をエラー終了させる
- README with command list / README にコマンド一覧を整備

### 🐛 Bug Fixes / バグ修正

- fish PATH adds system paths (`/usr/local/bin` etc.) / fish の PATH に `/usr/local/bin` 等のシステムパスを追加
- `brew install/upgrade` per-package loop for fault tolerance / brew install/upgrade を per-package ループで耐障害化
- `install_go` warns on version-fetch failure instead of aborting / `install_go` の version 取得失敗時に script abort せず警告で継続
- Unfreeze fisher plugin commits for new-machine install / fisher プラグインの commit を解除し新マシンでの install.sh 失敗を修正
- nvim plugin sync uses `Lazy! restore` / install.sh の nvim プラグイン同期を `Lazy! sync` から `Lazy! restore` に変更
- `fnm.fish` loads before `paths.fish` / `fnm.fish` が `paths.fish` より先にロードされる順序問題を修正
- nvim config inconsistencies / nvim 設定の不整合を修正
- `spec-to-hugo` root → /docs/ redirect on edge / spec-to-hugo のルート→/docs/ リダイレクトをエッジ側で処理
- `spec-to-hugo` unified on bun for Cloudflare deploy / spec-to-hugo を bun ベースに統一し Cloudflare デプロイを通す

### 📝 Documentation / ドキュメント

- `~/.env` is the storage location for all env vars / `~/.env` はsecret/非secret問わず全 env 変数の保管場所であることを明記
