# omp (oh-my-pi) の設定

`install.sh` の `link_omp` が、このディレクトリを `~/.omp/agent/` 配下へ symlink する。

| dotfiles | リンク先 |
|---|---|
| `omp/config.yml` | `~/.omp/agent/config.yml` |
| `.claude/CLAUDE.md` | `~/.omp/agent/RULES.md` |
| `omp/WATCHDOG.md` | `~/.omp/agent/WATCHDOG.md` |
| `omp/agents/` | `~/.omp/agent/agents/` |
| `omp/extensions/` | `~/.omp/agent/extensions/` |
| `omp/skills/` | `~/.omp/agent/skills/` |
| `claude-mcp/mcp.json` | `~/.omp/agent/mcp.json` |

## なぜ設定の意図をここに書くか

`omp setup` / `/model` / `/login` / `omp config set` など **設定を書き込む操作は config.yml を再シリアライズし、コメントを全て落とす**。
読み取り（`omp config get` / `list`）や通常のセッション起動では消えないが、書き込みが一度でも走ると失われる。
そのため config.yml はコメントを持たない素の YAML として扱い、意図はこのファイルに残す。

## config.yml

### modelRoles

| ロール | 割り当て | 意図 |
|---|---|---|
| `default` / `task` | `claude-sonnet-5:high` | 主セッションと実装サブエージェント |
| `plan` / `advisor` | `claude-sonnet-5:high` | 設計と受動レビュー。常時動くので opus は使わない |
| `slow` | `claude-opus-5-5:high` | **難問を突破するときだけ**。通常の経路からは呼ばれない |
| `smol` / `tiny` / `commit` | `gpt-6-luna:medium` | 探索の fan-out・タイトル/メモリ・コミットメッセージ |
| `vision` | `claude-sonnet-5:high` | 画像。未設定だと default に落ちるので明示する |

opus は `slow` だけに限定する。レビュー（`reviewer` / `security-reviewer` / 自前の `review`）は
sweep が何度も並列起動するため、ここを opus にすると消費が跳ねる。sonnet で回し、
行き詰まったときに `--slow` や `/model` で opus に切り替える。`slow` は Opus 5.5
（`claude-opus-5-5`）。本線（`default`/`task`/`plan`/`advisor`/`vision`）は引き続き Sonnet 5
のままで、5.5 は難問・再試行枠だけに絞る（issue #30）。thinking は `develop-slow` の
`thinkingLevel: auto` のまま変更不要 — 5.5 も `anthropic-adaptive` モードで efforts
`low/medium/high/xhigh/max` を持ち、既存の `:high` 指定と矛盾しない（`models.db` で確認済み）。

`issue-sweep` だけ例外的に自動昇格がある: 同じバッチの実装が 1 回失敗して**同一バッチの 2 回目**を
再投入するとき、`develop` ではなく `develop-slow`（`@slow`）に上げる（`budget_exhausted` の
resume は対象外。詳細は `skills/harness-model/SKILL.md`、issue #22）。それ以外の経路（本線
`default`/`task`、Advisor、並列 review）は自動昇格しない。

モデル ID と effort は `~/.omp/agent/models.db`（omp のカタログ）で実在を確認する。
`omp models` は**認証済みプロバイダしか表示しない**ため、未認証のものはカタログ側を見る。

### advisor.enabled: true

毎ターンの差分を別コンテキスト・別モデルでレビューし、気づきを注入する。
approvalMode が `yolo` で人間のゲートが無いぶん、暴走を止める役として置く。

コストは限定的で、受け取るのは前回からの**差分のみ**、サブエージェントには既定で付かない
（sweep でレビューを並列起動しても advisor は主セッションの 1 本だけ）。
`advisor.immuneTurns`（既定 3）が割り込み頻度を抑える。

### advisor.syncBacklog: off（既定のまま）

advisor のノートを同期的に割り込ませる閾値。`1` / `3` にすると無人 sweep のブレーキは強くなるが、
そのたびに本線のターンが止まりスループットが落ちる。`advisor.enabled: true` のノート注入と
`immuneTurns`（既定 3）で足りているとみて off のままにしている。暴走が実際に起きたら `3` から試す。

### compaction.thresholdPercent: 50

既定は `-1`（未設定＝omp が `contextWindow - reserve`〈目安 16k または枠の 15%〉付近まで待って発火）。
長い `issue-sweep` / `impl` ではその手前で `task.softRequestBudget` の強制停止が先に来て、
`omp-jev-compaction`（TypeSafe Jev、上記 plugins 節参照）まで届かないことがあった。
枠ギリギリまで溜めてから一気に compact するより、**50% 前後でこまめに** compaction（と Jev の
ツール結果間引き）を回したほうが、hub / gh / テストログのようなツール結果だらけの本線には合う
という判断で試験導入する（issue #23）。

**観測ポイント**: `~/.omp/logs/omp.<date>.*.log` の `jev context` 出現頻度と compact 頻度、
TypeSafe 側のコスト、後半ターンでの「さっき見た情報を読み直す」頻度が減っているか。
**戻し方**: 過発火・コスト増・挙動悪化が見えたら `compaction.thresholdPercent` の値を上げる
（例: 70）か、キーごと削除して既定（`-1`）に戻す。`thresholdTokens` は正の値を設定すると
`thresholdPercent` より優先されるため、percent 側だけで試している間は触らない。

### retry.fallbackChains

`retry.modelFallback` は既定 on だが、行き先を書かないと同一プロバイダ内で粘る。
長時間 sweep では anthropic 側のレート制限が実質の停止要因になるため、**別プロバイダへ逃がす**:

| ロール | 次候補 |
|---|---|
| `default` / `task` | `cursor/claude-sonnet-5-high` → `google/gemini-3.1-pro-preview` |
| `advisor` | `cursor/claude-sonnet-5-high` |
| `smol` / `tiny` / `commit` | `google/gemini-3.5-flash` → `cursor/claude-sonnet-5-low` |
| `slow` | `[]`（フォールバックしない） |

`slow` を空にするのは、opus を日常経路へ戻さないため。難問用に明示的に呼ぶときだけ使う。
キーは**ロール名・モデルセレクタ・`provider/*` ワイルドカード**が使える。未知のモデル名は
起動時に警告されるので、`omp models`（認証済みのみ）と `models.db` で実在を確認してから書く。

### providers.maxInFlightRequests

`issue-sweep --parallel 5` は実装エージェントを最大 5 本走らせる。anthropic への同時リクエストを
`3` に絞ってレート制限に当たる頻度を下げる。絞りすぎると sweep 全体が待ちになるので、
429 が出続けるようなら上げる（実測で調整する値）。

### statusLine.preset: nerd

`symbolPreset: nerd` と揃える（既定は `default`）。

### task.showResolvedModelBadge: true

サブエージェントが実際に解決したモデルをバッジ表示する（既定 `false`）。
ロール経由の間接指定（`scout` → `@smol` → 実モデル）は意図どおり解決されたか分かりにくいので、
sweep でどのロールがどれだけ使われたかを目視できるようにしておく。

### task.enableLsp: true

サブエージェントから LSP を使えるようにする（既定 `false`）。
`review` エージェントの tools に `lsp` を入れているため、これが false だと診断を見られない。
言語サーバー自体は omp が cwd の root marker とバイナリの有無で自動検出する（設定不要）。

### task.softRequestBudget: 400

サブエージェント 1 本あたりのリクエスト上限（既定 `200`、1.5x ≈ 300 で強制停止）。
`issue-sweep` / `impl` のような長寿命の実装サブエージェントは、rename のような広範囲な変更で
既定値に当たって「予算切れ」で強制停止することがあった（例: backend rename が `go build/vet` まで
通っていたのに、force-stop 後の worktree 掃除で成果が消えた）。**グローバル常時 `0`（無効化）にはしない**
（放置並列の暴走ガードを残す）。`400` は sweep での実測に基づく暫定値で、当たる頻度が高ければ上げる。

worktree を残して resume できるようにする側の対応は `omp/skills/issue-sweep/SKILL.md` の
2-2（worktree 再利用）/ 2-6（進捗があれば消さない）/ 2-7（budget切れ判定）を参照（issue #19）。

### task.agentModelOverrides

実在する bundled エージェントは `reviewer` / `scout` / `security-reviewer` / `sonic` / `task` の 5 つ。
ここに無い名前を書いても解決されず黙って無視されるので、存在するものだけを並べる。
`develop` / `develop-slow` / `review` は `agents/` の自前定義。frontmatter 側が `develop`→`@task`、
`develop-slow`→`@slow`（issue-sweep のバッチ 2 回目再試行専用）、`review`→`@task` を指定している。

`sonic`（「Low-reasoning agent for strictly mechanical updates or data collection only」）は
**どのスキルからも呼ばれていなかった空き枠**だったため、`@commit`（luna）に割り当てて
commit メッセージ / PR タイトルの下書き専用に使う（`impl` 2-7 / `issue-sweep` 2-2 手順3。
`../sweep-common/commit-draft.md` 参照）。`scout` は `issue-sweep` フェーズ1-2a のトリアージに使う
（read-only なので Issue 作成を伴う分割実行はできない。分割は 1-2b で `review` が行う）。

### 表示ノイズ抑制

issue-sweep など並列セッション中、メイン画面の表示量を抑えるための設定。`Ctrl+O`（ツール出力の
折りたたみ）はセッション操作のみで永続化する設定は upstream に無いため対象外。

| キー | 値 | 意図 |
|---|---|---|
| `hideThinkingBlock` | `true` | thinking ブロックを表示しない |
| `textVerbosity` | `low` | OpenAI Responses / Codex transport 向けの応答簡潔化。**anthropic（default/task/plan/advisor/slow）には効かない** — 効くのは `smol`/`tiny`/`commit`（luna）経由の呼び出しだけ |
| `display.pinnedAgents` | `collapsed` | 常時ライブ表示せず、数行 + expander に留める（`off` にすると完全に隠せるが、sweep 中の生存確認ができなくなるため既定の `collapsed` を明示的に固定） |
| `statusLine.preset` | `nerd`（変更なし） | tide の Nerd Font アイコン表示（下記）を優先し、`minimal`/`compact` には変更しない。両立しない単一 enum のため、アイコン表示とノイズ低減はトレードオフになる |
| `advisor.enabled` | `true`（変更なし） | ノイズの主因は advisor ではなく thinking ブロック / pinnedAgents / ツールカードの表示量。うるさいときは `advisor.immuneTurns`（既定 3）を上げる、またはセッション単位で advisor を一時的に切る運用で対応し、既定の ON は変えない |

`omp config set` の書き込み先は `~/.omp/agent/config.yml`。dotfiles 側は `omp/config.yml` を
`link_omp` が symlink するので、上記キーの直接編集はこのファイルに対して行う
（「なぜ設定の意図をここに書くか」を参照）。

### symbolPreset: nerd

tide が Nerd Font アイコンを使う環境のため（既定は `unicode`）。

### skills.enableClaudeUser: true

omp は `~/.claude/skills`（自作スキル）を**既定では読まない**。`~/.agents/skills`（外部 agent-skills）は既定 on なので触らない。

## RULES.md

常時適用のユーザールール。omp は `RULES.md` を sticky user rule として扱い、`alwaysApply: true` を強制する。

**実体は `.claude/CLAUDE.md` そのもので、omp 専用のコピーは持たない。** `link_omp` が
`~/.omp/agent/RULES.md` → `dotfiles/.claude/CLAUDE.md` をリンクする。

そうする理由:

- omp は **user レベルの `~/.claude/CLAUDE.md` を読まない**（v18.2.11 で実測。claude の rules
  プロバイダ自体は存在し、プロジェクト側の `.claude/CLAUDE.md` とリポジトリ直下の `CLAUDE.md` は読む。
  隔離した HOME で user レベルだけが無視されることを対照実験で確認した）。そのため omp 用の
  入り口が別途要る
- かつて omp 用に別ファイルを置いていたが、**ツール名だけ差し替える運用は必ず腐る**。実際
  `AskUserQuestion` / `ask` の 2 系統に割れ、`~/dotfiles` 内で omp を起動すると
  `.claude/CLAUDE.md`（プロジェクトルール）と RULES.md（user ルール）が**両方ロードされて**
  矛盾した指示が同時に載った（片方がもう片方を抑止しないことは実測済み）
- 1 ファイルに統合すれば同期ズレが構造的に起きない

**ハーネス固有の記述は本文側で両論併記する。** 片方のツール名に決め打ちしない:

- 選択式の確認ツール: Claude Code は `AskUserQuestion` / omp は `ask`
- 自由入力: Claude Code は `allowFreeText: true` または「Other」選択肢 / omp は自由入力を促す選択肢

## WATCHDOG.md

advisor だけが読む注意書き。omp は user レベル（`~/.omp/agent/WATCHDOG.md`）とプロジェクト側
（`./WATCHDOG.md` / `./.omp/WATCHDOG.md`）を探し、内容を「特に注意すること」として advisor に渡す。
`WATCHDOG.yml` 形式（advisor を複数定義してモデル・tools を割り当てる）もあるが、
ここでは「無人 sweep で実際に起きた逸脱」を列挙するだけなので `.md` を使う。

advisor のノート出力言語は上流 system prompt では設定できないため、`WATCHDOG.md` 先頭の
「出力言語」節に `advise` 本文は日本語で書く旨を明記している（issue #21）。

## extensions/

`session_stop` などのイベントに載る拡張（`export default (pi) => pi.on(...)`）。

**omp は `settings.json` の `hooks.Stop`（Claude Code のシェル形式 Stop Hook）を解釈しない。**
`.claude/hooks/pre/` `.claude/hooks/post/` は読むが、これは omp 独自の JS/TS ツールフックで別物。
そのため sweep の停止ガードは `sweep-stop-guard.ts` として omp ネイティブの `session_stop` に載せている
（`.sweep/queue.txt` に残があるか `state.json` が `phase != terminal` の間は `decision: "block"` を返す）。
`decision: "block"` は advisory な継続の上限（8 回）を消費しないので、長い sweep でも打ち止めにならない。

lock の鮮度（heartbeat 2時間）と PID の親子関係で「自分が持ち主の sweep か」を判定するのは
Claude Code 版フックと同じ。別セッションの sweep や放置された lock では停止を許可する。

## agents/

omp は `.claude/agents` を意図的にスキップする（frontmatter 契約が別物）ため、専用の実体を置く。
モデルは定義に書かず `modelRoles` のロール参照で解決する。方針は `skills/harness-model/`。

## skills/

omp の native provider (priority 100) が claude provider (80) より優先されるため、同名スキルは
ここの版が `~/.claude/skills` 版を上書きする。未移植のスキルは Claude 版にフォールバックする。

Claude Code 版からの書き換え規則:

| Claude Code | omp |
|---|---|
| `Agent(subagent_type=X, model=Y)` | `task(agent=X)`（モデルは書かない） |
| `AskUserQuestion` | `ask` |
| `TaskCreate` / `TaskUpdate` | `todo` |
| `user-invocable`（frontmatter） | 削除（omp に無い概念） |

`sweep-common` は `SKILL.md` を持たない共有リファレンスでスキルとしては登録されないが、
各スキルから `../sweep-common/<file>` の相対パスで参照されるため同じ階層に置く。

## plugins（`~/.omp/plugins/` 管理下。dotfiles には実体もロックファイルも置かない）

`omp plugin install <pkg>` はプラグイン本体を `~/.omp/plugins/node_modules/<name>` に配置し、
登録情報を `~/.omp/plugins/omp-plugins.lock.json` に書く（**`~/.omp/agent/config.yml` は変更しない**。
実機で `git diff omp/config.yml` を確認して検証済み）。dotfiles 側に対応する設定ファイルは置かず、
導入手順とガードだけをここに書く。

### jerryfane/omp-jev-compaction（TypeSafe Jev context compaction）

要約ではなく「もう要らない」と判定した**ツール結果だけ**を落として実効コンテキストを薄くするプラグイン。
落ちた中身は `~/.omp/jev-spill/<hash>.txt` に残り、エージェントは `read` で回収できる（issue #20）。

**秘密情報は Sakana と同じ経路に乗せる（専用の `.env` は増やさない）**:

1. `~/.env`（または `$DOTFILES_DIR/.env`）に `TYPESAFE_API_KEY=...` と `OMP_JEV_PROVIDER=typesafe` を書く
   （プレースホルダは `.env.example`）
2. fish 起動時に `fish/conf.d/secrets.fish` が読んで `set -gx` する。プラグインは環境変数の
   `TYPESAFE_API_KEY` を読むだけなので、fish 経由の起動なら追加のローダは不要
3. **omp のランタイム**（実際にプラグインが動くとき）は fish 経由の起動を前提にする。fish を通らない
   起動経路（systemd / 生 bash 等）は今のところ無い。将来増えたら、Fugu の `load_fugu_env`
   （`lib/tools/codex.sh`）と同じパターンで `$DOTFILES_DIR/.env` を source する。
   **インストール時**（`install.sh` 実行時）は bash 経由で `.env` を直接読む（`lib/tools/omp_jev.sh`
   の `load_omp_jev_env`。fish を経由しないので別ローダが要る — 下記4番）
4. インストールは **`install.sh`（`install_omp_jev` / `lib/tools/omp_jev.sh`）に組み込み済み**。
   `TYPESAFE_API_KEY` が無ければ Fugu と同じく warn してスキップし、圧縮せず従来どおり動く。
   キーがあれば以下を自動実行する:
   1. `~/.local/share/omp-plugins/omp-jev-compaction` へ `git clone`（既にあれば `git pull --ff-only`）
   2. `npm install`（`prepare` フックが `tsc` を実行して `dist/` をビルド）
   3. `omp plugin install <上記パス>`

   **公式 README の `omp plugin install jerryfane/omp-jev-compaction`（bare `owner/repo`）はこの omp
   バージョンでは使えない**（実機で `Invalid package name` エラーを確認）。`github:jerryfane/…` に
   すると名前検証は通るが、omp の github clone 経路は npm の `prepare` ビルドを実行しないため
   `dist/hook.js: declared extension entry not found on disk` で失敗する。そのため dotfiles 側で
   clone→build→`omp plugin install <local path>` を自前で行っている。`~/.omp/plugins/node_modules/`
   配下は `~/.local/share/omp-plugins/omp-jev-compaction` へのシンボリックリンクになるので、
   このソースディレクトリを消さないこと（`./install.sh omp_jev` で `git pull` + 再ビルドされる）

**推奨初期設定**（`~/.env`）:

```bash
TYPESAFE_API_KEY=...
OMP_JEV_PROVIDER=typesafe
# OMP_JEV_ALLOW_DROPPING_CALLS は書かない（既定 off のままにする）
```

| 変数 | 既定 | メモ |
|---|---|---|
| `TYPESAFE_API_KEY` | — | **必須**（TypeSafe 経路）。`~/.env` に置く |
| `OMP_JEV_PROVIDER` | auto | `typesafe` を明示 |
| `OMP_JEV_CONTEXT` | on | `0` で continuous 削減オフ |
| `OMP_JEV_ALLOW_DROPPING_CALLS` | off | **オフのまま**。`1` にしない |
| `OMP_JEV_SPILL` | on | `0` は非推奨（spill が無いと回収できず削減が恒久ロスになる） |

**段階導入。** 一気に全ロールへは入れない。まず `issue-sweep` / 長い `impl` から効かせ、1〜2 バッチ
観察して問題なければ全体へ広げる。スコープを絞る手段は 2 つ:

- 特定ディレクトリだけ: `.omp/hooks/pre/jev.ts` をそのプロジェクトに置く
- セッション単位: 普段は `~/.env` で `OMP_JEV_CONTEXT=0`（オフ）にしておき、sweep を起動する
  シェルだけ `OMP_JEV_CONTEXT=1 issue-sweep ...` のように上書きする

効きが悪ければ即オフ: `OMP_JEV_CONTEXT=0` または `omp plugin disable omp-jev-compaction`。

**検証**（fish 起動後）:

```bash
echo $TYPESAFE_API_KEY   # 埋まっていること（値はチャットに出さない）
omp plugin list
grep "jev context" ~/.omp/logs/omp.$(date +%F).*.log | tail -3
```

**やらないこと**: OpenRouter 常用、`OMP_JEV_ALLOW_DROPPING_CALLS=1`、`task.softRequestBudget`
（issue #19 の範囲）への言及の混在、会話が TypeSafe に送られることの社内ポリシー確定（必要なら別 Issue）。
