.DEFAULT_GOAL := help

.PHONY: help pull install update reset fugu runner-setup clean clean-system clean-timer diag test

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

runner-setup: ## GitHub Actions self-hosted runner ホストをセットアップ（sudo 必須。RUNNER_USER / RUNNER_DIR で上書き可）
	sudo env RUNNER_USER="$(RUNNER_USER)" RUNNER_DIR="$(RUNNER_DIR)" bash ./runner-host-setup.sh

clean: ## キャッシュ類を掃除（消しても再生成されるものだけ）
	./cleanup.sh

clean-system: ## sudo が必要な掃除（journal / snap / fstrim）
	./cleanup.sh system

diag: ## 容量と I/O の現状を表示（何も消さない）
	./cleanup.sh diag

clean-timer: ## 週次の自動掃除を systemd timer に登録（sudo 不要）
	@mkdir -p $(HOME)/.config/systemd/user
	@ln -sf $(CURDIR)/systemd/dotfiles-cleanup.service $(HOME)/.config/systemd/user/
	@ln -sf $(CURDIR)/systemd/dotfiles-cleanup.timer $(HOME)/.config/systemd/user/
	systemctl --user daemon-reload
	systemctl --user enable --now dotfiles-cleanup.timer
	@systemctl --user list-timers dotfiles-cleanup.timer --no-pager

test: ## cleanup.sh の回帰テストを実行
	./tests/cleanup_test.sh
