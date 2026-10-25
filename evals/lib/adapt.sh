#!/usr/bin/env bash
# ハーネスごとの生の出力を、共通の形に直す。run.sh から source される。
#
# どちらも次の形の JSON を標準出力へ出す:
#   { "model": "<id|null>",
#     "events": [ {owner, tool, agent, cmd, path, skill} ... ],   tool は ask / task / bash / read / edit / write / skill ...
#     "calls":  [ {owner, in, out} ... ],                         1 行 = モデル呼び出し 1 回。in は入力側の合計（新規 + cache 読み + cache 書き）
#     "final_text": "<最後の回答>" }
# owner はその呼び出しをしたエージェント（main か、task の agent 名）。by_agent の集計に使う。
#
# 形式の根拠:
#   omp    実際のセッション JSONL（~/.omp/agent/sessions/...）を読んで確かめた形。サブエージェントは
#          <session>/<name>.jsonl に別ファイルで残り、session 行に parentSession が付く。
#   claude `claude -p --output-format stream-json --verbose` の形（assistant 行の message.usage / content の tool_use、
#          サブエージェントの行に付く parent_tool_use_id、同じ応答が複数行に分かれるため message.id で重複を除く）。
#          この環境ではモデルを呼べないので、実機の出力で確かめていない（Phase 1 の最初に確かめる）。

adapt_claude() { # <agent.out>
    jq -s '
      def tool_name: ({AskUserQuestion: "ask", Task: "task", Agent: "task", Bash: "bash", Read: "read", Edit: "edit", MultiEdit: "edit", Write: "write", Skill: "skill"}[.] // ascii_downcase);
      [.[] | select(.type == "assistant")] as $asst
      | ([$asst[] | .message.content[]? | select(.type == "tool_use" and (.name == "Task" or .name == "Agent")) | {key: .id, value: (.input.subagent_type // "general-purpose")}] | from_entries) as $sub
      | def owner: if .parent_tool_use_id then ($sub[.parent_tool_use_id] // "unknown") else "main" end;
      {
        model: ([.[] | select(.type == "system" and .subtype == "init") | .model] | first // null),
        events: [ $asst[] | owner as $o | .message.content[]? | select(.type == "tool_use")
                  | {owner: $o, tool: (.name | tool_name),
                     agent: (if .name == "Task" or .name == "Agent" then (.input.subagent_type // "general-purpose") else null end),
                     cmd: (.input.command // null), path: (.input.file_path // .input.path // null), skill: (.input.skill // null)} ],
        calls: ([ $asst[] | {id: .message.id, owner: owner,
                           in: ((.message.usage.input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0)),
                           out: (.message.usage.output_tokens // 0)} ] | group_by(.id) | map(max_by(.out) | del(.id))),
        final_text: ([.[] | select(.type == "result") | .result] | last // "")
      }' "$1"
}

adapt_omp() { # <session-dir>
    local f
    while IFS= read -r f; do
        jq -s --arg name "$(basename "$f" .jsonl)" '
          [.[] | select(.type == "message" and .message.role == "assistant")] as $asst
          | {name: $name,
             parent: ([.[] | select(.type == "session") | .parentSession] | first // null),
             model: ([.[] | select(.type == "model_change") | .model] | first // null),
             tools: [$asst[] | .message.content[]? | select(.type == "toolCall") | {name, arguments}],
             usage: [$asst[] | .message.usage | select(.) | {in: ((.input // 0) + (.cacheRead // 0) + (.cacheWrite // 0)), out: (.output // 0)}],
             final_text: ([$asst[] | .message.content[]? | select(.type == "text") | .text] | last // "")}' "$f"
    done < <(find "$1" -name '*.jsonl' | sort) | jq -s '
      (map(select(.parent == null)) | .[0] // {tools: [], usage: [], final_text: "", model: null}) as $main
      | ([$main.tools[] | select(.name == "task") | .arguments.tasks[]? | {key: (.name // ""), value: (.agent // "task")}] | from_entries) as $amap
      | map(. + {owner: (if .parent == null then "main" else ($amap[.name] // "task") end)}) as $files
      | {model: $main.model,
         events: [ $files[] | .owner as $o | .tools[]
                   | if .name == "task" then (.arguments.tasks[]? | {owner: $o, tool: "task", agent: (.agent // "task"), cmd: null, path: null, skill: null})
                     else {owner: $o, tool: .name, agent: null, cmd: (.arguments.command // null), path: (.arguments.path // null), skill: null} end ],
         calls: [ $files[] | .owner as $o | .usage[] | . + {owner: $o} ],
         final_text: $main.final_text}'
}

# norm_summary: 標準入力の共通形から、results.jsonl に入れる集計を出す（by_agent の項目名は compare.py に合わせる）
#   { model_calls, in_tokens, out_tokens, by_agent: {<agent>: {calls, input_tokens, output_tokens}} }
norm_summary() {
    jq -c '{
      model_calls: (.calls | length),
      in_tokens: ([.calls[].in] | add // 0),
      out_tokens: ([.calls[].out] | add // 0),
      by_agent: (.calls | group_by(.owner) | map({key: .[0].owner, value: {calls: length, input_tokens: ([.[].in] | add), output_tokens: ([.[].out] | add)}}) | from_entries)
    }'
}
