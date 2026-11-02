.DEFAULT_GOAL := help

.PHONY: help pull install update reset fugu swarm-console runner-setup runner-tools clean clean-system clean-timer diag test

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

swarm-console: ## swarm-console だけ単独でインストール（~/bin/swarm-console に sha256 照合して配置 → systemd ユーザーサービス登録。config.toml が無ければ起動せず手順を表示。配置済みならバイナリは触らない）
	./install.sh swarm_console

runner-setup: ## GitHub Actions self-hosted runner ホストをセットアップ（runner 本体の取得・登録とサービス化まで。.path が PATH の正。sudo 必須。RUNNER_USER / RUNNER_DIR / RUNNER_ORG / RUNNER_NAME / RUNNER_GROUP / RUNNER_REPLACE で上書き可。Linux と Apple Silicon の macOS）
	sudo env RUNNER_USER="$(RUNNER_USER)" RUNNER_DIR="$(RUNNER_DIR)" RUNNER_ORG="$(RUNNER_ORG)" RUNNER_NAME="$(RUNNER_NAME)" RUNNER_GROUP="$(RUNNER_GROUP)" RUNNER_REPLACE="$(RUNNER_REPLACE)" bash ./runner-host-setup.sh

runner-tools: ## runner のジョブが使うツール（macOS は brew で colima/docker/fnm/gh/jq など）の足りないものだけ入れる。sudo 不要・何度でも可
	./runner-tools-install.sh

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

test: ## 回帰テストを実行（cleanup.sh / runner-path-guard.sh / runner-host-setup.sh / runner-tools-install.sh / swarm-console の install / cloudflared の apt ソース / bash 3.2 可搬性 / evals の dry 配線）
	./tests/cleanup_test.sh
	./tests/runner_path_guard_test.sh
	./tests/runner_host_setup_test.sh
	./tests/runner_tools_install_test.sh
	./tests/swarm_console_install_test.sh
	./tests/cloudflared_install_test.sh
	./tests/portability_test.sh
	./tests/evals_dry_test.sh
