# {{PROJECT_SLUG}} — Slidev deck
#
# build : Cloudflare Workers で配信する静的サイト（PDF を含まない）
# pdf   : 配布用 PDF を public/ に出力する
#
# PDF は成果物のためコミットしない（.gitignore 対象）。
# public/ に置いた PDF は次回 build で dist/ へコピーされ、Web からも参照できる。

SLUG      := {{PROJECT_SLUG}}
SKILL_DIR ?= $(HOME)/.claude/skills/slide-gen

.PHONY: help install dev build pdf png site check deploy clean

help:
	@echo "make install  依存をインストールする"
	@echo "make dev      開発サーバを起動する (http://localhost:3030)"
	@echo "make build    静的サイトをビルドする (dist/)"
	@echo "make pdf      PDF を出力する (public/$(SLUG).pdf)"
	@echo "make png      1ページ1枚の PNG を出力する (public/$(SLUG)/)"
	@echo "make site     PDF を作ってから静的サイトをビルドする"
	@echo "make check    枠からのはみ出しを検査する"
	@echo "make deploy   Cloudflare Workers へデプロイする"

install:
	bun install

dev: node_modules
	bun run dev

build: node_modules
	bun run build

# PDF / PNG の出力には Chromium が要る
.chromium: node_modules
	bunx playwright install chromium
	@touch .chromium

pdf: .chromium
	bun run export:pdf
	@echo "→ public/$(SLUG).pdf"

png: .chromium
	bun run export:png
	@echo "→ public/$(SLUG)/"

# PDF を含めて配信したい場合はこちら（public/ の PDF が dist/ へコピーされる）
site: pdf build

check: build
	bun $(SKILL_DIR)/scripts/check-overflow.mjs

deploy: build
	bunx wrangler deploy

node_modules:
	bun install

clean:
	rm -rf dist public/$(SLUG).pdf public/$(SLUG) .chromium
