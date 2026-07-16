# shellcheck shell=bash
# Netlify CLI installer/updater. common.sh の log/warn に依存。

install_netlify_cli() {
    if command -v netlify >/dev/null 2>&1; then
        log "netlify-cli は既にインストール済み"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が見つからないため netlify-cli インストールをスキップ"
        return
    fi
    log "netlify-cli をインストール (bun -g netlify-cli)"
    bun install -g netlify-cli
}
update_netlify_cli() {
    if ! command -v netlify >/dev/null 2>&1; then
        warn "netlify が無いため update をスキップ"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が無いため netlify-cli の update をスキップ"
        return
    fi
    log "netlify-cli を更新 (bun update -g netlify-cli)"
    bun update -g netlify-cli || warn "netlify-cli の update に失敗"
}
