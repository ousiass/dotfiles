# shellcheck shell=bash
# Gemini CLI installer/updater. common.sh の log/warn に依存。

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

# ------------------------------------------------------------------
# Fugu (Sakana AI の Codex 設定バンドル)
# ------------------------------------------------------------------
# 公式 install.sh は SAKANA_API_KEY を env から読めれば対話プロンプトを出さない。
# ~/.env を一時 source して取り出し、無ければ warn してスキップする
# （install.sh 全体を止めずに「鍵が用意できたら次回入る」運用にする）。
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
# herdr (コーディングエージェント向けターミナルマルチプレクサ)
# ------------------------------------------------------------------
# 公式 install.sh をそのまま実行。~/.local/bin にバイナリを配置する想定なので
# PATH の先行追加に載っている（install.sh 冒頭で export 済み）。
