# shellcheck shell=bash
# Neovim の install/update。OS と TIMESTAMP に依存。

# ------------------------------------------------------------------
# Neovim (Linux: 公式 release tarball / macOS: brew)
# ------------------------------------------------------------------
nvim_current_version() {
    nvim --version 2>/dev/null | awk 'NR == 1 { print $2 }'
}

neovim_latest_tag() {
    command -v curl >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1

    curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
        | jq -r '.tag_name // empty'
}

neovim_linux_asset() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) echo "nvim-linux-x86_64.tar.gz" ;;
        aarch64 | arm64) echo "nvim-linux-arm64.tar.gz" ;;
        *) return 1 ;;
    esac
}

install_neovim_release() {
    local version="$1"

    if [[ "$OS" == "mac" ]]; then
        if brew list --formula neovim >/dev/null 2>&1; then
            brew upgrade neovim || warn "neovim の update に失敗"
        else
            brew install neovim || warn "neovim のインストールに失敗"
        fi
        return
    fi

    local asset
    if ! asset=$(neovim_linux_asset); then
        warn "Neovim 公式 tarball が未対応の CPU アーキテクチャです: $(uname -m)"
        return
    fi

    local tmp archive
    tmp=$(mktemp -d)
    archive="$tmp/$asset"

    log "Neovim $version を公式 release tarball からインストール ($asset)"
    if ! curl -fL "https://github.com/neovim/neovim/releases/download/${version}/${asset}" -o "$archive"; then
        warn "Neovim $version のダウンロードに失敗"
        rm -rf "$tmp"
        return
    fi

    local extract_dir
    extract_dir="$tmp/nvim"
    mkdir -p "$extract_dir"
    if ! tar -C "$extract_dir" --strip-components=1 -xzf "$archive"; then
        warn "Neovim $version の展開に失敗"
        rm -rf "$tmp"
        return
    fi

    sudo rm -rf /opt/nvim
    sudo mv "$extract_dir" /opt/nvim

    if [[ -e /usr/local/bin/nvim && ! -L /usr/local/bin/nvim ]]; then
        local backup="/usr/local/bin/nvim.bak.$TIMESTAMP"
        warn "/usr/local/bin/nvim が通常ファイルのため $backup に退避"
        sudo mv /usr/local/bin/nvim "$backup"
    fi
    sudo ln -sfn /opt/nvim/bin/nvim /usr/local/bin/nvim
    rm -rf "$tmp"

    log "Neovim $version を /opt/nvim にインストールし /usr/local/bin/nvim を更新"
}

install_neovim() {
    local latest current

    if [[ "$OS" == "mac" ]]; then
        install_neovim_release "stable"
        return
    fi

    latest=$(neovim_latest_tag || true)
    if [[ -z "$latest" ]]; then
        warn "Neovim 最新バージョン取得に失敗、apt 版のまま続行"
        return
    fi

    current=$(nvim_current_version || true)
    if [[ "$current" == "$latest" ]]; then
        log "Neovim は既に最新 ($current)"
        return
    fi

    log "Neovim を更新: ${current:-未インストール} -> $latest"
    install_neovim_release "$latest"
}

update_neovim() {
    install_neovim
}
