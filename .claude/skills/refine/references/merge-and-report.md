# refine 系 マージ・レポート・終了処理（フェーズ3）

`refine` / `refine-git` が共有する終了フロー。`skill_name` / `pr_number` / `branch` / `iter` / `findings` / `start_ts` は呼び出し元で設定済みとする。

## 1. 経過時間と status の確定

```bash
total_dur=$(( $(date +%s) - start_ts ))
```

status は以下の enum から選ぶ。**これ以外の文字列（`stuck` 等）を作らない** — 呼び出し元の `issue-sweep` が parse する:

- 閾値到達 → `clean`（マージへ進む）
- `max_iter` 到達 → `iter_limit`（マージしない）
- 2 反復連続で `critical + major` が減らない → `no_progress`（マージしない）
- agent failure → `agent_failed`（マージしない）
- マージ自体の失敗 → `merge_failed` / CI 修正を諦めた → `ci_gave_up`

## 2. CI 緑を待って直接マージ → Issue close

status=`clean` かつ `--no-merge` 未指定の場合のみ実行する。`--no-merge` 指定時はこのステップを完全スキップして 3 へ。

```bash
sweep_notify "$skill_name: waiting for CI green" "PR #${pr_number}" ":hourglass:"

# statusCheckRollup ポーリング
respawn=0
while true; do
  payload=$(gh pr view "$pr_number" --json state,mergedAt,statusCheckRollup)
  state=$(echo "$payload" | jq -r .state)
  merged=$(echo "$payload" | jq -r '.mergedAt // "null"')
  failed=$(echo "$payload" | jq -r '[.statusCheckRollup[]? | select(.conclusion == "FAILURE") | .name] | join(",")')
  pending=$(echo "$payload" | jq '[.statusCheckRollup[]? | select(.conclusion == null and .status != "COMPLETED")] | length')

  [[ "$state" == "MERGED" ]] && break

  if [[ "$state" == "CLOSED" && "$merged" == "null" ]]; then
    status="merge_failed"; break
  fi

  if [[ -n "$failed" && "$pending" -eq 0 ]]; then
    if (( respawn >= 2 )); then status="ci_gave_up"; merge_failure="$failed"; break; fi
    respawn=$((respawn+1))
    gh pr comment "$pr_number" --body "$skill_name: マージ前 CI 失敗を検知（attempt ${respawn}/3、checks: $failed）。修正 agent を再起動します。"
    # フェーズ2-4 と同じ fix プロンプトで Agent(claude) 起動
    # CI 修正に限り、ワークフロー/設定ファイル等の差分外変更を許可する
    continue
  fi

  # 全 check 完了 ∧ FAILURE なし ∧ OPEN → 直接マージ
  if [[ "$pending" -eq 0 && -z "$failed" && "$state" == "OPEN" ]]; then
    if gh pr merge "$pr_number" --merge --delete-branch 2>/tmp/refine-merge-err; then
      sweep_notify "$skill_name: merged" "PR #${pr_number}" ":white_check_mark:"
      continue  # 次ループで state==MERGED で break
    else
      err=$(cat /tmp/refine-merge-err)
      status="merge_failed"; merge_failure="$err"; break
    fi
  fi

  sleep 60
done

# マージ成功時、リンクされた Issue を close
if [[ "$state" == "MERGED" ]]; then
  closing_issues=$(gh pr view "$pr_number" --json closingIssuesReferences -q '.closingIssuesReferences[].number')
  for issue in $closing_issues; do
    gh issue close "$issue" --comment "Closed by PR #${pr_number} (refined and merged via /${skill_name}, iters=${iter})"
  done
fi
```

## 3. テレメトリ最終行を追記（status 込み）

`state-and-telemetry.md` の追記コードに `status` を足した 1 行を append する。

## 4. 最終カウントの確定

- **`--no-merge` 指定時（`issue-sweep` からの呼び出しは常にこれ）は re-review を行わない。** 最終反復 2-1 のレビュー結果をそのまま最終カウントとして使う。マージしないなら「マージ直前の状態を再確認する」意味がなく、呼び出し元が自前で CI ゲートを持っているので二重になる（PR ごとにレビュー agent 3〜5 本ぶんの周回が丸損だった）
- **マージまで行う場合のみ**、status=`clean` を主張する前にもう一度フェーズ2-1 のレビューを走らせて閾値を満たしていることを再確認する（推定で clean にしない）
- どちらの場合も最終カウントを `$SWEEP_DIR/refine-metrics.jsonl` に append し、`OWNS_STATE=true` なら state.json の `last_counts` / `updated_at` を更新する

## 5. state.json を terminal 化

**`OWNS_STATE=false`（呼び出し元の sweep が state.json を所有）のときはこの手順を丸ごとスキップする。** ここで terminal 化すると sweep の Stop Hook のブロックが解除され、キュー途中で静かに終わる。

```bash
if [[ "$OWNS_STATE" == "true" ]]; then
  reason="thresholds_met"   # または iter_limit / no_progress / agent_failed / merge_failed / ci_gave_up / aborted
  jq --arg reason "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.phase = "terminal" | .termination_reason = $reason | .updated_at = $now' \
     "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
fi
```

## 6. Markdown レポート生成

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
report="$SWEEP_DIR/report-${skill_name}-${ts}.md"
cat > "$report" <<EOF
# ${skill_name} report — $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Target
- PR: #${pr_number}
- Branch: ${branch}
- Scope: ${scope_label}
- Iterations: ${iter}
- Final status: **${status}**
- Elapsed: ${total_dur}s

## Findings trend

| Iter | Critical | Major | Minor |
|---|---|---|---|
$(jq -r --arg skill "$skill_name" --argjson pr "$pr_number" 'select(.source == $skill and .pr_number == $pr) | "| \(.iter) | \(.critical) | \(.major) | \(.minor) |"' "$SWEEP_DIR/refine-metrics.jsonl")

## Remaining issues
$(if [[ "$status" != "clean" ]]; then echo "$findings" | jq -r '.critical[]?, .major[]?, .minor[]? | "- [\(.file // "?"):\(.line // 0)] \(.msg)"'; else echo "なし（閾値到達）"; fi)
EOF

echo "Report written to $report"
```

`scope_label` は呼び出し元が設定する:
- `refine`: `リポジトリ全体`
- `refine-git`: `\`${base_ref}...HEAD\` の差分のみ（N files）`

`refine-git` はこの後に `## Out of scope` セクションを追記する（`refine-git/SKILL.md` 参照）。

## 7. 通知

```bash
sweep_notify "$skill_name done" "PR #${pr_number}: ${status}, ${iter} iters" "<emoji>"
```

`issue-sweep` と同じ `sweep_notify` 関数を流用（`.sweep/notify.url` が読まれる）。

## 8. 呼び出し元への返答

最終メッセージとして以下の JSON 1行を出力する。`issue-sweep` の engineer agent などが parse できるよう、Markdown レポートのパス案内に**先行して** JSON 行を出すこと。

```json
{"status":"<clean|iter_limit|no_progress|agent_failed|merge_failed|ci_gave_up>","skill":"<refine|refine-git>","pr_number":<N>,"iter":<K>,"critical_remaining":<N>,"major_remaining":<N>,"minor_remaining":<N>,"merged":<true|false>,"report_path":".sweep/report-<skill>-<ts>.md"}
```

- `--no-merge` 指定時は `merged: false` で固定（マージをしていないため）
- `iter_limit` / `no_progress` でも `critical_remaining=0 ∧ major_remaining=0` のときは呼び出し元が「軽微残りで OK」と判定できる（`issue-sweep` のマージゲートはこの 2 つだけを見る）
- レポートパスはユーザー向けの最終表示と JSON 両方に含める

## 失敗時の挙動

- review agent / fix agent のいずれかが failure → ループ中断、テレメトリ最終行に `status: "agent_failed"` を記録、レポート生成して終了
- worktree 作成失敗 → そもそも開始しない
- ネットワーク断・gh エラー → 60秒待って3回までリトライ、それでもダメならユーザー判断
