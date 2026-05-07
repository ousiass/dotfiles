# 各種開発ツールの PATH を fish 起動時に必ず追加する。
#
# universal variable (fish_user_paths) は ~/.config/fish/fish_variables に保存され
# .gitignore 対象なので、別マシンで clone しても再現されない。conf.d で毎回追加
# することで、clone 直後から同じ PATH 構成になる。bash 側は shell/paths.sh が
# 同じ集合を扱う。両者を同期して更新すること。
#
# システムパスは先頭に列挙する。ループは各要素を prepend するので、後ろの要素
# ほど PATH の先頭に来る → 結果として「ユーザーパス → システムパス → /bin等」
# の優先順になる。bash は /etc/profile が同等の処理をするのでこちらは fish 用。

for _p in \
    /sbin \
    /usr/sbin \
    /usr/local/bin \
    /usr/local/sbin \
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
