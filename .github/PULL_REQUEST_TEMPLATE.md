## 概要

<!-- 何を変えたのかを 1〜2 行で -->

## 背景・理由

<!-- どんな問題が起きていたか。再現手順があれば書いてください -->

## 動作確認

<!-- 確認した OS と手順 -->

- [ ] Ubuntu
- [ ] macOS

## チェックリスト

- [ ] `git ls-files '*.sh' | xargs -n1 bash -n` が通る
- [ ] `git ls-files '*.sh' | xargs shellcheck -x --severity=warning` が通る
- [ ] `install.sh` を変更した場合、2 回連続実行しても壊れない（idempotent）
- [ ] 秘密情報（API キー等）を含んでいない
- [ ] README と矛盾しない（矛盾するなら README も更新した）
