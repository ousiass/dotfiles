---
name: impl-type-wr
description: impl-wt → refine-git を worktree 隔離で連続実行し、実装から研磨・CI 緑マージまで一気通貫で行う。
user-invocable: true
---

# impl-type-wr

impl-wt の上位互換。worktree で隔離した `/impl-wt` を完走した直後に `/refine-git` を続けて実行し、レビュー観点で「critical/major=0 ∧ minor≤閾値」まで磨いてから CI 緑を待って直接マージする。並列 sweep とも相性が良い合成スキル。

## 引数

impl-wt と refine-git の引数を両方受け付ける。

- **impl-wt 側**（実装対象の指定、いずれか一つ）:
  - `/impl-type-wr #<Issue番号>` — GitHub Issue から要件取得
  - `/impl-type-wr <Issue URL>` — Issue URL から要件取得
  - `/impl-type-wr <text>` — テキストを要件として扱う
  - `/impl-type-wr`（引数なし）— ユーザーにヒアリング
- **refine-git 側**（研磨挙動のチューニング、任意）:
  - `--max-minor <N>` — minor 指摘の上限（デフォルト 5）
  - `--max-iter <N>` — レビューループ反復上限（デフォルト 10）
  - `--no-merge` — 研磨のみでマージしない（デフォルトは CI 緑後に直接マージ）

## 前提条件

- Claude Code 環境
- `git`, `gh` CLI が認証済み

## フェーズ1: 引数分離

1. 引数から refine-git 側フラグ（`--max-minor` / `--max-iter` / `--no-merge`）を抽出して `REFINE_ARGS` に退避
2. 残りを `IMPLWT_ARGS` として impl-wt に渡す引数とする
3. 分離結果をユーザーに 1 行で明示（例: `impl-wt args: #123 / refine-git args: --max-minor 3`）

## フェーズ2: 実装（impl-wt 実行）

1. Skill ツールで `impl-wt` を `IMPLWT_ARGS` 付きで起動する
2. impl-wt のフルフロー（worktree 作成・要件分析・スコープ分割・実装サイクル・PR 作成）を完走させる
3. impl-wt の最終報告から **PR 番号** と **worktree パス** を取得し、`PR_NUMBER` / `WORKTREE_PATH` に保持する
4. PR が作成されなかった場合はここで終了し、refine-git へは進まない

## フェーズ3: 研磨（refine-git 実行、worktree 再利用）

1. `cd <WORKTREE_PATH>` で worktree ディレクトリに移動する（refine-git が既存 worktree の再利用条件を満たすように）
2. Skill ツールで `refine-git` を `#<PR_NUMBER> <REFINE_ARGS>` 付きで起動する
3. refine-git はフェーズ1 の判定で「既に worktree 内で起動」と検知し、impl-wt が作った worktree をそのまま再利用する（新規作成しない）
4. `--no-merge` 未指定の場合は refine-git が CI 緑を待って `gh pr merge --merge --delete-branch` + Issue close まで実行する

## フェーズ4: 最終報告

impl-wt の PR 情報・worktree パス・削除コマンド（`git worktree remove <パス>`）と、refine-git の JSON レポート（`status` / `iter` / 残指摘数 / `merged` / `report_path`）を統合してユーザーに 1 メッセージで報告する。

## 禁止行動

- impl-wt が PR 作成前に失敗・中断したのに refine-git へ進む
- refine-git を **impl-wt が作った worktree の外** で起動する（別 worktree が二重作成される。フェーズ3 で必ず `cd` してから起動）
- impl-wt / refine-git の禁止行動をこの合成スキル経由での呼び出しを理由に緩和する
- impl-wt と refine-git を並列実行する（順序依存）
- 引数分離をスキップして全引数をそのまま impl-wt に投げる（`--max-*` / `--no-merge` は impl-wt が知らないフラグなので必ず抽出する）
- **`refine-git` の代わりに `refine` を起動する**（`refine` はリポジトリ全体が対象。実装 PR と無関係な既存指摘まで拾って収束しなくなる）
- **`refine-git` の代わりに `refine` を起動する**（`refine` はリポジトリ全体が対象。実装 PR と無関係な既存指摘まで拾って収束しなくなる）

## ルール

- impl-wt と refine-git の禁止行動・ルールはこのスキルにも全て適用される
- refine-git が研磨するのは **impl-wt が作った PR の差分のみ**（全コードベース研磨が必要な場合は別途 `/refine-sweep` を使う）
- 引数のパース・PR 番号 / worktree パスの受け渡し以外に独自の状態管理は行わない
- refine-git の状態管理 `.sweep/state.json` は worktree 内で扱う（メイン作業ツリーを汚さない）
- フェーズ2 で取得した PR 番号は必ずフェーズ3 の refine-git 引数に明示的に渡す（refine-git が現ブランチ推定で別 PR を掴む事故を防ぐ）
