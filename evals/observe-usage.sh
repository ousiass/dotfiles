#!/usr/bin/env bash
# 見積もりの根拠を作る。過去に omp で実際に動いた session（~/.omp/agent/sessions）の使用量から、
# impl / issue-sweep の 1 セッションあたりの分位点を計算して calibration.json を出す。モデルは呼ばない。
#
#   evals/observe-usage.sh [sessions-dir] > evals/calibration.json
#
# 1 セッション = トップレベルの <ts>_<id>.jsonl と、その下のサブエージェントの jsonl の assistant 応答の usage 合計。
# 区分けは最初のユーザー発話で決める:
#   impl         `/impl ` か `/impl-wt ` で始まる
#   sweep_2to3   `/issue-sweep` に Issue 番号が 2〜3 個
# 大きな JSONL を全部読むので、数分かかる。
set -uo pipefail

root="${1:-$HOME/.omp/agent/sessions}"
[[ -d "$root" ]] || {
    echo "observe-usage.sh: $root が無い" >&2
    exit 2
}

rows="$(mktemp)"
trap 'rm -f "$rows"' EXIT

for f in "$root"/*/20*.jsonl; do
    [[ -f "$f" ]] || continue
    d="${f%.jsonl}"
    files=("$f")
    if [[ -d "$d" ]]; then
        while IFS= read -r s; do files+=("$s"); done < <(find "$d" -name '*.jsonl')
    fi
    first="$(jq -rs '[.[] | select(.type == "message" and .message.role == "user")][0] | .message.content | if type == "array" then .[0].text else . end // ""' "$f" 2>/dev/null | tr '\n' ' ' | cut -c1-120)"
    jq -s -c --arg first "$first" '
      [ .[] | select(.type == "message" and .message.role == "assistant") | .message.usage // empty ] as $u
      | {first: $first, calls: ($u | length), out: ([$u[].output] | add // 0), fresh: ([$u[] | (.input // 0) + (.cacheWrite // 0)] | add // 0), cache_read: ([$u[].cacheRead] | add // 0)}' "${files[@]}" >>"$rows" 2>/dev/null
done

jq -s '
  def q($p): sort | .[((length - 1) * $p | floor)];
  def dist(f): [.[] | f] | {n: length, p25: q(0.25), p50: q(0.5), p75: q(0.75), max: max};
  def nissues: (.first | split(" ") | .[1:] | (map(startswith("#")) | index(false) // length));
  [.[] | select(.first | test("^/impl(-wt)? "))] as $impl
  | [.[] | select(.first | test("^/issue-sweep")) | select(nissues >= 2 and nissues <= 3)] as $sweep
  | def cls($rows; $p): {n: ($rows | length), calls: ($rows | dist(.calls) | .[$p]), out: ($rows | dist(.out) | .[$p]), fresh: ($rows | dist(.fresh) | .[$p]), cache_read: ($rows | dist(.cache_read) | .[$p])};
  {
    provenance: "~/.omp/agent/sessions の実測（omp。impl \($impl | length) セッション、issue-sweep の Issue 2〜3 件 \($sweep | length) セッション。実 repo での実行で、eval の題材より大きい。claude -p の実測は無い）。evals/observe-usage.sh で作り直せる",
    weights: {light: "impl_p25", normal: "impl_p50", heavy: "sweep_2to3_p75"},
    classes: {
      impl_p25: cls($impl; "p25"), impl_p50: cls($impl; "p50"), impl_p75: cls($impl; "p75"),
      sweep_2to3_p50: cls($sweep; "p50"), sweep_2to3_p75: cls($sweep; "p75")
    }
  }' "$rows"
