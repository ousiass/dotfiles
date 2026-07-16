# shellcheck shell=bash
# Google Cloud CLI installer/updater. common.sh の log/warn と OS に依存。

install_gcloud() {
    if command -v gcloud >/dev/null 2>&1; then
        log "gcloud は既にインストール済み"
        return
    fi
    log "gcloud (Google Cloud SDK) をインストール"
    if [[ "$OS" == "mac" ]]; then
        brew install --cask google-cloud-sdk
        return
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get が見つからないため gcloud インストールをスキップ"
        return
    fi
    # Google 公式手順: https://cloud.google.com/sdk/docs/install#deb
    sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
    local keyring=/usr/share/keyrings/cloud.google.gpg
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | sudo gpg --batch --yes --dearmor -o "$keyring"
    echo "deb [signed-by=$keyring] https://packages.cloud.google.com/apt cloud-sdk main" \
        | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y google-cloud-cli
}
update_gcloud() {
    if ! command -v gcloud >/dev/null 2>&1; then
        warn "gcloud が無いため update をスキップ"
        return
    fi
    if [[ "$OS" == "mac" ]]; then
        log "gcloud を更新 (brew upgrade)"
        brew upgrade --cask google-cloud-sdk || warn "gcloud の update に失敗"
        return
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get が無いため gcloud の update をスキップ"
        return
    fi
    log "gcloud を更新 (apt --only-upgrade)"
    sudo apt-get update -qq
    sudo apt-get install -y --only-upgrade google-cloud-cli \
        || warn "gcloud の update に失敗"
}

# ------------------------------------------------------------------
# Cloudflare Tunnel デーモン (apt / brew)
# ------------------------------------------------------------------
