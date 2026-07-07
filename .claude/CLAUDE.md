# Claude Instructions

## Complexity & readability
- Do not increase complexity without a clear reason.
- Prefer the simplest solution that satisfies the requirements and existing constraints.
- Complexity is allowed only when it reduces overall risk or improves maintainability (e.g., removes duplication, clarifies invariants, improves testability).
- Match the complexity to the task: small tasks should use small, straightforward changes.
- Optimize for readability: clear naming, small functions, and predictable control flow.

## Testing
- Bug fixes must include a regression test:
  - Add a test that fails before the fix and passes after the fix.
  - Place it in the closest relevant test suite.

## Execution Proof（実行事実の確認）
- 「成功」「完了」「保存済み」「反映済み」「commit済み」「push済み」「PR作成済み」は、同一ターンまたは直近の tool_result で実行事実を確認できた場合のみ言う。
- 自然文の予定・推測・過去の記憶を作業事実として扱わない。
- APIエラー・tool失敗・permission拒否・command not found・refspec error・exit非0は成功扱いにしない。
- commit 後は `git log -1 --oneline` 等で確認する。push 後は push 成功ログまたは `git status -sb` 等で確認する。PR作成後は PR URL を確認する。
- ファイル編集後は Edit/Write の tool_result だけで完了扱いにせず、Read / grep / git diff 等で対象箇所が実際に反映されたことを確認する。
- 確認できない場合は「未確認」「未実行」「失敗」と報告し、そこで止まる。

## Language
- User-facing responses must use the same language as the instructions used.

## Writing（文章品質）
出力する文章（応答・日報・提案書・ドキュメント・コミットメッセージ等すべて）は、次の判断基準を頂点とする。根拠と詳細do/don'tは Drive `VeriCerts/00_管理・概要/CC文章品質ベストプラクティス.md`、深い自己添削は `/writing-lint` を参照。手本は吉田自身の入力文（メモリ [[user-writing-style]] 参照）。

**北極星（迷ったらこの一問だけに照らす）**: 良い応答とは、相手が最小の労力で必要を得られたものを指す。説明量ではない。各文・各段落・各装飾は「問いに答えるのに不可欠か」だけで残し、迷ったら消す。**デフォルトは書かない**。

具体ルール（北極星の実装。衝突したら北極星が優先）:
- **足す理由を立証できた要素だけ残す**。頼まれていない選択肢の列挙・次アクション提案・予防的な補足・「他に何かあれば」式の締めは立証できないので書かない。
- **視認性を設計する**（文字量とは別軸）。目が一目で構造を拾える形にする。項目の間に余白を空け、一行を短くし、要点を行頭に置く。塊で詰めない。
- **整理してから出す**（量で縛らない）。論点が複数でも、一気に出してよい。悪いのは整理せず盛って投げること。見出し・区切り・順序・強調は「数を絞る」道具ではなく「構造を立てて読み手を迷わせない」道具として使う。「○文以内」「太字1つ」「論点1つ」のような量の制限は表層なので使わない。
- **結論を先頭に置く**（front-load / BLUF）。前置き・経緯・背景から書き始めない。
- **能動態・動詞主導・断定で書く**。受動「〜される」とヘッジ「〜かもしれません」を削り、行為者を主語にする。
- **不要語を全部削る**。一文一義。読点が4つ／一文が3行を超えたら分割。「実装を行う→実装する」のように縮める。
- **具体で書く**。固有名詞・数字・実例を入れ、一般論で薄めない。動作を「〜の実施」「〜化」と抽象名詞に逃がさない。
- **テンプレ句を使わない**（禁止句）: 「〜することが重要です」「さまざまな／あらゆる」「以下に示します」「〜と言えるでしょう」「総じて」、根拠なき誇張副詞（劇的に・大幅に）、バズワード（シームレス・革新的）、過剰な箇条書き・絵文字・感嘆符。英文では "It's important to note" "delve" "leverage" "robust" "Furthermore" 等。
- **用語は1概念=1語**で固定。
- カタカナ語の安易な多用を避け、和語/漢語で言えるものは言う（定着語は可）。

## Asking the user
- 不明点・前提条件が曖昧な点・複数の妥当な選択肢がある場合は、推測で進めずに `AskUserQuestion` で選択式に確認する。テキストだけで質問しない。
- 各選択肢の `description` は**1〜2文まで**。判断材料（推奨理由・主要なトレードオフ）だけを書く。
- 1回あたり最大4問にまとめる。確認漏れがあれば次のターンで再度 `AskUserQuestion` を出す。
- すでに明示された指示や、コード/ドキュメントを読めば一意に決まる事項についてはわざわざ聞かない（読んで把握する）。
- 自由入力の受け口は自動付与される「Other」に任せる（`allowFreeText` というパラメータは存在しないので渡さない）。

### AskUserQuestion Payload Budget（壊れたJSONを送らない）
`AskUserQuestion` は「判断の入力欄」であり、「調査報告の置き場」ではない。

- options は原則 2〜4個。label は短く（1〜5語）。
- description に長い背景・ログ・diff・コードブロック・長いパス一覧を入れない。
- 判断材料が長い場合は、**本文で先に説明してから**、AskUserQuestion 側は短い選択肢だけにする。
- 複数論点を1つの question に詰め込まない（論点が複数なら questions を分けるか、ターンを分ける）。
- payload が大きくなりそうな場合は例外として AskUserQuestion を使わず、本文で「A/B/C のどれにしますか」と短く聞く。
- InputValidationError が出たら、**同じ payload を再送しない**。選択肢数と description を削って再提示する。

## Git Commits
- コミットメッセージは `<type>: <説明>` の形式で書く
- type は英語（feat, fix, update, refactor, docs, test など）
- 説明は日本語で簡潔に書く
- 例: `feat: ユーザー認証機能を追加`, `fix: ログイン時のエラーを修正`
- `git commit` / `git push` で `--no-verify` を使わないこと。pre-commit および pre-push フックは必ず通す。フックが失敗した場合はスキップせず、原因を調査・修正する。

## Git Merge
- PR をマージする際は squash せず、マージコミット方式（merge commit）を使うこと。
- `gh pr merge` を使う場合は `--merge` を明示する（`--squash` / `--rebase` は使わない）。
- ローカルで `git merge` する場合も fast-forward ではなく `--no-ff` でマージコミットを残す。

## Dotfiles Sync（環境同期）
- `~/.dotfiles` は `git pull` で一括同期しない。origin/main の差分は危険設定を含みうるため、項目単位で確認してから取り込む。
- 明示承認なしに取り込まない対象: `settings.json` / `hooks/` / `permissions`(allow・deny) / `defaultMode` / `issue-sweep` / `refine-sweep` / `issue-split-auto` / `bypassPermissions` / `git push:*`・`git commit:*`・`gh pr:*`・`gh issue:*` 等の広範allow。
- 取り込みが必要な場合は diff を提示し、承認を得てから項目単位で適用する。

## Libraries
- Prefer using well-known, widely adopted libraries when they simplify the solution, reduce risk, or improve maintainability.
- Do not re-implement common, well-solved functionality that a major library already provides (e.g., parsing, validation, date/time handling, HTTP clients), unless there is a clear constraint (performance, bundle size, security policy, dependency restrictions).
- Keep dependencies minimal: introduce a new library only when it provides clear value over standard library or existing dependencies.
- When adding a library, choose a stable option with strong community support and maintenance; document the reason briefly (e.g., in a comment, PR description, or dependency note).

