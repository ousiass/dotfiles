# NOTICE

このフォルダは Damir Sokolovsky ([@heydamir](https://x.com/heydamir)) の **unslop** を取り込んだもの。
CC BY 4.0 に従い、作者・ライセンス・出典・変更点をここに示す。

| 項目 | 内容 |
|---|---|
| 作品 | unslop（`skills/unslop`） |
| 作者 | Damir Sokolovsky ([@heydamir](https://x.com/heydamir)) |
| ライセンス | CC BY 4.0 — <https://creativecommons.org/licenses/by/4.0/> |
| 元のリポジトリ | <https://github.com/heydamir/unslop> |
| 取り込み元のフォルダ | <https://github.com/heydamir/unslop/tree/a6f121eee5f29c2f74976b75456feae8b66afb3a/skills/unslop> |
| 取り込み元のコミット | `a6f121eee5f29c2f74976b75456feae8b66afb3a`（2026-11-01、`main`） |
| 取り込み日 | 2026-11-02 |

## 変更点

- 上流の `skills/unslop/` 配下のファイルは **1 バイトも変えていない**（`SKILL.md`・`agents/`・`references/`・`scripts/`）。
- この `NOTICE.md` だけを追加した。

## 更新のしかた

上流の新しいコミットを取り込むときは、`skills/unslop/` を丸ごと置き換え、この表のコミットと取り込み日を更新する。
`SKILL.md` 冒頭にも作者表示があるので、消さずに残すこと（CC BY 4.0 の表示条件）。

## 任意の依存（dotfiles は入れない）

スクリプトを使う機能だけが次を必要とする。スキル本体（監査・修正）は不要。

| 機能 | 必要なもの |
|---|---|
| 公開サイトのスナップショット（`scripts/snapshot.mjs`） | Playwright と chromium |
| ストーリー動画（`scripts/story.mjs`） | Playwright と chromium、`ffmpeg`（PATH 上） |

入れる場合は、スキルを使うプロジェクトの中で `npm install -D playwright` と `npx playwright install chromium`、
ffmpeg は OS のパッケージ（`apt install ffmpeg` / `brew install ffmpeg`）で入れる。
