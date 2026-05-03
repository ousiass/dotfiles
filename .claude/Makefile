.PHONY: update update-plugins update-skills help

help: ## ヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

update: update-plugins update-skills ## プラグインとスキルをすべて更新

update-plugins: ## マーケットプレイスのプラグインを最新に更新
	@echo "==> プラグインを更新中..."
	git submodule update --init --remote plugins/marketplaces/claude-plugins-official
	@echo "==> プラグイン更新完了"

update-skills: ## スキルをリモートから更新（git pull）
	@echo "==> スキルを更新中..."
	git pull --rebase origin main
	@echo "==> スキル更新完了"
