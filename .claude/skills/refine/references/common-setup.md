# refine 系 共通セットアップ（フェーズ1）

`refine` / `refine-git` が共有する初期化手順。呼び出し元 SKILL.md は事前に `skill_name` を設定しておく（`refine` または `refine-git`）。

## 1. ターゲット特定

1. 引数が PR 番号: `gh pr view <n> --json number,headRefName,baseRefName,url`
2. 引数なし: 現ブランチで `gh pr view --json ...` を試す。なければ現ブランチを直接対象に

取得結果から `pr_number` / `branch`（headRefName）/ `base_branch`（baseRefName）を変数に保持する。PR が無い場合 `base_branch` は空にしておく。

## 2. worktree 確保（必須）

メイン作業ツリーを保護するため、以下のいずれかで worktree を確保する:

- **既に worktree 内で起動された場合**（例: issue-sweep の engineer agent、`impl-wt-r` からの呼び出し）: `git rev-parse --show-toplevel` と `git worktree list --porcelain` を比較し、現在が worktree なら**再利用**（新規作成しない）
- **メイン作業ツリーで起動された場合**（例: ユーザーが `/refine-git #42` を直接叩く）: `impl-wt` の `references/worktree-setup.md` に従い PR ブランチ用の worktree を新規作成。以後フェーズ2/3 の全操作は worktree 内で実行

## 3. 変数の初期化

```bash
start_ts=$(date +%s)
iter=0
max_minor=5      # --max-minor で上書き
max_iter=10      # --max-iter で上書き
skip_minor=false # --skip-minor で true（refine-git のみ。issue-sweep からは常に true）

# `.sweep/` は **常にメインリポジトリ側** を指す。worktree 内で走っても分裂させない
# （worktree を消すとテレメトリが消え、Stop Hook が別ファイルを見る事故になる）
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
mkdir -p "$SWEEP_DIR"
```

以降 `.sweep/...` と書かれた箇所はすべて `$SWEEP_DIR/...` を指す。

## 4. `.sweep/state.json` の初期化（**所有権ガード必須**）

`.sweep/` はメインリポジトリ共有なので、`issue-sweep` から呼ばれた場合は **sweep が state.json の所有者**になる。上書きすると sweep の進行状態（`queue_remaining` など）が壊れ、フェーズ3 で `phase=terminal` にした瞬間に **Stop Hook のブロックが解除されて sweep がキュー途中で静かに終わる**。

```bash
# 既存 state.json が別スキルのもので、かつ未 terminal → sweep が所有中。触らない
owner=$(jq -r '.skill // ""' "$SWEEP_DIR/state.json" 2>/dev/null)
owner_phase=$(jq -r '.phase // ""' "$SWEEP_DIR/state.json" 2>/dev/null)
if [[ -n "$owner" && "$owner" != "$skill_name" && "$owner_phase" != "terminal" ]]; then
  OWNS_STATE=false   # state.json は一切書かない（テレメトリのみ書く）
else
  OWNS_STATE=true
fi
```

`OWNS_STATE=false` のときは以下の初期化・更新・terminal 化をすべてスキップし、`$SWEEP_DIR/refine-metrics.jsonl` への追記だけ行う。呼び出し元の sweep が停止制御を握っているので、Stop Hook 対策は不要。

`OWNS_STATE=true` のときのみ:

```bash
jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg skill "$skill_name" \
      --argjson mi "$max_iter" --argjson mm "$max_minor" \
      --argjson pr "${pr_number:-null}" '{
  skill: $skill,
  started_at: $now, updated_at: $now,
  phase: "iterating", iteration: 0, max_iter: $mi,
  thresholds: {critical: 0, major: 0, minor: $mm},
  last_counts: {critical: null, major: null, minor: null},
  termination_reason: null,
  pr_number: $pr
}' > "$SWEEP_DIR/state.json"
```

スキーマと更新規則の詳細は `state-and-telemetry.md` を参照。

## 5. HALT プロジェクト検知（初回のみ、結果は変数に保持）

```bash
HAS_HALT=false
if find . -name "*.templ" -not -path "./node_modules/*" -not -path "./.git/*" 2>/dev/null | grep -q .; then
  HAS_HALT=true
elif grep -rli "HALT\|HTMX+Atomic+Lit+Templ" docs/ SPEC.md README.md 2>/dev/null | grep -q .; then
  HAS_HALT=true
fi
```

## 6. Atomic Design プロジェクト検知

HALT でない場合のみ判定する（`halt-review` が Atomic を内包するため排他）。

```bash
HAS_ATOMIC=false
if [[ "$HAS_HALT" != "true" ]]; then
  for base in components src/components app/components; do
    if [[ -d "$base/atoms" ]] && { [[ -d "$base/molecules" ]] || [[ -d "$base/organisms" ]]; }; then
      HAS_ATOMIC=true
      break
    fi
  done
fi
```

## 7. フロントエンドプロジェクトの Atomic Design 必須ガード

```bash
IS_FRONTEND=false
if [[ -f package.json ]] && grep -qE '"(react|vue|next|nuxt)"[[:space:]]*:' package.json 2>/dev/null; then
  IS_FRONTEND=true
fi
if [[ "$IS_FRONTEND" == "true" ]] && [[ "$HAS_HALT" != "true" ]] && [[ "$HAS_ATOMIC" != "true" ]]; then
  msg="フロントエンドプロジェクト (react/vue/next/nuxt) ですが Atomic Design 構造 (atoms/molecules/organisms) が見つかりません。"
  if [[ "$OWNS_STATE" == "false" ]]; then
    # sweep 経由（issue-sweep の engineer agent 等）→ warn に降格して続行
    echo "WARN: $msg"
    echo "  研磨と無関係な構造規約で全 Issue のマージゲートを落とさないため、警告のみで続行します。"
    echo "  atomic-review はスキップされます（HAS_ATOMIC=false）。"
  else
    echo "ERROR: $msg"
    echo "  $skill_name はフロント回りで Atomic Design 準拠を必須としています。"
    echo "  対応: components/, src/components/, app/components/ のいずれかに atoms/ + (molecules/ or organisms/) を配置してください。"
    jq --arg reason "atomic_design_required" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.termination_reason = $reason | .phase = "terminal" | .updated_at = $now' \
       "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
    exit 2
  fi
fi
```

**ユーザーが直接 `/refine-git` を叩いた場合（`OWNS_STATE=true`）は従来どおり停止する。** 停止するのは「規約違反を人に知らせる」ためであり、自律実行中の sweep を全滅させるためではない。
