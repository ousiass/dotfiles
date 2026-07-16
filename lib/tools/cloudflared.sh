# shellcheck shell=bash
# cloudflared installer/updater. common.sh の log/warn と OS に依存。

install_cloudflared() {
    if command -v cloudflared >/dev/null 2>&1; then
        log "cloudflared は既にインストール済み"
        return
    fi
    log "cloudflared をインストール"
    if [[ "$OS" == "mac" ]]; then
        brew install cloudflared
        return
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get が見つからないため cloudflared インストールをスキップ"
        return
    fi
    # Cloudflare 公式手順: https://pkg.cloudflare.com/index.html
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo noble)
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared ${codename} main" \
        | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y cloudflared
}
update_cloudflared() {
    if ! command -v cloudflared >/dev/null 2>&1; then
        warn "cloudflared が無いため update をスキップ"
        return
    fi
    if [[ "$OS" == "mac" ]]; then
        log "cloudflared を更新 (brew upgrade cloudflared)"
        brew upgrade cloudflared || warn "cloudflared の update に失敗"
        return
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get が無いため cloudflared の update をスキップ"
        return
    fi
    log "cloudflared を更新 (apt --only-upgrade)"
    sudo apt-get update -qq
    sudo apt-get install -y --only-upgrade cloudflared \
        || warn "cloudflared の update に失敗"
}

# ------------------------------------------------------------------
# Node 系グローバル CLI (bun -g 経由)
# ------------------------------------------------------------------
