# shellcheck shell=bash
# lazygit installer/updater. common.sh の log/warn と OS に依存。

install_lazygit_linux_release() {
    command -v curl >/dev/null 2>&1 || { warn "curl が無いため lazygit インストールをスキップ"; return; }
    command -v jq >/dev/null 2>&1 || { warn "jq が無いため lazygit インストールをスキップ"; return; }
    command -v tar >/dev/null 2>&1 || { warn "tar が無いため lazygit インストールをスキップ"; return; }

    local arch
    case "$(uname -m)" in
        x86_64 | amd64) arch="x86_64" ;;
        aarch64 | arm64) arch="arm64" ;;
        *)
            warn "lazygit 公式 release が未対応の CPU アーキテクチャです: $(uname -m)"
            return
            ;;
    esac

    local release_json asset_url version tmp archive
    release_json="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest)" || {
        warn "lazygit 最新バージョン取得に失敗"
        return
    }
    version="$(jq -r '.tag_name // empty' <<< "$release_json")"
    asset_url="$(
        jq -r --arg arch "$arch" '
            .assets[]
            | select(.name | test("_linux_" + $arch + "\\.tar\\.gz$"))
            | .browser_download_url
        ' <<< "$release_json" | head -n 1
    )"

    if [[ -z "$version" || -z "$asset_url" ]]; then
        warn "lazygit Linux ${arch} 用 asset が見つかりません"
        return
    fi

    tmp="$(mktemp -d)"
    archive="$tmp/lazygit.tar.gz"

    log "lazygit $version を公式 release tarball からインストール"
    if ! curl -fL "$asset_url" -o "$archive"; then
        warn "lazygit のダウンロードに失敗"
        rm -rf "$tmp"
        return
    fi
    if ! tar -C "$tmp" -xzf "$archive" lazygit; then
        warn "lazygit の展開に失敗"
        rm -rf "$tmp"
        return
    fi

    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$tmp/lazygit" "$HOME/.local/bin/lazygit"
    rm -rf "$tmp"
    log "lazygit $version を $HOME/.local/bin/lazygit にインストール"
}
install_lazygit() {
    if command -v lazygit >/dev/null 2>&1; then
        log "lazygit は既にインストール済み"
        return
    fi
    if [[ "$OS" == "mac" ]]; then
        log "lazygit をインストール (brew)"
        brew install lazygit || warn "lazygit のインストールに失敗"
        return
    fi
    install_lazygit_linux_release
}
update_lazygit() {
    if ! command -v lazygit >/dev/null 2>&1; then
        warn "lazygit が無いため update をスキップ"
        return
    fi
    if [[ "$OS" == "mac" ]]; then
        log "lazygit を更新 (brew upgrade lazygit)"
        brew upgrade lazygit || warn "lazygit の update に失敗"
        return
    fi

    # Linux: 最新タグを取得し、既に最新なら再ダウンロードをスキップ
    # （install_neovim と同じ「最新ならスキップ」パターンに揃える）。
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        local latest current
        latest="$(
            curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
                | jq -r '.tag_name // empty' | sed 's/^v//'
        )"
        current="$(lazygit --version 2>/dev/null | grep -oE 'version=[^,]+' | head -1 | cut -d= -f2)"
        if [[ -n "$latest" && "$current" == "$latest" ]]; then
            log "lazygit は既に最新 ($current)"
            return
        fi
        log "lazygit を更新: ${current:-不明} -> ${latest:-最新}"
    fi
    install_lazygit_linux_release || warn "lazygit の update に失敗"
}
