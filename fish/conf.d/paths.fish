# 各種開発ツールの PATH を fish 起動時に必ず追加する。
#
# universal variable (fish_user_paths) は ~/.config/fish/fish_variables に保存され
# .gitignore 対象なので、別マシンで clone しても再現されない。conf.d で毎回追加
# することで、clone 直後から同じ PATH 構成になる。bash 側は shell/paths.sh が
# 同じ集合を扱う。両者を同期して更新すること。

for _p in \
    $HOME/.local/bin \
    $HOME/.bun/bin \
    $HOME/.cargo/bin \
    $HOME/.local/share/fnm \
    $HOME/.local/share/pnpm \
    $HOME/.opencode/bin \
    $HOME/go/bin \
    /usr/local/go/bin \
    /opt/nvim \
    /opt/homebrew/bin \
    /opt/homebrew/sbin
    if test -d $_p; and not contains -- $_p $PATH
        set -gx PATH $_p $PATH
    end
end
set -e _p
