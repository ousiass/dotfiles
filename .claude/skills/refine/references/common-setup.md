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
```

## 4. `.sweep/state.json` の初期化

```bash
mkdir -p .sweep
jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg skill "$skill_name" \
      --argjson mi "$max_iter" --argjson mm "$max_minor" \
      --argjson pr "${pr_number:-null}" '{
  skill: $skill,
  started_at: $now, updated_at: $now,
  phase: "iterating", iteration: 0, max_iter: $mi,
  thresholds: {critical: 0, major: 0, minor: $mm},
  last_counts: {critical: null, major: null, minor: null},
  evidence: [],
  termination_reason: null,
  pr_number: $pr
}' > .sweep/state.json
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
  echo "ERROR: フロントエンドプロジェクト (react/vue/next/nuxt) ですが Atomic Design 構造 (atoms/molecules/organisms) が見つかりません。"
  echo "  $skill_name はフロント回りで Atomic Design 準拠を必須としています。"
  echo "  対応: components/, src/components/, app/components/ のいずれかに atoms/ + (molecules/ or organisms/) を配置してください。"
  jq --arg reason "atomic_design_required" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.termination_reason = $reason | .phase = "terminal" | .updated_at = $now' \
     .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
  exit 2
fi
```
