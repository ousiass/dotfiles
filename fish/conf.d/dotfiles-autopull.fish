# dotfiles-autopull.fish
#
# 対話シェル起動時に ~/dotfiles をバックグラウンドで git pull する。

if not status is-interactive
    exit
end

set -l dotfiles_dir $HOME/dotfiles

# dotfiles が git リポジトリでなければ何もしない
if not test -d $dotfiles_dir/.git
    exit
end

# バックグラウンドで pull（ターミナル起動を待たせない）
fish -c "
    cd $dotfiles_dir
    and git pull --rebase --autostash --quiet 2>/dev/null
" &
disown
