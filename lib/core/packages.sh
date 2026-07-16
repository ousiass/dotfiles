# shellcheck shell=bash
# apt/brew の基本パッケージ install/update。OS に依存。

# ------------------------------------------------------------------
# システムパッケージ
# ------------------------------------------------------------------
install_packages() {
    if [[ "$OS" == "linux" ]]; then
        if ! command -v apt-get >/dev/null 2>&1; then
            warn "apt-get が見つからないためパッケージインストールをスキップ"
            return
        fi
        log "apt パッケージをインストール"
        sudo apt-get update -qq
        # unzip: bun installer が内部で使用（Ubuntu minimal では未導入）
        # jq: sync_codex_mcp / install_neovim が JSON パースに使用
        # neovim は apt 版をフォールバックとして入れた後、install_neovim で
        # 公式リリース tarball に置き換える（Ubuntu LTS の apt 版は古いことが多い）。
        sudo apt-get install -y \
            fish tmux neovim git curl rsync xclip unzip jq
    else
        log "brew パッケージをインストール"
        # brew install を一括で呼ぶと、既に non-brew (公式 pkg / port / 自前ビルド)
        # で入っているパッケージ 1 つの link 衝突等で全部止まるので per-package で。
        # brew 管理下にある pkg はスキップ、失敗したものだけ warn を出して続行する。
        # unzip は macOS 標準で入っているので brew には含めない。
        local pkgs=(fish tmux neovim git curl rsync jq)
        local pkg
        for pkg in "${pkgs[@]}"; do
            if brew list --formula "$pkg" >/dev/null 2>&1; then
                log "$pkg は既にインストール済み"
            else
                brew install "$pkg" || warn "$pkg のインストールに失敗"
            fi
        done
    fi
}

update_packages() {
    if [[ "$OS" == "linux" ]]; then
        if ! command -v apt-get >/dev/null 2>&1; then
            warn "apt-get が無いため packages の update をスキップ"
            return
        fi
        log "apt パッケージを更新（対象のみ --only-upgrade）"
        sudo apt-get update -qq
        sudo apt-get install -y --only-upgrade \
            fish tmux neovim git curl rsync xclip unzip jq \
            || warn "apt パッケージの update に失敗"
    else
        if ! command -v brew >/dev/null 2>&1; then
            warn "brew が無いため packages の update をスキップ"
            return
        fi
        log "brew パッケージを更新"
        # brew で管理されている pkg だけ upgrade。未インストールに upgrade を
        # 投げると失敗するし、一括だと 1 個失敗で全部止まるので per-package で。
        local pkgs=(fish tmux neovim git curl rsync jq)
        local pkg
        for pkg in "${pkgs[@]}"; do
            if brew list --formula "$pkg" >/dev/null 2>&1; then
                brew upgrade "$pkg" || warn "$pkg の update に失敗"
            else
                log "$pkg は brew 管理外のためスキップ"
            fi
        done
    fi
}
