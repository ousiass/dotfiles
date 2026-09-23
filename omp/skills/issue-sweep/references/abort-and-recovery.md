# --abort と失敗時のリカバリ

**このファイルは `--abort` 指定時、または処理が失敗したときだけ読めばよい。**

## --abort 処理

引数が `--abort` の場合は以下を実行して終了する（他フェーズに進まない）:

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
rm -f "$SWEEP_DIR/queue.txt" "$SWEEP_DIR/lock" "$SWEEP_DIR/attempts.json"
# state.json があれば terminal 化（履歴を残すため削除しない）
if [[ -f "$SWEEP_DIR/state.json" ]]; then
  jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.phase = "terminal" | .termination_reason = "aborted" | .updated_at = $now' \
    "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
fi
# 残った worktree の参照だけ掃除する（ディレクトリが実在する worktree は消えない。下記「budget切れ／
# force-stop からの再開」参照）
git worktree prune
```

完了後「sweep を中止しキュー / ロックを削除しました」とユーザーに報告。

## budget切れ／force-stop からの再開

`task.softRequestBudget`（既定 200、dotfiles では 400 に上げてある。`omp/README.md` 参照）に
当たった、あるいは agent がクラッシュした場合、**進捗（コミット済み or 未コミットの変更）がある
worktree は 2-6 が意図的に削除しない**。同じバッチが `attempts < 2` でリトライされるときは、
2-2 手順1 が `git worktree list` から同じ worktree を見つけて自動的に再利用し、
`git log <base>..HEAD` / `git status` で完了済み Issue を確認してから続きに着手する。
**手動で何もする必要はない。**

`attempts >= 2` で諦めた場合や、sweep セッションそのものを中断した場合は worktree がそのまま残る。
再開したいときは:

```bash
cd <worktree のパス>   # 諦めたバッチの Issue コメント、または 3-1 レポートの
                        # 「Preserved worktrees」セクションに記載されている
git log <base_branch>..HEAD --oneline   # どこまで進んでいたか確認
git status                              # 未コミットの変更を確認
```
中身を活かせるなら手動で `gh pr create` するか、続きを実装してから `/refine-git` にかける。
不要なら `git worktree remove --force <path>` で消す。

## 失敗時の挙動

- **1 バッチの失敗で sweep 全体を止めない。** `attempts.json` が 2 に達したバッチだけ諦め、キューから該当行を消して metrics に `agent_failed`（budget切れなら `budget_exhausted`）を記録し、残りのバッチを流し続ける
- 諦めたバッチは**必ずキューから消す**。残すと停止ガードが停止をブロックし続けて sweep が終われない（worktree はキューとは別物なので、進捗があれば消さずに残す — 上記参照）
- 観測時の `CLOSED ∧ merged == false`（手動 close）は 1 回目は agent 再起動、2 回連続でユーザー判断
- キューファイルが壊れた場合は `--abort` で全削除してフェーズ1からやり直す
- **すべてのバッチが諦めに終わった場合も、完了報告フェーズに進んで terminal 化とレポート生成を行う**（`termination_reason = "batch_failed"`）。記録が残らないまま終わるのが最悪
