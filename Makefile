.DEFAULT_GOAL := help

.PHONY: help pull install update reset fugu clean clean-system diag

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

pull: ## ローカル変更を stash しつつ git pull --rebase
	git pull --rebase --autostash

install: ## dotfiles と各種ツールをセットアップ（idempotent）
	./install.sh

update: ## インストール済みツールを最新版に更新
	./update.sh

reset: ## ツールを一括削除して install.sh で再インストール（検証用）
	./reset-tools.sh

fugu: ## Fugu だけ単独でインストール（~/.env の SAKANA_API_KEY を使う）
	./install.sh fugu

clean: ## キャッシュ類を掃除（消しても再生成されるものだけ）
	./cleanup.sh

clean-system: ## sudo が必要な掃除（journal / snap / fstrim）
	./cleanup.sh system

diag: ## 容量と I/O の現状を表示（何も消さない）
	./cleanup.sh diag
