# shellcheck shell=bash
# pm2 installer/updater. common.sh の log/warn に依存。

install_pm2() {
    if command -v pm2 >/dev/null 2>&1; then
        log "pm2 は既にインストール済み"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が見つからないため pm2 インストールをスキップ"
        return
    fi
    log "pm2 をインストール (bun -g pm2)"
    bun install -g pm2
}
update_pm2() {
    if ! command -v pm2 >/dev/null 2>&1; then
        warn "pm2 が無いため update をスキップ"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が無いため pm2 の update をスキップ"
        return
    fi
    log "pm2 を更新 (bun update -g pm2)"
    bun update -g pm2 || warn "pm2 の update に失敗"
}

# ------------------------------------------------------------------
# 自作 Go ツール (go install で取得、$HOME/go/bin に配置)
# ------------------------------------------------------------------
