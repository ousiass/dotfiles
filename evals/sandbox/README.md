# evals/sandbox — eval 専用の隔離フォルダと試験用 repo（#56 Phase 1 の準備）

モデルを呼ぶ実行（Phase 1 以降）を、ユーザーの環境から切り離して回すための土台。**この README の範囲では、モデルは呼ばない。**

| ファイル | 役割 |
|---|---|
| `init.sh` | 隔離フォルダ（既定 `/mnt/nvme/eval-sandbox`）を作る。何度実行しても同じ結果。 |
| `seed.sh` | 試験用 repo にコード・CI・ダミー Issue を入れる（既に在る ref・Issue は飛ばす。force push しない）。 |
| `reset.sh` | 試験用 repo を初期状態に戻す（`--plan` で一覧、`--apply` で実行。人が実行する。安全策は下）。 |
| `lib.sh` | 固定の repo 名など、上の 3 本が共有する部分。 |
| `issue-map.json` | タスクの中の Issue 番号 → 試験用 repo の Issue 番号。 |
| `doctor.sh` | 隔離が効いているかを確かめる（落ちたら exit 1）。 |

## 試験用 repo

`ousiass/dotfiles-eval-sandbox`（private、本物の作業はしない）。`seed.sh` が `evals/tasks.jsonl` から作った。

| 入れたもの | 内容 |
|---|---|
| `main` | 題材（小さな bash ライブラリ。`lib/fixture.sh` の `fixture_seed_files` と同じ） |
| `eval/<scenario>/main` | シナリオの初期状態を `main` に重ねたもの（`docs-typo` / `out-of-scope` / `sweep-three` / `sweep-impossible`） |
| `eval/<scenario>/feat/wip` | refine 系（`refine-defect` / `refine-clean`）の作業ブランチ |
| Issue #1〜#12 | ラベル `eval` と `task:<id>`。対応表は下 |

どのブランチも `main` の同じ初期コミットから伸びる。

| Issue | task | 内容 |
|---|---|---|
| #1 | `impl-bugfix` | greet に空の名前 |
| #2 | `impl-feature` | farewell を追加 |
| #3 | `impl-docs` | README の見出しの綴り |
| #4 | `impl-spinoff` | greet に空の名前（範囲外の欠陥つき） |
| #5 | `impl-missing-target` | 存在しない `src/missing.sh` |
| #6 | `impl-auto` | greet に空の名前（`--auto`） |
| #7 / #8 / #9 | `sweep-three` | 空の名前 / farewell / 綴り |
| #10 / #11 / #12 | `sweep-impossible` | 空の名前 / 綴り / 存在しない `src/missing.sh` |

`tasks.jsonl` のプロンプトは `/impl #1` のように**タスクの中の番号**（1 始まり）で書いてある。この表の GitHub 側の番号とは別なので、
本物の repo で動かすときは、プロンプトの番号をこの表で置き換える（`run.sh --remote` が `issue-map.json` で自動で置き換える。下の「試験用 repo に書かせる」）。

## 分け方（隔離）

`init.sh` が `<root>` の下に次を作る。**ユーザーのチェックアウト・`~/dotfiles`・`~/.claude`・`~/.omp`・他のペインのフォルダ・`gh` のログインには触れない**
（`init.sh` は `--root` が `~/.claude` `~/.omp` `~/dotfiles` の中、または `~` 自体なら止まる。`.eval-sandbox` の目印が無い既存の非空フォルダにも作らない）。

```
<root>/                 既定 /mnt/nvme/eval-sandbox
  .eval-sandbox         init.sh が作った目印
  dotfiles/             試験対象の dotfiles の clone（--ref の先端。detached、作業ツリーは clean）
  home/                 ハーネス用の HOME
    .claude/            CLAUDE.md / skills / agents / hooks は dotfiles/.claude へのリンク。settings.json は複製（テレメトリの env を除く）
    .omp/agent/         config.yml / RULES.md / WATCHDOG.md / agents / extensions / skills は dotfiles/omp 等へのリンク。セッション・DB はここに溜まる
    .config/gh/         gh の設定の置き場（hosts.yml は作らない）
    .gitconfig          user = eval、credential helper = gh（トークンは GH_TOKEN）
  work/tmp/             TMPDIR（run.sh のサンドボックスはここの下に作られて、終わると消える）
  results/              results.jsonl の出力先（EVAL_RESULTS_DIR）
  env.sh                環境変数（下）
  with-env              env.sh を読み込んだ別プロセスでコマンドを実行する入口
```

`env.sh` が設定するもの: `HOME` / `XDG_*` / `CLAUDE_CONFIG_DIR`（Claude Code の設定・セッション）/ `PI_CODING_AGENT_DIR`（omp の設定・セッション・DB）/
`TMPDIR` / `GIT_CONFIG_GLOBAL` / `GH_CONFIG_DIR`。`SSH_AUTH_SOCK`・`GITHUB_TOKEN`・各社の API キー（`ANTHROPIC_API_KEY` など）・テレメトリの変数は外す。
**MCP の設定（`claude-mcp/mcp.json`）は置かない**（supabase などに繋がせない）。

呼び出し元のシェルは汚さない。`with-env` は別プロセスで動くので、実行後に元のシェルの `HOME` などは変わらない。

```bash
/mnt/nvme/ousiass/dotfiles/.claude/worktrees/feat-#56-sandbox/evals/sandbox/init.sh --ref feat/#56-sandbox   # evals/ が main に入ったら --ref は不要
/mnt/nvme/eval-sandbox/with-env /mnt/nvme/eval-sandbox/dotfiles/evals/sandbox/doctor.sh
```

`run.sh --live` は、この隔離フォルダの中（`HOME` / `CLAUDE_CONFIG_DIR` / `PI_CODING_AGENT_DIR` が `<root>` の下）でないと起動しない。`--out` を省くと `<root>/results/` に出す。

### サブスクリプションのログイン

隔離した HOME には、ユーザーのログイン情報を**コピーしない**。Phase 1 の最初に、ユーザーが一度だけ、隔離環境の中でログインする:

```bash
/mnt/nvme/eval-sandbox/with-env claude          # 起動して /login（サブスクリプション）
/mnt/nvme/eval-sandbox/with-env omp             # 起動してログイン（`omp` のプロバイダの案内に従う）
```

ログイン情報は `<root>/home/.claude/` と `<root>/home/.omp/agent/agent.db` にだけ残る。API キーは `env.sh` が外すので、サブスクリプションの枠で動く
（どのプロバイダを枠で動かすかは、`omp/config.yml` の `modelRoles` に従う。Anthropic 以外のロールにも触れるので、ログインが要るのはそのプロバイダ）。

## GitHub のトークン（ユーザーが作って、自分で設定する）

このリポジトリの作業では、トークンを作らない。既存の `gh` のログインも使わない（`env.sh` が `GH_CONFIG_DIR` を隔離して、`GH_TOKEN` だけを認証にする）。

**fine-grained personal access token**（Settings → Developer settings → Personal access tokens → Fine-grained tokens）:

| 項目 | 値 |
|---|---|
| Resource owner | `ousiass` |
| Repository access | **Only select repositories** → `ousiass/dotfiles-eval-sandbox` だけ |
| Expiration | 短く（例: 7〜30 日） |
| Repository permissions: **Contents** | Read and write（clone・push・ブランチ削除・マージ） |
| Repository permissions: **Pull requests** | Read and write（`gh pr create` / `view` / `merge` / `comment`） |
| Repository permissions: **Issues** | Read and write（`gh issue view` / `create` / `edit` / `comment`、ラベル） |
| Repository permissions: **Checks** | Read（`gh pr checks`） |
| Repository permissions: **Commit statuses** | Read（`gh pr checks`） |
| Repository permissions: **Metadata** | Read（自動で付く） |
| 付けない | Administration / Workflows / Actions / Secrets / Environments / Pages / Webhooks / Account permissions のすべて |

試験用 repo に GitHub Actions のワークフローは置いていない。ワークフローを置く（CI を回す）なら、Contents に加えて **Workflows: Read and write** と **Actions: Read** が要る。

置き場所（どちらか。両方あるときは環境変数が優先）:

| 方法 | 内容 |
|---|---|
| 環境変数 `EVAL_GH_TOKEN` | `EVAL_GH_TOKEN=github_pat_... /mnt/nvme/eval-sandbox/with-env ...`。`env.sh` が `GH_TOKEN` に移して、`EVAL_GH_TOKEN` は外す |
| ファイル `/mnt/nvme/eval-sandbox/gh-token` | トークンだけを 1 行。`chmod 600`（`doctor.sh` がモードを確かめる） |

どちらも、このリポジトリには置かない（`/mnt/nvme/eval-sandbox` は dotfiles の外）。設定したら `doctor.sh` を実行する: 試験用 repo を読めること、`ousiass/dotfiles` には書き込めないことを、読み取り専用の API で確かめる（トークンの値は表示しない）。

## 試験用 repo に書かせる（`run.sh --remote`）

`run.sh --remote` は、ローカルの使い捨て repo と偽 `gh` の代わりに、試験用 repo に実際に書かせる。**書き込むのはエージェントの `git push` と `gh` だけ**で、`run.sh` 自身はブランチも PR も Issue も作らず、消しもしない。

```bash
# dry: 試験用 repo の代わりのローカルの bare repo と偽 gh（ネットワークに出ない。トークン不要）
evals/run.sh --harness claude --dry --remote --rep 1
# live（有料。トークンと隔離フォルダが要る）
EVAL_CONFIRM_PAID=1 /mnt/nvme/eval-sandbox/with-env dotfiles/evals/run.sh --harness claude --live --remote --model <id> --rep 1 --task refine-clean
```

| 仕組み | 内容 |
|---|---|
| 記録用の `gh` ラッパー（`lib/gh-record.sh`） | エージェントの PATH 先頭に `gh` として置く。`--repo` / `-R` / `GH_REPO` / `gh api` のパスが固定の repo 以外を指していたら実行せずに止める。許可する subcommand は `auth status` / `api` / `issue` / `pr` / `label` / `repo view` / `run list\|view\|watch` だけ（`repo delete`・`secret`・`auth login` などは止める）。`pr create` / `issue create` には eval ラベルを足す。呼び出しを `actions.jsonl` に記録して、本物の `gh` に渡す（`GH_REPO` は固定の repo にする） |
| 実行前の検査（`remote_check_ref`） | `main` と、そのタスクが使うブランチが初期状態のままかを見る。動いていたら、その実行は始めず `status=error` で残す（何も書き込まない）。タスクの Issue が閉じていたときも同じ |
| base | シナリオに `eval/<scenario>/main` があればそれ、無ければ `main`。プロンプトの `--base` の値と PR のマージ先を、これにそろえる |
| ブランチ名 | プロンプトで `eval/r<日時>-<連番>/` で始めるよう指示する。`reset.sh` が片付けられる名前にするため |
| Issue 番号 | プロンプトの `#<n>`（タスクの中の番号）を、`issue-map.json` で GitHub の番号に置き換える。`seed.sh` は番号が `issue-map.json` と食い違ったら止まる |
| 採点用の取り出し | 実行後に、リモートを mirror clone して `origin.git` に、PR・Issue を `gh` で読んで `state/prs.json` / `issues.json` にする。この実行で作られたもの（実行前の最大番号より大きい番号）だけを PR・spinoff として数える。PR の先端は `refs/pull/<N>/head`（`--delete-branch` でブランチが消えても読める） |
| CI | 試験用 repo の `.github/workflows/ci.yml`（`./test.sh` を回すだけ）。`seed.sh` が `main` の初期状態に入れる |

### 試験用 repo の初期化（`reset.sh`。人が実行する）

`run.sh` の前後で自動には走らせない。`--remote --live` を続けて回すと、2 回目は初期状態ではないので始まらない（上の検査）。

```bash
/mnt/nvme/eval-sandbox/with-env dotfiles/evals/sandbox/reset.sh --plan    # 一覧だけ（既定。何も変えない）
/mnt/nvme/eval-sandbox/with-env dotfiles/evals/sandbox/reset.sh --apply   # 実行する
/mnt/nvme/eval-sandbox/with-env dotfiles/evals/sandbox/seed.sh            # シナリオ用ブランチを作り直す（--apply のあと）
```

- 対象は `ousiass/dotfiles-eval-sandbox` だけ。`--repo` や `--url` に別の repo を渡すと止まる。`GH_TOKEN` と隔離フォルダ（`EVAL_SANDBOX_ROOT`）が無いと止まる（既存の `gh` のログインでは動かない）
- 動かすのは次だけ: (1) `eval/` で始まるブランチの削除（`seed.sh` のシナリオ用ブランチも含む）、(2) eval ラベルの開いている PR を閉じる（マージ済みは一覧に出すだけ）、(3) eval ラベルの Issue — `issue-map.json` の Issue が閉じていれば開き直し、タイトルと本文を `tasks.jsonl` のとおりに戻し、アサインを外す。エージェントが作った Issue（`issue-map.json` に無い番号）は閉じる（API では消せない。コメントは残る）、(4) `main` の戻し
- `main`・初期状態のコミット・`eval/` で始まらないブランチ・eval ラベルの無い PR / Issue には触れない
- `main` は force しない。先端の上に「初期状態と同じ中身にするコミット」を 1 本積んで、通常の push で戻す。保護ルールがあれば失敗して止まる
- 1 回で動かす件数が 50 を超えたら、何もせず止まる（`--max` は 50 まで）

### トークンを入れたあとに確かめる手順

トークン（上の表）を `EVAL_GH_TOKEN` か `gh-token` に入れたあと。**上から順に。どれかが落ちたら先へ進まない**。

1. `with-env dotfiles/evals/sandbox/doctor.sh` — NG 0。試験用 repo を読めて、`ousiass/dotfiles` には書き込めないこと
2. `with-env dotfiles/evals/sandbox/reset.sh --plan` — 一覧を読む。いまの repo（seed 直後）は、`eval/<scenario>/...` のブランチ 6 本の削除だけが出るはず（`RESTORE-MAIN` や PR・Issue の操作が出たら、何が動いたか確かめる）
3. `with-env dotfiles/evals/sandbox/seed.sh --plan` — 入れるものの一覧。続けて `seed.sh`（実行）: 既に在る ref・Issue は「在るので飛ばす」になり、`main` に CI（`.github/workflows/ci.yml`）の目印コミットが **1 本積まれる**（既存の `main` には初期状態の目印が無いので）。Issue の番号が `issue-map.json` と一致するメッセージが出ること
4. 手順 3 のあと、既存のシナリオ用ブランチは CI を足す前の初期コミットから伸びているので、`seed.sh` が「古い」と警告する。`reset.sh --apply` → `seed.sh` で作り直す（この時点でだけ、試験用 repo に force なしの書き込みが入る）
5. `with-env dotfiles/evals/run.sh --harness claude --dry --remote --rep 1` が完走する（ローカルの代わりの repo。ネットワークに出ない）
6. GitHub の Actions が動くこと: `gh run list --repo ousiass/dotfiles-eval-sandbox`（`main` への push で CI が走る）。fine-grained トークンの Actions: Read が要る
7. 最小の live: `EVAL_CONFIRM_PAID=1 with-env dotfiles/evals/run.sh --harness claude --live --remote --model <id> --rep 1 --task refine-clean`（何も書かないのが正解のタスク）。実行後の `reset.sh --plan` が空（初期状態）であること

### 実装時に確かめていないこと（トークンが無いので）

- 本物の `gh` と GitHub に対する、記録用ラッパー・`reset.sh`・`seed.sh` の Issue / PR 操作。呼び出しの形は、スタブと偽 gh で確かめた
- 本物の `gh pr checks` の終了コード（pending = 8）と、`gh pr list --json` が返す項目（`labels` などの形）は、偽 gh を実物に合わせて書いたもの
- `gh pr merge --delete-branch` のあとに `refs/pull/<N>/head` が読めること（GitHub の仕様どおりのはずだが、試験用 repo では未確認）
- `main` の保護ルールやブランチの命名ルールがあると、`reset.sh` の push が失敗する。試験用 repo には設定していない
- 本物の Actions の CI（`.github/workflows/ci.yml`）が通ること
