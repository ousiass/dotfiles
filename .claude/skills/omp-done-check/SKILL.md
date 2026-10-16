---
name: omp-done-check
description: omp から完了報告を受けたとき、PR の CI を自分で確かめてから ✅ にして悠太さんへ報告する
user-invocable: true
---

# omp-done-check

omp が「完了」と報告しても、それだけでは完了扱いにしない。受け取る側（かな）が PR の head コミットと CI の結果を自分で確かめ、問題がなければ ✅ にして悠太さんへ報告する。

## 前提条件

- `gh` CLI（認証済み）
- 完了報告に PR 番号（または URL）と head コミットの SHA が書かれていること
- 完了報告の書式は、このリポジトリの `.claude/CLAUDE.md` の `## 完了報告` に従う（`指示から外れた点` の欄を含む）

## 手順

1. **head を控える**: 完了報告に書かれた PR 番号と head コミット SHA を控える
2. **PR と CI を確認する**: 次を実行し、head が報告と一致するか、各チェックの結果を見る

   ```bash
   gh pr view <PR> --json headRefOid,state,isDraft,statusCheckRollup
   gh pr checks <PR>
   ```

   - `headRefOid` が報告の SHA と一致するか（先頭の数桁ではなく全桁で比べる）
   - `state` が `OPEN`、`isDraft` が `false` か
   - `statusCheckRollup` / `gh pr checks` の全チェックが成功か（failure・pending・skipped を見落とさない）
   - skipped は、前段の失敗で飛ばされたものなら失敗として扱う。設定上の意図（`if:` 条件など）と確かめられたものだけ許容し、理由を報告に添える（`.claude/CLAUDE.md` の `## 完了報告` と同じ区別）
3. **失敗・pending があれば ✅ にしない**
   1. 失敗なら `gh run view <run-id> --log-failed` などで原因を調べる（pending なら完了まで待って、手順 2 をやり直す）
   2. omp への修正依頼を作る前に、omp がすでに push 中でないか確認する（ペインの出力、`gh pr view <PR> --json headRefOid` を少し置いて取り直し、SHA が動いていないか）。push 中なら重複修正を避けるため、push が終わってから手順 1 に戻る
   3. 動いていなければ、原因と直してほしい点をまとめて修正依頼を作る。依頼は `omp-instruction-card` の手順で送る
4. **「指示から外れた点」を読む**: 完了報告の `指示から外れた点` の欄を読み、決めた方式と違っていれば、悠太さんに確認カードを出す。違いがなければ手順 5 へ進む（欄が無い・空の場合も、「なし」と明記されているか確かめる）
5. **✅ にして報告する**: 手順 2〜4 がすべて問題なければ ✅ にして、下記の書式で悠太さんへ報告する

## 結果の報告の書式

```
PR #<番号> の完了確認: ✅ / ⚠️ 要対応
- head: <報告の SHA> / <実際の SHA> → 一致 / 不一致
- state: <OPEN など> / draft: <true|false>
- チェック:
  - <チェック名>: <success|failure|pending|skipped（理由: ...）>
  - ...
- 指示から外れた点: なし / <内容> → 決めた方式と同じ / 違う（確認カードを出した）
- 判定: ✅（すべて成功・head 一致・外れた点なし）／ ✅ にしない（理由: ...）
```

## ルール

- 失敗・pending・head 不一致・理由の分からない skipped・外れた点の未確認のどれかが残るうちは、✅ にしない
- 確認は報告の文面ではなく、`gh` で自分で取った結果にもとづく
- 確認カードが必要なことを、文章だけで済ませない

## 関連

- 参照元: `omp-pane-report`（かなの私用スキル。このリポジトリの外にある）
- 修正依頼を送るときに使う: `omp-instruction-card`
- 完了報告の書式: `.claude/CLAUDE.md` の `## 完了報告`
