# refine 系 マージ・レポート・終了処理（フェーズ3）

`refine` / `refine-git` が共有する終了フロー。`skill_name` / `pr_number` / `branch` / `iter` / `findings` / `start_ts` は呼び出し元で設定済みとする。

## 1. 経過時間と status の確定

```bash
total_dur=$(( $(date +%s) - start_ts ))
```

- 閾値到達 → `clean`（マージへ進む）
- `max_iter` 到達 → `iter_limit`（マージしない）
- agent failure → `agent_failed`（マージしない）

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

## 4. 最終 review を再実行して last_counts / evidence を確定

- status=`clean` を主張する場合は **必ずもう一度フェーズ2-1 のレビューを走らせ**、最新カウントが閾値を満たしていることを再確認する（推定で clean にしない）
- 結果を `.sweep/refine-metrics.jsonl` に append し、state.json の `last_counts` / `evidence` / `updated_at` を更新

## 5. state.json を terminal 化

```bash
reason="thresholds_met"   # または iter_limit / agent_failed / merge_failed / ci_gave_up / aborted
jq --arg reason "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.phase = "terminal" | .termination_reason = $reason | .updated_at = $now' \
   .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
```

## 6. Markdown レポート生成

`## Evidence` セクション必須（state.json の `evidence` をそのまま引用）。

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
report=".sweep/report-${skill_name}-${ts}.md"
mkdir -p .sweep
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
$(jq -r --arg skill "$skill_name" --argjson pr "$pr_number" 'select(.source == $skill and .pr_number == $pr) | "| \(.iter) | \(.critical) | \(.major) | \(.minor) |"' .sweep/refine-metrics.jsonl)

## Evidence

$(jq -r '.evidence[] | "- \(.)"' .sweep/state.json)

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
{"status":"<clean|iter_limit|agent_failed|merge_failed|ci_gave_up>","skill":"<refine|refine-git>","pr_number":<N>,"iter":<K>,"critical_remaining":<N>,"major_remaining":<N>,"minor_remaining":<N>,"merged":<true|false>,"report_path":".sweep/report-<skill>-<ts>.md"}
```

- `--no-merge` 指定時は `merged: false` で固定（マージをしていないため）
- `iter_limit` でも `critical_remaining=0 ∧ major_remaining=0` のときは呼び出し元が「軽微残りで OK」と判定できる
- レポートパスはユーザー向けの最終表示と JSON 両方に含める

## 失敗時の挙動

- review agent / fix agent のいずれかが failure → ループ中断、テレメトリ最終行に `status: "agent_failed"` を記録、レポート生成して終了
- worktree 作成失敗 → そもそも開始しない
- ネットワーク断・gh エラー → 60秒待って3回までリトライ、それでもダメならユーザー判断
