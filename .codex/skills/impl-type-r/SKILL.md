---
name: impl-type-r
description: impl → refine を連続実行し、実装から研磨・CI 緑マージまで一気通貫で行う。impl の上位互換として、実装完了後に手動で refine を叩く工数をゼロにしたいときに使う。
---

# impl-type-r

impl の上位互換。`impl` を完走した直後に `refine` を続けて実行し、レビュー観点で「critical/major=0 ∧ minor≤閾値」まで磨いてから CI 緑を待って直接マージする。手動で impl → refine を叩き分ける工数をゼロにするための合成スキル。

## いつ使うか

- Issue 1 件を実装 → PR → 研磨 → マージまでワンショットで済ませたいとき
- worktree 隔離は不要で、現在のブランチをベースに直接進めたいとき
- worktree 隔離が必要な場合は `impl-type-wr` を使う

## 前提条件

- Codex CLI 環境
- `git`, `gh` CLI が認証済み

## 引数

impl と refine の引数を両方受け付ける。

- **impl 側**（実装対象の指定、いずれか一つ）:
  - **Issue 番号** (例: `#123`): GitHub Issue から要件を取得
  - **Issue URL** (例: `https://github.com/owner/repo/issues/123`): 同上
  - **テキスト** (例: `ユーザー認証機能を追加`): テキストを要件として扱う
  - **引数なし**: ユーザーに要件をヒアリング
- **refine 側**（研磨挙動のチューニング、任意）:
  - `--max-minor <N>` — minor 指摘の上限（デフォルト 5）
  - `--max-iter <N>` — レビューループ反復上限（デフォルト 10）
  - `--no-merge` — 研磨のみでマージしない（デフォルトは CI 緑後に直接マージ）

## フェーズ1: 引数分離

1. 引数から refine 側フラグ（`--max-minor` / `--max-iter` / `--no-merge`）を抽出して `REFINE_ARGS` に退避
2. 残りを `IMPL_ARGS` として impl に渡す引数とする（Issue 番号 / URL / テキスト / 空）
3. 分離結果をユーザーに 1 行で明示（例: `impl args: #123 / refine args: --max-minor 3`）

## フェーズ2: 実装（impl 実行）

1. `impl` スキルを `IMPL_ARGS` 付きで起動する
2. impl のフルフロー（要件分析・スコープ分割・実装サイクル・PR 作成）を完走させる
3. impl の最終報告から **PR 番号** を取得して `PR_NUMBER` に保持する
4. PR が作成されなかった場合（impl が中断した等）はここで終了し、refine へは進まない

## フェーズ3: 研磨（refine 実行）

1. `refine` スキルを `#<PR_NUMBER> <REFINE_ARGS>` 付きで起動する
2. refine は自身で PR ブランチ用の worktree を新規作成し、review → 修正 → 再 review を回す
3. `--no-merge` 未指定の場合は refine が CI 緑を待って `gh pr merge --merge --delete-branch` + Issue close まで実行する

## フェーズ4: 最終報告

impl の PR 情報と refine の JSON レポート（`status` / `iter` / 各残指摘数 / `merged` / `report_path`）を統合してユーザーに 1 メッセージで報告する。

## 禁止行動

- impl が PR 作成前に失敗・中断したのに refine へ進む（PR が存在しないため必ずスキップ）
- impl / refine の禁止行動をこの合成スキル経由での呼び出しを理由に緩和する（両スキルの禁止行動はそのまま継承される）
- impl と refine を並列実行する（refine は impl の PR を対象にするため順序依存）
- 引数分離をスキップして全引数をそのまま impl に投げる（`--max-*` / `--no-merge` は impl が知らないフラグなので必ず抽出する）

## ルール

- impl と refine の禁止行動・ルールはこのスキルにも全て適用される
- 引数のパース・PR 番号の受け渡し以外に独自の状態管理は行わない（`.sweep/state.json` は refine が管理）
- フェーズ2 で取得した PR 番号は必ずフェーズ3 の refine 引数に明示的に渡す（refine が現ブランチ推定で別 PR を掴む事故を防ぐ）
