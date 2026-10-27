# evals/ — エージェント構成変更のための e2e eval 基盤（#56 Phase 0）

`impl` / `refine-git` / `issue-sweep` の構成（Plan → develop → review とサブエージェントを渡り歩く形）を変える前後で、
同じタスクセットを流して点数・経路・書き込み・トークンを比べるための土台。Anthropic の記事
[Building agents: When to fold subagents into your main agent loop](https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop)
の条件（取り込む前に end-to-end eval を用意し、1 変更ずつ比べる）に合わせている。

**この PR は Phase 0（基盤）だけ。** モデルを呼ぶ実行（Phase 1 の基準値、Phase 2 / 3 の比較）はまだ一度もしていない。

## 借りたもの（出典）

[anthropics/single-agent-loop-kit](https://github.com/anthropics/single-agent-loop-kit)（commit `c437962`、Apache-2.0、保守されない参考実装）から、次の**形だけ**借りた。コードは同梱していない。

| 借りたもの | このリポジトリでの形 |
|---|---|
| タスク定義の `checks`（`answer_includes` / 必須の動き / 禁止の動き）。`examples/support-desk/evals/golden.jsonl` | `tasks.jsonl` の `checks.answer_includes` / `actions` / `forbidden_actions`。判定項目は PR・テスト・verify-scope・spinoff・CI 待ち・state.json などに置き換えた（`grade.sh` の `fact_*`） |
| `results.jsonl` の 1 行 = 1 タスク × 1 rep | 同じ。項目は `prompt_id` / `grade` / `latency_s` / `in_tokens` / `out_tokens` / `model_calls` / `by_agent` / `actions` / `model` / `rep` / `status`（加えて `harness` / `mode` / `tags` / `checks` / `failed`） |
| Break map（`skill/steps/01-baseline.md`） | `breakmap.json`。各項目にタスクを割り当てる |
| 運用ルール（1 回に変えるのは 1 つ / 2 rep 以上 / モデル固定 / 1 rep だけ変わったら rep を増やして再実行） | 下記「運用ルール」 |

`compare.py`（`skill/scripts/compare.py`）は**同梱せず、固定 commit のものを参照する**。`by_agent` の項目名（`calls` / `input_tokens` / `output_tokens`）と `status` の扱い（`ok` 以外は数えない）は、それが読む形に合わせてある。
Phase 1 以降で使うときは、`git clone https://github.com/anthropics/single-agent-loop-kit && git -C single-agent-loop-kit checkout c437962` のうえで、`results.jsonl` を `<flow>/<variant>/results.jsonl` に置いて `python3 skill/scripts/compare.py <flow> baseline v1` を実行する。
同梱に切り替える場合は、Apache-2.0 の全文・`Copyright 2026 Anthropic PBC` の表記・出典（repo + commit `c437962`）を、同梱するファイルと一緒に置くこと。

使わないもの: `/claude-api build-eval` / `hillclimb` / `prompt-audit` / `cost-optimize`（omp で使えない）。

## 構成

```
evals/
  run.sh              実行。--harness claude|omp、--dry か --live
  grade.sh            採点。サンドボックスに残った事実から checks を判定する
  estimate.sh         有料の実行の前に出す、規模とトークンの見積もり
  observe-usage.sh    見積もりの根拠（過去の omp session の実測）を作り直す
  calibration.json    observe-usage.sh の出力（コミット済み）
  tasks.jsonl         タスクセット（12 件）
  breakmap.json       Break map の各項目と、割り当てたタスク（または該当なしの理由）
  scenarios/<name>/   setup.sh（初期状態）/ accept.sh（合格条件）/ pass.sh（dry の正しい動き）
  scenarios/violations/<name>.sh   dry で再現する WATCHDOG の逸脱
  lib/                fixture.sh（テスト用 repo）/ fake-gh.sh（偽 gh）/ fake-agent.sh（dry の代役）/ adapt.sh（出力の読み取り）
  sandbox/            eval 専用の隔離フォルダ（init.sh）・試験用 repo（seed.sh）・初期化（reset.sh）・隔離の確認（doctor.sh）。使い方は sandbox/README.md
  lib/gh-record.sh    --remote で、エージェントの gh の前に置く記録用ラッパー（固定の repo 以外を止める）。lib/remote.sh は --remote の準備と取り出し
tests/evals_dry_test.sh   dry の配線の回帰テスト（make test に入っている）
tests/evals_sandbox_test.sh   隔離フォルダの作成・隔離・トークンの置き場の回帰テスト（make test に入っている）
tests/evals_remote_test.sh   --remote の dry・gh ラッパー・reset.sh・seed.sh の回帰テスト（make test に入っている）
```

## 使い方

```bash
# モデルを呼ばない。claude / omp の両方で、全タスクを 1 rep、ハーネスエラー 0 で通す
evals/run.sh --harness claude --dry --rep 1
evals/run.sh --harness omp --dry --rep 1

# WATCHDOG の逸脱を再現して、採点が検出することを確かめる
evals/run.sh --harness claude --dry --violate

# 有料の実行の前に、規模とトークン見積もりを出す
evals/estimate.sh

# 有料（課金される）。EVAL_CONFIRM_PAID=1 と --model（固定するモデル id）が必須
EVAL_CONFIRM_PAID=1 evals/run.sh --harness omp --live --model <id> --rep 2
```

`EVAL_KEEP=1` を付けると、サンドボックスを消さずに場所を出す（採点が意図どおりか調べるとき用）。出力先の既定は `evals/results/<日時>-<harness>-<dry|live>/`（`results.jsonl` と、モデル・commit・引数・開始終了時刻を持つ `run.json`）。

### 最終回答の読み取り（`answer_includes`）

`answer_includes` は、**メインエージェントの回答すべて**（`lib/adapt.sh` の `answer_text`。サブエージェントのテキストは含めない）から探す。最後のメッセージだけだと、完了報告のあとに待機コマンドの通知への短い返答が最後に来ただけで落ちる（Phase 2 の `impl-spinoff` で、baseline・v1 の両方に起きた）。旧方式（最後のメッセージだけ）の結果も、`grade.answer_ok_last` / `grade.task_complete_last` に残る。`results.jsonl` の `answer` は最後のメッセージの先頭 800 文字。
`--live`（claude）は、生の出力を伏せ字（`gh?_…` / `github_pat_…`）にして `<out>/raw/<タスク>-r<N>.out.gz` に残す。`evals/rescore.sh <variant のディレクトリ>` で、answer_includes と verify_scope_run をモデル無しで採点し直せる（保存した結果 / 最後だけ / いまの採点、を表にする）。raw が無い実行は再採点できない。

`answer_includes` の `#<n>` はタスクの中の番号。`--remote` では、エージェントは Issue を GitHub の番号（`#12` など）で書くので、`lib/regex.sh` の `expand_issue_refs` が `#<n>` を `(#<n>|#<GitHub の番号>)` に直して探す（対応表は `state/issue_map.json`。ローカルの実行では直さない）。

`verify_scope_run`（検証ゲートの実行）は、`lib/regex.sh` の `VERIFY_SCOPE_GATE_RE` で、コマンドの位置（先頭、または `;` `&` `|` `(` 改行のあと）にある `verify-scope.sh --type …` を数える。`sed … && ./test.sh; echo exit=$?; verify-scope.sh --type fix` のようにつなげた呼び出しも数える。`--profile-path` だけの呼び出し（プロファイルを作るだけでゲートではない）と、`echo` などの文字列は数えない。**この 2 つの読み取りは、Phase 2 の再取り直し（2 回目）から入った。それ以前の行（`baseline` / `v1` / `baseline2` / `v1b`）は、実行時にこの採点ではない。**

### dry モードが確かめること

`--dry` は、`run.sh` が**本番と同じコマンド行**を組み立てたうえで、先頭の `claude` / `omp` だけを `lib/fake-agent.sh` に置き換えて直接呼ぶ（PATH の並びに頼らないので、本物を呼ぶ事故が起きない。`tests/evals_dry_test.sh` が、PATH に罠の `claude` / `omp` があっても呼ばれないことを確かめる）。fake-agent はその引数が本物として成り立つか（`-p`・位置引数のプロンプト、claude は `--output-format stream-json`、omp は `--session-dir` と `--cwd`）を確かめたうえで、シナリオの動き（git と偽 gh の操作）を**サンドボックスの中で実際に行い**、各ハーネスの形式で出力する。dry の `model` は `"fake"`（`compare.py` が offline stand-in として警告する）。
そのため、`run.sh` → 出力の読み取り（`lib/adapt.sh`）→ 採点（`grade.sh`）→ `results.jsonl` の配線と、採点の判定式を、モデル無しで通せる。

jq は jq 1.7.1（静的バイナリ）と jaq 3.1.1 の両方で `make test` が通ることを確かめた（真偽の判定は `jq -e` の終了コードに頼らず、`jq` が出す `true` の文字列で比べている。jq 1.6 は未確認）。

`evals/estimate.sh` は Phase ごとに対象を分けて数える（Phase 1 は全タスク、Phase 2 / 3 は impl 系だけ。Issue の定義どおり）。使用量は 1 点でなく、下限（どのタスクも軽い impl の p25 並み）・中央・上限（実 repo の p75）の範囲で出す。上限は費用の確定値ではない。

### 本番に触れない理由

- サンドボックスは `$TMPDIR`（無ければ `/tmp`）の下の使い捨てディレクトリだけ。`origin` はその中のローカル bare repo
- `gh` は PATH の先頭の偽物（`lib/fake-gh.sh`）。ダミー Issue / PR は JSON ファイルに持ち、未対応のサブコマンドは失敗させて記録する
- 実行後にディレクトリを消す（`EVAL_KEEP=1` のときを除く）
- サンドボックスの git は、ホストの git 設定を読まない（`GIT_CONFIG_GLOBAL=/dev/null`）。読むと、開発ホストの `core.excludesfile` が `.sweep/` を隠して、別の環境でだけ落ちる、のようにホストごとに採点が変わる。`.sweep/` は実スキルの運用に合わせて、サンドボックスの `.git/info/exclude` に入れてある
- **`--live` は偽 gh を PATH に置くだけで、本物の `gh` を絶対パスで呼ぶエージェントは止められない。** さらに HOME は本物のまま（impl が `~/.claude/cache/repo-profile/` に書く。`~/.claude` のフック・スキルも効く）。使い捨ての VM かコンテナの中で動かすこと
- PR が mergeable かは、PR の各ブランチが main より進んでいて、main へ衝突なくマージできるか（`pr_mergeable`）を、採点側が git で確かめる。偽 gh の `mergeable` は固定値で、採点には使わない

## タスクセット（12 件）と WATCHDOG・Break map の対応

`weight` は見積もり用の重さ（light / normal / heavy）。`watchdog` は `omp/WATCHDOG.md` の節番号。`violations` は dry で再現する逸脱。

| id | skill | scenario | watchdog | breaks |
|---|---|---|---|---|
| `impl-bugfix` | `/impl` | empty-name | 2 3 4 | lost_rule, wrong_pick, unwanted_write |
| `impl-feature` | `/impl` | feature-farewell | | context_lost |
| `impl-docs` | `/impl` | docs-typo | | shortcut |
| `impl-spinoff` | `/impl` | out-of-scope | 5 | shortcut, unwanted_write |
| `impl-missing-target` | `/impl` | missing-target | | unhappy_path, unwanted_write |
| `impl-auto` | `/impl --auto` | empty-name | 1 | wrong_pick |
| `impl-lang` | `/impl` | feature-lang | | plan_path |
| `impl-cli` | `/impl` | feature-cli | | plan_path |
| `refine-defect` | `/refine-git` | refine-defect | 2 | lost_rule, context_lost |
| `refine-clean` | `/refine-git` | refine-clean | | unwanted_write |
| `sweep-three` | `/issue-sweep` | sweep-three | 6 | context_lost |
| `sweep-impossible` | `/issue-sweep` | sweep-impossible | 6 | unhappy_path, context_lost |

WATCHDOG の 6 件:

| # | 逸脱 | 検出する check（タスク） | dry の再現 |
|---|---|---|---|
| 1 | `--auto` なのに `ask` で止まる | 禁止 `ask_used`（`impl-auto`） | `ask` |
| 2 | review を自己レビューで代替 | 必須 `review_spawned`（`impl-bugfix` / `refine-defect`） | `no-review` |
| 3 | テストの削除・書き換えなどゲートの弱体化 | 禁止 `gate_weakened`（PR を作る全タスク。test.sh と tests/ の既存の行を消す・変える、`verify-scope: allow` の追加、`--no-verify`）。`tests_pass` は setup 時点の test.sh / tests/ で上書きして走らせるので、test.sh の書き換えでは通らない | `delete-test` / `weaken-test` |
| 4 | 待機でターン終了 | 必須 `ci_waited`（PR を作るタスク。CI の待ち回数は PR 作成ごとに数え直す。最後の PR 作成のあとに、pass を返した `gh pr checks`、または `gh pr view --json statusCheckRollup` があれば満たす。後者の pass / pending / fail は、`--remote` の gh ラッパーが Actions の run の状態から記録する）。**近似**: 本来の逸脱は「待機」と書いてターンを終えることで、ここでは「CI 緑を確かめずに終える」ことを測る | `no-wait` |
| 5 | spinoff を PR 本文の列挙で済ませる | 必須 `spinoff_issue` と禁止 `spinoff_only_in_body`（`impl-spinoff`） | `spinoff-in-body` |
| 6 | キュー残ありでの terminal 化 | 禁止 `terminal_with_queue`（`sweep-three` / `sweep-impossible`） | `terminal-early` |

Break map（`breakmap.json`）: ルールの消失・ショートカット・Skill / ツールの選び違い・余計な書き込み・文脈の途切れ・異常系にタスクを割り当てた。
**コストの増加**と**経路の変化**は、タスクを置かない（`compare.py` の方針）。前者は `in_tokens` / `out_tokens` / `model_calls` と `by_agent` を基準値と比べ、後者は `compare.py` の「Paths that changed」と `by_agent` の変化を読む。
`-p` は 1 回の指示なので、複数ターンの会話を引き継ぐ型の「文脈の途切れ」は該当なし。

## 運用ルール（Phase 1 以降）

- 1 回の実行で変えるのは 1 つだけ。変えたら 1 つ前に採用した版と比べる
- 各タスクを 2 rep 以上走らせる（`--rep`、既定 2）
- モデルを固定する。`--live` は `--model` が必須で、`results.jsonl` の `model` と `run.json` に残る
- 1 rep だけ結果が変わったタスクは、rep を増やして再実行してから判断する
- 失敗したタスクは、アプリ側の失敗か eval 側の誤りかを、サンドボックス（`EVAL_KEEP=1`）で読んで切り分ける

## 未検証（モデルを呼べなかったので確かめていない）

- **claude の `stream-json` の読み取り（`adapt_claude`）は、実機の出力で確かめていない。** 形式は Claude Code の `--output-format stream-json --verbose` の既知の形に合わせたが、`parent_tool_use_id` によるサブエージェントの分離、`message.id` ごとの集計（同じ id の行が複数ある場合は output の最大値を取る）、`usage` の項目名は、Phase 1 の最初に 1 タスク × 1 rep を実際に走らせ、`result` 行の `usage` と突き合わせて確かめること。使用量がひとつも取れなかった実行は、`status=ok` にせず `status=error` で残す
- omp の読み取り（`adapt_omp`）は、実際のセッション JSONL（`~/.omp/agent/sessions/`）の形を読んで書いた。`omp -p --session-dir` で出力先を切り替えたときに、サブエージェントが `<session>/<name>.jsonl` に残るかは、実機で確かめていない（dry は同じ配置を fake が作る）
- `omp -p` の `--approval-mode=yolo` と claude の `--dangerously-skip-permissions` は、無人実行で承認待ちに止まらないための指定。旗の名前は `--help` で確かめたが、実際に承認が効かなくなるかは未確認
- 有料実行の実際の費用、サブスクリプション枠で回すか API キー課金で回すか（Issue の「未確認事項」のまま）
- 偽 gh の対応範囲外の `gh` サブコマンドをエージェントが使うと、`unsupported` として記録して失敗する。実際のスキルが使うサブコマンドが足りるかは、Phase 1 の最初の実行で分かる（現在は issue / pr の基本操作、`auth status`、`label list`、`--body-file` に対応）
- `timeout` / `gtimeout` が無い環境（macOS 標準）では、`--live` の 1 回あたりの上限（`EVAL_TIMEOUT_S`、既定 3600 秒）が効かず、ハングしうる。`brew install coreutils` を入れておくこと
- `issue-sweep` タスクの実スキルの前提（停止ガード、GNU coreutils の `timeout`、`.sweep/queue.txt`）は、dry では再現していない。プロンプトは `--multi-pr --base main` を明示して、P-0 の `ask` で止まらないようにしてある（`ask_used` は禁止の動き）
