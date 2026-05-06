.PHONY: pull

# ローカル変更を自動 stash → pull --rebase → 復元
pull:
	git pull --rebase --autostash
