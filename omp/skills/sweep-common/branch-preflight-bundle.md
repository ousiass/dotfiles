# ブランチ事前ガード（PR を作らない sweep 用）

`report-sweep`（および将来同じ方針を採る `spec-sweep`）が使う `branch-preflight.md` の薄いラッパ。
**PR 作成前提の P-0-2（PR モード確認）だけを置き換える。** この sweep は PR を一切作らないため、
「PR の出し方」という質問・選択肢は出さない。

prelude 生成（P-0-0）・候補収集（P-0-1）・清潔確認（P-0-5）・事前ガード関数 `assert_not_base` は
`branch-preflight.md` をそのまま使う（コピーしない）。差分は P-0-2 と P-0-4 だけ。

## P-0-2': `ask` で聞く（PR の出し方は聞かない）

`--bundle` / `--per-feature` と `--base` の両方が引数で確定している場合は省略する。

| 質問 | header | 選択肢 |
|---|---|---|
| ブランチの束ね方 | `ブランチ` | **1 本にまとめる（推奨）**: 統合ブランチ 1 本に仕様書の差分を積んで push する。**PR は作らない**（レビュー・マージは `/impl` 等の後段の責務）／ **機能ごとに分ける**: 機能要望ごとに `feat/#N` ブランチを切る（従来どおり。こちらも PR は作らない） |
| ベースブランチ | `ベース` | `branch-preflight.md` の P-0-1 の候補から選ぶ（変更なし） |

**「PR モード」「PR の出し方」という文言・選択肢は一切出さない。** どちらを選んでも最終的に PR は作られない。

## P-0-3': 決定を state.json に持たせる

```json
{ "mode": "bundle" | "per-feature", "base_branch": "<base>" }
```

## P-0-4': モードごとの続き

- `bundle` → `single-branch-mode.md` の **S-0（統合ブランチ作成）だけ**を流用して統合ブランチを切り push する。**S-2（統合研磨・最終 PR 作成・CI 確認）は実行しない**
- `per-feature` → 通常どおり項目ごとに `feat/#<Issue番号>` ブランチを作る

## 禁止行動

- `single-branch-mode.md` の S-2（最終 PR 作成）を呼ぶ
- `ask` の選択肢や見出しに「PR」という語を含める
- `branch-preflight.md` の P-0-2（本物の PR モード選択）をこのラッパ経由で `issue-sweep` / `refine-sweep` にも適用する（それらは `branch-preflight.md` を直接使い続ける。壊さない）
