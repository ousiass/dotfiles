# omp (oh-my-pi) の設定

`install.sh` の `link_omp` が、このディレクトリを `~/.omp/agent/` 配下へ symlink する。

| dotfiles | リンク先 |
|---|---|
| `omp/config.yml` | `~/.omp/agent/config.yml` |
| `omp/RULES.md` | `~/.omp/agent/RULES.md` |
| `omp/agents/` | `~/.omp/agent/agents/` |
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
| `default` | `claude-sonnet-5:high` | 主セッション。最終判断と統合 |
| `smol` | `gpt-6-luna:medium` | 探索・大量サブエージェントの fan-out |
| `tiny` | `gpt-6-luna:medium` | セッションタイトル・メモリ・auto thinking の難易度分類。分類が後段の判断に響くので low にしない |
| `commit` | `gpt-6-luna:medium` | コミットメッセージと changelog。`<type>: <日本語説明>` の規約を守らせるため low にしない |
| `task` | `claude-sonnet-5:high` | 汎用の実装サブエージェント |
| `slow` / `plan` / `advisor` | `claude-opus-5:high` | 難しいレビュー・設計 |

モデル ID と effort は `~/.omp/agent/models.db`（omp のカタログ）で実在を確認する。
`omp models` は**認証済みプロバイダしか表示しない**ため、未認証のものはカタログ側を見る。

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

**omp の rules プロバイダに `claude` は存在せず、`~/.claude/CLAUDE.md` は読まれない**
（skills と MCP は Claude Code の資産を継承するが、rules だけは継承されない）。
そのため `.claude/CLAUDE.md` と同じ方針をここに置く。内容は原本と揃え、差分は次の 2 点だけにする:

- `AskUserQuestion` → `ask`（omp のツール名）
- 自由入力の指定方法（omp の `ask` に `allowFreeText` は無い）

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
| `TaskCreate` | `todo` |
| `user-invocable`（frontmatter） | 削除（omp に無い概念） |

`sweep-common` は `SKILL.md` を持たない共有リファレンスでスキルとしては登録されないが、
各スキルから `../sweep-common/<file>` の相対パスで参照されるため同じ階層に置く。
