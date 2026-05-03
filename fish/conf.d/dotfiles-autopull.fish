# dotfiles-autopull.fish
#
# 対話シェル起動時に ~/dotfiles を git pull する。
# 過剰実行を避けるためマーカーファイルでスロットルする。

if not status is-interactive
    exit
end

set -l dotfiles_dir $HOME/dotfiles
set -l marker $HOME/.cache/dotfiles-last-pull
set -l throttle_hours 6

# dotfiles が git リポジトリでなければ何もしない
if not test -d $dotfiles_dir/.git
    exit
end

# マーカーがあり、まだ throttle 期間内ならスキップ
if test -f $marker
    set -l elapsed (math (date +%s) - (cat $marker))
    if test $elapsed -lt (math "$throttle_hours * 3600")
        exit
    end
end

# バックグラウンドで pull（ターミナル起動を待たせない）
mkdir -p (dirname $marker)
fish -c "
    cd $dotfiles_dir
    and git pull --rebase --autostash --quiet 2>/dev/null
    and date +%s > $marker
" &
disown
