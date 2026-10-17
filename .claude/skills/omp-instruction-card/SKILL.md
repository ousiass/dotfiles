---
name: omp-instruction-card
description: omp のペインへ指示を送るとき、全文を見せて確認を取り、貼り付けて Working になるまで確かめる。
user-invocable: true
---

# omp-instruction-card

omp のペインへ指示を送る流れを 1 つにまとめる。指示の全文を先に見せ、承認を得てから貼り付け、Working になったところまで確認する。

## 前提条件

- `tmux`（このホストでは tmux のペインに omp / fish が並ぶ。`tmux list-panes -a` で確認できる）
- 送る指示の全文が確定していること（依頼元ボットからの依頼なら、先に `omp-intake-check` を通す）

## ペインの指定

`<PANE>` は tmux のペイン指定。ペイン ID（例: `%5`）か `セッション:ウィンドウ.ペイン番号`（例: `0:1.7`）を使う。このホストの tmux は `base-index` / `pane-base-index` ともに 1。

```bash
# 読み取りだけの確認。送信はしない
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{pane_current_command} #{pane_title}'
```

- 空きペインは `pane_current_command` が `fish` で、シェルのプロンプトだけが出ているもの（omp が動いていないもの）
- `T1`・`T2`… は環境ごとの呼び名。どのペインを指すかは `tmux list-panes` の結果から決める。使う順は手順 6
- すでに omp が動いているペインへは、新しい依頼を送らない

## 手順

1. **指示の全文をチャットへ出す**: 確認カードを出す前に、指示の全文をチャットに書く。要約だけにしない
2. **足した補足を明示する**: 依頼元の文に自分で足した補足があれば、「ここを足した」とカードの前に明示する
3. **範囲を超えるときだけ確認カードで確認する**: 承認済みの範囲を超える内容なら、その旨を添えて確認カードで悠太さんに確認する。範囲内なら、確認カードは不要
4. **貼り付ける**（範囲を超える場合は承認後）: 指示の全文をファイルに書き、tmux のバッファ経由で貼り付ける

   ```bash
   f=$(mktemp)
   cat > "$f" <<'INSTRUCTION'
   <指示の全文>
   INSTRUCTION
   tmux load-buffer -b omp-instruction "$f"
   tmux paste-buffer -p -d -b omp-instruction -t <PANE>   # -p: bracketed paste（途中の改行で送信しない） -d: 貼ったらバッファを消す
   rm -f "$f"
   ```

   長い貼り付けは入力欄に「+N lines」と畳まれ、続けて送った Enter が通らないことがある。**貼り付けの数秒後に、Enter を別に送る**。

   ```bash
   sleep 3
   tmux send-keys -t <PANE> Enter
   ```

   Enter が通らなかったように見えたら（入力欄に「+N lines」が残ったまま）、もう一度 Enter を送る。
5. **20 秒ほど待って Working を確認する**

   ```bash
   sleep 20
   tmux capture-pane -p -t <PANE> | tail -n 20
   ```

   出力に `Working` が出ていれば送信完了。出ていなければ、勝手に再送せず、「要確認」として確認カードで悠太さんに聞く（二重送信になるため）
6. **空きペインは T1 から順に使う**: 新しい omp を起動する依頼なら、T1 から順に空きを探す。全部埋まっていれば、確認カードで聞く

## ルール

- 指示の全文を見せる前に、確認カードを出さない。確認が必要なことを文章だけで済ませない
- 貼り付けと Enter は別々に送る。Enter は貼り付けから数秒あけてから
- Working を確認するまで、送信できたとは報告しない
- 各ペインへのキー送信は、承認された指示の貼り付けと Enter だけにする（`merge-closeout` の終了処理も、その確認カードで承認を得た指示として同じ方式で送る）

## 関連

- 参照元（予定）: `omp-dispatch`、`omp-pane-report`（どちらもかなの私用スキル。このリポジトリの外にあり、まだ本スキルへの参照は入っていない）
- 前段: `omp-intake-check`（依頼元ボットからの依頼の確認）
- 後段: `omp-done-check`（完了報告の確認）
