# shellcheck shell=bash
# grade.sh と rescore.sh が共有する、採点の小さな部品。source して使う。

# expand_issue_refs <正規表現> <Issue 番号の対応表（JSON の配列。[i-1] がタスクの中の番号 i の GitHub の番号。空文字ならそのまま）>
#   正規表現の中の #<n>（タスクの中の番号）を (#<n>|#<GitHub の番号>) に直す。
#   試験用 repo（--remote）では、エージェントは Issue を GitHub の番号（#12 など）で書く。tasks.jsonl の answer_includes の #3 のままだと、
#   「3 件目の Issue を #12 と書いた」正しい回答が落ちる。ローカルの実行（対応表なし）では何も変えない。
expand_issue_refs() {
    local re="$1" map="${2:-}" out="" pre num suf g
    local pat='^(.*)#([0-9]+)(.*)$'
    if [[ -z "$map" ]]; then
        printf '%s' "$re"
        return 0
    fi
    while [[ "$re" =~ $pat ]]; do
        pre="${BASH_REMATCH[1]}"
        num="${BASH_REMATCH[2]}"
        suf="${BASH_REMATCH[3]}"
        g="$(jq -r --argjson i "$num" '.[$i - 1] // empty' <<<"$map")"
        if [[ -n "$g" ]]; then
            out="(#${num}|#${g})${suf}${out}"
        else
            out="#${num}${suf}${out}"
        fi
        re="$pre"
    done
    printf '%s%s' "$re" "$out"
}

# 検証ゲート（impl の 2-6）を実際に起動したコマンドか: verify-scope.sh を --type 付きで、コマンドの位置（先頭、または ; & | ( 改行 のあと）で呼んでいる。
#   - 先頭だけだと、`sed -i … && ./test.sh; echo exit=$?; verify-scope.sh --type fix …` のようにつなげて呼んだゲートを見落とす（Phase 2 の v1b で観測）
#   - --type が無い呼び出し（--profile-path。プロファイルを作るだけでゲートではない）は数えない
#   - echo などの文字列に書いただけでは通らない
# shellcheck disable=SC2034 # rescore.sh が読む
VERIFY_SCOPE_GATE_RE='(^|[;&|(]|\n) *((bash|sh) +)?[^ ;&|]*verify-scope[.]sh( [^;&|\n]*)? --type( |$)'

# CI の通過を確かめたか（ci_waited）の jq プログラム。入力は actions.jsonl（jq -s で配列にしたもの）。
# 最後の gh pr create のあとに、pass を返した gh pr checks か、gh pr view --json statusCheckRollup がある。
# 後者の pass は、gh のラッパー（lib/gh-record.sh）が Actions の run の状態から記録する
# shellcheck disable=SC2034 # grade.sh が読む
CI_WAITED_JQ='
    def ci_read: (.cmd | startswith("gh pr checks")) or ((.cmd | startswith("gh pr view")) and (.cmd | contains("statusCheckRollup")));
    (to_entries | map(select(.value.cmd | startswith("gh pr create"))) | last | .key) as $i
    | $i != null and (to_entries | any(.key > $i and (.value | ci_read) and .value.result == "pass"))'
