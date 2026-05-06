.PHONY: update

# ローカル変更を自動 stash → pull --rebase → 復元
update:
	git pull --rebase --autostash
