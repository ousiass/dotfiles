# shellcheck shell=bash
# cloudflared installer/updater. common.sh の log/warn と OS に依存。

# apt ソース。codename は埋め込まない（新しい Ubuntu は pkg.cloudflare.com に Release が無く apt update が落ちる）。
# テストが書き込み先を一時ディレクトリへ向けられるよう変数にしている。
CLOUDFLARED_APT_LIST="${CLOUDFLARED_APT_LIST:-/etc/apt/sources.list.d/cloudflared.list}"

_cloudflared_write_apt_list() {
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
        | sudo tee "$CLOUDFLARED_APT_LIST" >/dev/null
}

# インストール済みのホストに古い codename 入りの list が残っていると、他の apt 操作（gh / gcloud を含む
# apt-get update）まで Release エラーで止まるので any に書き直す。list が無い（apt 以外で入れた）なら触らない。
_cloudflared_refresh_apt_list() {
    [[ "$OS" == "mac" ]] && return 0
    command -v apt-get >/dev/null 2>&1 || return 0
    [[ -f "$CLOUDFLARED_APT_LIST" ]] || return 0
    _cloudflared_write_apt_list
}

install_cloudflared() {
    if command -v cloudflared >/dev/null 2>&1; then
        log "cloudflared は既にインストール済み"
        _cloudflared_refresh_apt_list
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
    _cloudflared_write_apt_list
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
    _cloudflared_refresh_apt_list
    log "cloudflared を更新 (apt --only-upgrade)"
    sudo apt-get update -qq
    sudo apt-get install -y --only-upgrade cloudflared \
        || warn "cloudflared の update に失敗"
}

# ------------------------------------------------------------------
# Node 系グローバル CLI (bun -g 経由)
# ------------------------------------------------------------------
