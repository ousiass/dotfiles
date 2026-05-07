# shellcheck shell=bash
#
# AI CLI ツール（claude / codex / gemini）と
# クラウド / 開発 CLI（gh / gcloud）。

# ------------------------------------------------------------------
# AI CLI ツール
# ------------------------------------------------------------------
install_claude_code() {
    if command -v claude >/dev/null 2>&1; then
        log "Claude Code は既にインストール済み"
        return
    fi
    log "Claude Code をインストール"
    curl -fsSL https://claude.ai/install.sh | bash
}

update_claude_code() {
    if ! command -v claude >/dev/null 2>&1; then
        warn "claude が無いため update をスキップ"
        return
    fi
    log "Claude Code を更新 (claude update)"
    claude update || warn "claude update に失敗"
}

install_codex_cli() {
    if command -v codex >/dev/null 2>&1; then
        log "Codex CLI は既にインストール済み"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が見つからないため Codex CLI インストールをスキップ"
        return
    fi
    log "Codex CLI をインストール (bun -g @openai/codex)"
    bun install -g @openai/codex
}

update_codex_cli() {
    if ! command -v codex >/dev/null 2>&1; then
        warn "codex が無いため update をスキップ"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が無いため codex の update をスキップ"
        return
    fi
    log "Codex CLI を更新 (bun update -g @openai/codex)"
    bun update -g @openai/codex || warn "codex の update に失敗"
}

install_gemini_cli() {
    if command -v gemini >/dev/null 2>&1; then
        log "Gemini CLI は既にインストール済み"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が見つからないため Gemini CLI インストールをスキップ"
        return
    fi
    log "Gemini CLI をインストール (bun -g @google/gemini-cli)"
    bun install -g @google/gemini-cli
}

update_gemini_cli() {
    if ! command -v gemini >/dev/null 2>&1; then
        warn "gemini が無いため update をスキップ"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が無いため gemini の update をスキップ"
        return
    fi
    log "Gemini CLI を更新 (bun update -g @google/gemini-cli)"
    bun update -g @google/gemini-cli || warn "gemini の update に失敗"
}

# ------------------------------------------------------------------
# クラウド / 開発 CLI
# ------------------------------------------------------------------
install_gh() {
    if command -v gh >/dev/null 2>&1; then
        log "gh は既にインストール済み"
        return
    fi
    log "gh (GitHub CLI) をインストール"
    if [[ "$OS" == "mac" ]]; then
        brew install gh
        return
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get が見つからないため gh インストールをスキップ"
        return
    fi
    # GitHub 公式手順: https://github.com/cli/cli/blob/trunk/docs/install_linux.md
    local keyring=/usr/share/keyrings/githubcli-archive-keyring.gpg
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee "$keyring" >/dev/null
    sudo chmod go+r "$keyring"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y gh
}

update_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        warn "gh が無いため update をスキップ"
        return
    fi
    if [[ "$OS" == "mac" ]]; then
        log "gh を更新 (brew upgrade gh)"
        brew upgrade gh || warn "gh の update に失敗"
        return
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get が無いため gh の update をスキップ"
        return
    fi
    log "gh を更新 (apt --only-upgrade)"
    sudo apt-get update -qq
    sudo apt-get install -y --only-upgrade gh || warn "gh の update に失敗"
}

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
# 自作 Go ツール (go install で取得、$HOME/go/bin に配置)
# ------------------------------------------------------------------
install_moleport() {
    if command -v moleport >/dev/null 2>&1; then
        log "MolePort は既にインストール済み"
        return
    fi
    if ! command -v go >/dev/null 2>&1; then
        warn "go が見つからないため MolePort インストールをスキップ"
        return
    fi
    log "MolePort をインストール (go install)"
    go install github.com/ousiassllc/moleport/cmd/moleport@latest
}

update_moleport() {
    if ! command -v go >/dev/null 2>&1; then
        warn "go が無いため MolePort の update をスキップ"
        return
    fi
    log "MolePort を更新 (go install ...@latest)"
    go install github.com/ousiassllc/moleport/cmd/moleport@latest \
        || warn "moleport の update に失敗"
}

install_linterly() {
    if command -v linterly >/dev/null 2>&1; then
        log "Linterly は既にインストール済み"
        return
    fi
    if ! command -v go >/dev/null 2>&1; then
        warn "go が見つからないため Linterly インストールをスキップ"
        return
    fi
    log "Linterly をインストール (go install)"
    go install github.com/ousiassllc/linterly/cmd/linterly@latest
}

update_linterly() {
    if ! command -v go >/dev/null 2>&1; then
        warn "go が無いため Linterly の update をスキップ"
        return
    fi
    log "Linterly を更新 (go install ...@latest)"
    go install github.com/ousiassllc/linterly/cmd/linterly@latest \
        || warn "linterly の update に失敗"
}
