# evals/sandbox — eval 専用の隔離フォルダと試験用 repo（#56 Phase 1 の準備）

モデルを呼ぶ実行（Phase 1 以降）を、ユーザーの環境から切り離して回すための土台。**この README の範囲では、モデルは呼ばない。**

| ファイル | 役割 |
|---|---|
| `init.sh` | 隔離フォルダ（既定 `/mnt/nvme/eval-sandbox`）を作る。何度実行しても同じ結果。 |
| `seed.sh` | 試験用 repo にコードとダミー Issue を入れる（既に在る ref・Issue は飛ばす。force push しない）。 |
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
本物の repo で動かすときは、プロンプトの番号をこの表で置き換える必要がある（下の「いまの run.sh と試験用 repo の関係」）。

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

## いまの run.sh と試験用 repo の関係

**`run.sh` は、いまは試験用 repo（GitHub）を使わない。** `run.sh` はタスクごとに `$TMPDIR` の下にローカルの bare repo と偽の `gh`（`lib/fake-gh.sh`）を作り、そこで動かして採点する（dry も `--live` も同じ）。
つまり `--live` を回しても、本物のモデルは動くが、書き込み先はローカルの使い捨て repo と偽 gh で、`ousiass/dotfiles-eval-sandbox` には何も書かれない。GitHub のトークンも使われない。

試験用 repo に実際に書かせる（本物の `gh` と本物の PR・Issue・CI で動かす）には、次が要る。これは別の判断なので、この PR では実装していない:

- `gh` を、呼び出しを記録して本物の `gh` に渡すラッパーにする（`state/actions.jsonl` の代わり）
- 採点用に、実行後の PR・Issue・ブランチを `gh` / `git ls-remote` から `state/` と同じ形で取り出す
- 実行ごとに試験用 repo を初期状態へ戻す（PR を閉じる、ブランチを消す、`main` を戻す、Issue を開き直す）。ファイルや PR の削除を含むので、実装前に確認する
- プロンプトの Issue 番号を、上の対応表で置き換える
- CI（`gh pr checks`）の実体。試験用 repo にワークフローが無いので、そのままでは待つ対象が無い
