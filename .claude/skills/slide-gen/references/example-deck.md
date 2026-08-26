# 完成例

**執筆前に必ず読む。** 文章の粒度・パターンの使い方・presenter note の書き方の基準になる。
架空の社内プロダクト「Reflow」の提案デッキ（本編8ページ）。はみ出し検査済み。

見るべき点:

- **h2 はタイトル**。「申請経路の現状と導入後」のように、そのページが何のページかを示す（10〜20字）
- **主張は h2 に書かない**。カードの見出し、`v-duo` の giant、`v-two-stack` の h3 が語る。
  それらで足りないページだけ `v-formula-banner` を最下部に置く（8ページ中3ページ）
- **リード文（`v-lead`）は使っていない**。必要なときだけ入れる要素であり、既定では置かない
- `v-formula-banner` と `v-note` を同じページに両方置かない
- `.accent` は各ページ1箇所だけ
- 数値には出典と年が入っている
- `v-dark` は課題ページと締めの2枚だけ

そのままコピーせず、**文章の詰め方と長さの基準として使う**。

```markdown
---
theme: default
title: 申請ワークフロー基盤 提案
info: |
  ## 申請ワークフロー基盤 提案
  社内の申請と承認を1つの基盤にまとめる提案資料。
author: サンプル株式会社
class: visual-deck text-left v-dark
transition: fade
mdc: true
fonts:
  sans: 'Inter, Noto Sans JP'
  mono: 'JetBrains Mono'
colorSchema: light
css: unocss
---

<div class="v-cover-copy">
  <div class="v-kicker">Internal Workflow Platform</div>
  <div class="v-cover-title">Reflow</div>
  <div class="v-cover-sub">申請から承認、記録までを<br/>1つの流れにまとめる。</div>
  <div class="v-cover-info">
    <div><span class="label">Date</span><span class="value">2026.08.26</span></div>
    <div><span class="label">Company</span><span class="value">サンプル株式会社</span></div>
  </div>
</div>

<!--
このページで固定するのは「何の提案か」の1点。機能の話はまだしない。
-->

---
class: visual-deck
---

<div class="v-kicker">What we propose</div>

## 申請手続きを1つの基盤に

<div class="v-audience">
  <article>
    <div class="ordinal">01</div>
    <h3>誰の課題か</h3>
    <p>申請する社員、承認する管理職、集計する管理部門。3者がそれぞれ別の手間を抱えている。</p>
    <p class="use">対象</p>
  </article>
  <article>
    <div class="ordinal">02</div>
    <h3>何を提供するか</h3>
    <p>申請フォーム、承認経路、期限管理、記録の保管。申請の種類が増えても同じ仕組みで扱える。</p>
    <p class="use">プロダクト</p>
  </article>
  <article class="accent">
    <div class="ordinal">03</div>
    <h3>何が変わるか</h3>
    <p>申請の状態が1画面でわかる。差し戻しの理由も、承認までにかかった日数も記録に残る。</p>
    <p class="use">効果</p>
  </article>
</div>

<div class="v-formula-banner">
  <span>Key point</span>
  <strong>申請の種類を増やすたびに新しい仕組みを作るのをやめ、1つの基盤の設定で足せるようにする</strong>
</div>

---
class: visual-deck v-dark
---

<div class="v-statement">
  <div class="eyebrow">The problem</div>
  <div class="line">申請が今どこにあるのか、<br/><em>誰にも見えていない。</em></div>
  <div class="sub">
    紙、メール、表計算、チャット。申請の種類ごとに経路が違う。<br/>
    止まっていることに気づくのは、期限を過ぎてからになる。
  </div>
</div>

---
class: visual-deck
---

<div class="v-kicker">Before / After</div>

## 申請経路の現状と導入後

<div class="v-duo">
  <article>
    <div class="giant">いま</div>
    <h3>経路が種類ごとに違う</h3>
    <ul>
      <li>経費は表計算を添付してメールで送る</li>
      <li>休暇は紙に押印して総務へ回す</li>
      <li>備品はチャットで上長に依頼する</li>
      <li>稟議は専用システムに入力する</li>
    </ul>
    <p>どこで止まっているかは、担当者に聞かないとわからない。</p>
  </article>
  <article class="accent">
    <div class="giant">導入後</div>
    <h3>経路が1つに揃う</h3>
    <ul>
      <li>種類にかかわらず同じ画面から出す</li>
      <li>今どの承認者の手元にあるかが見える</li>
      <li>期限が近づくと承認者へ通知が届く</li>
      <li>差し戻しの理由が記録に残る</li>
    </ul>
    <p>問い合わせずに状況がわかり、滞留は通知で解消される。</p>
  </article>
</div>

<div class="v-formula-banner">
  <span>Key point</span>
  <strong>申請を出したあと、社員が待つ以外にできることがない状態をなくす</strong>
</div>

---
class: visual-deck
---

<div class="v-kicker">How it works</div>

## 申請から記録までの4段階

<div class="v-flow-detail v-flow-detail-four">
  <article>
    <div class="index">01</div>
    <h3>申請</h3>
    <p>種類を選ぶと、必要な項目だけが出る。過去の申請から複製もできる。</p>
  </article>
  <div class="arrow">→</div>
  <article>
    <div class="index">02</div>
    <h3>承認</h3>
    <p>金額と部署から経路が自動で決まる。承認者は一覧からまとめて処理する。</p>
  </article>
  <div class="arrow">→</div>
  <article>
    <div class="index">03</div>
    <h3>執行</h3>
    <p>承認された内容が会計・人事の各システムへ渡る。二重入力をなくす。</p>
  </article>
  <div class="arrow">→</div>
  <article>
    <div class="index">04</div>
    <h3>記録</h3>
    <p>誰がいつ承認したかを保管する。監査で求められる証跡をそのまま出せる。</p>
  </article>
</div>

<p class="v-note">申請の種類を追加するときに変えるのは、項目と経路の設定だけ。仕組みそのものは作り直さない。</p>

---
class: visual-deck
---

<div class="v-kicker">Comparison</div>

## 4つの手段の比較

<div class="v-matrix">
  <div class="head"></div><div class="head">導入の速さ</div><div class="head">種類の追加</div><div class="head">状態の可視化</div><div class="head">証跡の保管</div>
  <div class="row">紙とメール</div><div class="yes">●</div><div>—</div><div>—</div><div>—</div>
  <div class="row">表計算で管理</div><div class="yes">●</div><div>△</div><div>—</div><div>—</div>
  <div class="row">種類ごとに個別開発</div><div>—</div><div>—</div><div class="yes">●</div><div class="yes">●</div>
  <div class="row best">共通の申請基盤</div><div class="yes best">●</div><div class="yes best">●</div><div class="yes best">●</div><div class="yes best">●</div>
</div>

<div class="v-formula-banner">
  <span>Key point</span>
  <strong>個別に作るのではなく、共通の土台に載せることで、種類の追加を設定だけで済ませる</strong>
</div>

---
class: visual-deck
---

<div class="v-kicker">Impact</div>

## 現状を示す3つの指標

<div class="v-metrics">
  <article>
    <div class="num">4.2<span class="unit">日</span></div>
    <p>申請から承認完了までの平均日数（現状・2026年上期の社内実績）。</p>
  </article>
  <article>
    <div class="num">23<span class="unit">%</span></div>
    <p>差し戻しが発生した申請の割合。理由が残らないため同じ不備が繰り返される。</p>
  </article>
  <article>
    <div class="num">37<span class="unit">種類</span></div>
    <p>現在運用中の申請様式。うち11種類が個別の仕組みで動いている。</p>
  </article>
</div>

<div class="v-two-stack">
  <article>
    <h3>滞留は、経路が見えないことから起きている</h3>
    <p>承認者が申請を認識していない期間が、平均日数の大半を占める。通知と一覧化で短縮できる。</p>
  </article>
  <article>
    <h3>手戻りは、入力時点で防げる</h3>
    <p>差し戻し理由の上位3件はいずれも記入漏れ。申請時の必須チェックで発生を抑えられる。</p>
  </article>
</div>

---
layout: center
class: visual-deck text-center v-center v-dark
---

<div class="v-end-copy">
  <div class="v-kicker">Reflow</div>
  <h2>申請の流れが見えれば、<br/>止まっている場所から直せる。</h2>
  <p>まず利用の多い5種類から始め、運用しながら残りを移す。</p>
</div>```
