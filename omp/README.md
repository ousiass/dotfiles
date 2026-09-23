# omp (oh-my-pi) の設定

`install.sh` の `link_omp` が、このディレクトリを `~/.omp/agent/` 配下へ symlink する。

| dotfiles | リンク先 |
|---|---|
| `omp/config.yml` | `~/.omp/agent/config.yml` |
| `omp/RULES.md` | `~/.omp/agent/RULES.md` |
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
| `slow` | `claude-opus-5:high` | **難問を突破するときだけ**。通常の経路からは呼ばれない |
| `smol` / `tiny` / `commit` | `gpt-6-luna:medium` | 探索の fan-out・タイトル/メモリ・コミットメッセージ |
| `vision` | `claude-sonnet-5:high` | 画像。未設定だと default に落ちるので明示する |

opus は `slow` だけに限定する。レビュー（`reviewer` / `security-reviewer` / 自前の `review`）は
sweep が何度も並列起動するため、ここを opus にすると消費が跳ねる。sonnet で回し、
行き詰まったときに `--slow` や `/model` で opus に切り替える。

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

### task.agentModelOverrides

実在する bundled エージェントは `reviewer` / `scout` / `security-reviewer` / `sonic` / `task` の 5 つ。
ここに無い名前を書いても解決されず黙って無視されるので、存在するものだけを並べる。
`develop` / `review` は `agents/` の自前定義で、frontmatter 側が `@task` / `@slow` を指定している。

### symbolPreset: nerd

tide が Nerd Font アイコンを使う環境のため（既定は `unicode`）。

### skills.enableClaudeUser: true

omp は `~/.claude/skills`（自作スキル）を**既定では読まない**。`~/.agents/skills`（外部 agent-skills）は既定 on なので触らない。

## RULES.md

常時適用のユーザールール。omp は `RULES.md` を sticky user rule として扱い、`alwaysApply: true` を強制する。

**user レベルの `~/.claude/CLAUDE.md` は読まれない。** claude の rules プロバイダ自体は存在し、
プロジェクト側の `.claude/CLAUDE.md` とリポジトリ直下の `CLAUDE.md` は読む（v18.2.11 で実測。
隔離した HOME で user レベルだけが無視されることを対照実験で確認した）。user レベルが対象外なので、
`.claude/CLAUDE.md` と同じ方針をここに置く。

**内容は原本と完全に一致させる（差分は H1 見出しだけ）。** `~/.claude` が `dotfiles/.claude` への
symlink なので、`~/dotfiles` 内で omp を起動すると `.claude/CLAUDE.md` が**プロジェクトルール**として
読まれ、user レベルの RULES.md と並んで有効になる（片方がもう片方を抑止することはない。
両方ロードされることを実測で確認済み）。ここで文言が割れていると「`AskUserQuestion` で聞け」と
「`ask` で聞け」が同時に指示される。rules をプロバイダ単位で切る設定は無く、`--no-rules` は
全ルールを落とすので使えない。

そのため**ツール名はどちらか一方に決め打ちせず、両ハーネスを併記する**:

- 選択式の確認ツール: Claude Code は `AskUserQuestion` / omp は `ask`
- 自由入力: Claude Code は `allowFreeText: true` または「Other」選択肢 / omp は自由入力を促す選択肢

この書き方なら、どちらのハーネスが両ファイルを同時に読んでも矛盾しない。

## WATCHDOG.md

advisor だけが読む注意書き。omp は user レベル（`~/.omp/agent/WATCHDOG.md`）とプロジェクト側
（`./WATCHDOG.md` / `./.omp/WATCHDOG.md`）を探し、内容を「特に注意すること」として advisor に渡す。
`WATCHDOG.yml` 形式（advisor を複数定義してモデル・tools を割り当てる）もあるが、
ここでは「無人 sweep で実際に起きた逸脱」を列挙するだけなので `.md` を使う。

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
