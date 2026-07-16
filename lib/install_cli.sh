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
    if [[ -n "${CLAUDECODE:-}" ]]; then
        warn "Claude Code セッション中のため claude update をスキップ"
        warn "  → Claude Code を終了してから 'claude update' を手動実行してください"
        return
    fi
    log "Claude Code を更新 (claude update)"
    claude update || warn "claude update に失敗"
}

install_codex() {
    install_codex_cli "$@"
}

install_codex_fugu() {
    install_fugu "$@"
}

install_codex_cli() {
    local fugu_target current
    fugu_target="$(fugu_codex_target || true)"

    if [[ -n "$fugu_target" ]]; then
        current="$(codex_cli_version || true)"
        if [[ "$current" == "$fugu_target" ]]; then
            log "Codex CLI は Fugu target と整合済み ($current)"
            return
        fi
        log "Codex CLI を Fugu target に自動整合 (${current:-未インストール} -> $fugu_target)"
        sync_fugu_codex
        return
    fi

    if command -v codex >/dev/null 2>&1; then
        current="$(codex_cli_version || true)"
        log "Codex CLI は既にインストール済み${current:+ ($current)}"
        return
    fi

    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が見つからないため Codex CLI インストールをスキップ"
        return
    fi

    log "Codex CLI をインストール (bun -g @openai/codex)"
    bun install -g @openai/codex
}

codex_session_active() {
    [[ -n "${CODEX_CI:-}" || -n "${CODEX_THREAD_ID:-}" ]]
}

codex_cli_version() {
    codex --version 2>/dev/null | grep -oE 'codex-cli[[:space:]]+[0-9][0-9.]*' | head -n1 | awk '{print $2}'
}

load_fugu_env() {
    local env_file="$DOTFILES_DIR/.env"
    if [[ -z "${SAKANA_API_KEY:-}" && -f "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        . "$env_file" || true
        set +a
    fi
}

fugu_installer_path() {
    local bundle_file repo_dir
    bundle_file="$(fugu_bundle_file || true)"
    if [[ -n "$bundle_file" ]]; then
        repo_dir="$(dirname "$(dirname "$bundle_file")")"
        if [[ -x "$repo_dir/scripts/install.sh" ]]; then
            printf '%s/scripts/install.sh' "$repo_dir"
            return
        fi
    fi

    if [[ -x "$HOME/.fugu/scripts/install.sh" ]]; then
        printf '%s/.fugu/scripts/install.sh' "$HOME"
    fi
}

sync_fugu_codex() {
    load_fugu_env

    if codex_session_active; then
        warn "Codex/Fugu セッション中のため Codex/Fugu 自動整合をスキップ"
        warn "  → このセッションを終了してから './install.sh fugu' または './update.sh codex_fugu' を実行してください"
        return
    fi

    local installer
    installer="$(fugu_installer_path || true)"
    if [[ -n "$installer" ]]; then
        log "Fugu installer で Codex と codex-fugu を自動整合 (--yes --force)"
        FUGU_ASSUME_YES=1 FUGU_FORCE=1 "$installer" --yes --force \
            || warn "Fugu/Codex の自動整合に失敗"
        return
    fi

    if [[ -z "${SAKANA_API_KEY:-}" ]]; then
        warn "SAKANA_API_KEY が未設定のため Fugu インストーラ取得をスキップ"
        warn "  → $DOTFILES_DIR/.env に SAKANA_API_KEY=... を追加して再実行"
        return
    fi

    log "Fugu installer を取得して Codex と codex-fugu を自動整合 (--yes --force)"
    FUGU_ASSUME_YES=1 FUGU_FORCE=1 bash -c 'curl -fsSL https://sakana.ai/fugu/install | bash' \
        || warn "Fugu/Codex の自動整合に失敗"
}

fugu_state_file() {
    printf '%s/.fugu/state' "${CODEX_HOME:-$HOME/.codex}"
}

fugu_bundle_file() {
    local state_file repo_dir
    state_file="$(fugu_state_file)"
    if [[ -f "$state_file" ]]; then
        repo_dir="$(sed -n 's/^repo_dir=//p' "$state_file" | tail -n1)"
        if [[ -n "$repo_dir" && -f "$repo_dir/configs/bundle.sh" ]]; then
            printf '%s/configs/bundle.sh' "$repo_dir"
            return
        fi
    fi

    if [[ -f "$HOME/.fugu/configs/bundle.sh" ]]; then
        printf '%s/.fugu/configs/bundle.sh' "$HOME"
    fi
}

fugu_codex_target() {
    local state_file bundle_file target
    state_file="$(fugu_state_file)"
    if [[ -f "$state_file" ]]; then
        target="$(sed -n 's/^deployed_target=//p' "$state_file" | tail -n1)"
        if [[ -n "$target" ]]; then
            printf '%s' "$target"
            return
        fi
    fi

    bundle_file="$(fugu_bundle_file || true)"
    if [[ -n "$bundle_file" && -f "$bundle_file" ]]; then
        awk -F= '/^BUNDLE_CODEX_VERSION=/ { gsub(/"/, "", $2); print $2; exit }' "$bundle_file"
    fi
}

update_codex() {
    update_codex_cli "$@"
}

update_codex_fugu() {
    update_fugu "$@"
}

update_codex_cli() {
    local fugu_target current
    fugu_target="$(fugu_codex_target || true)"

    if [[ -n "$fugu_target" ]]; then
        current="$(codex_cli_version || true)"
        if [[ "$current" == "$fugu_target" ]]; then
            log "Codex CLI は Fugu target と整合済み ($current)"
            return
        fi
        log "Codex CLI を Fugu target に自動整合 (${current:-未インストール} -> $fugu_target)"
        sync_fugu_codex
        return
    fi

    if ! command -v codex >/dev/null 2>&1; then
        warn "codex が無いため update をスキップ"
        return
    fi

    if codex_session_active; then
        warn "Codex セッション中のため codex update をスキップ"
        warn "  → Codex を終了してから 'codex update' を手動実行してください"
        return
    fi

    # Fugu 非管理の通常 Codex では、現在有効な `codex` 自身に更新させる。
    if codex help update >/dev/null 2>&1; then
        log "Codex CLI を更新 (codex update)"
        codex update || warn "codex update に失敗"
        return
    fi

    if command -v bun >/dev/null 2>&1; then
        log "Codex CLI を更新 (bun update -g @openai/codex)"
        bun update -g @openai/codex || warn "codex の update に失敗"
    elif command -v npm >/dev/null 2>&1; then
        log "Codex CLI を更新 (npm install -g @openai/codex)"
        npm install -g @openai/codex || warn "codex の update に失敗"
    else
        warn "bun/npm が無いため codex の update をスキップ"
    fi
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

# ------------------------------------------------------------------
# Fugu (Sakana AI の Codex 設定バンドル)
# ------------------------------------------------------------------
# 公式 install.sh は SAKANA_API_KEY を env から読めれば対話プロンプトを出さない。
# ~/.env を一時 source して取り出し、無ければ warn してスキップする
# （install.sh 全体を止めずに「鍵が用意できたら次回入る」運用にする）。
install_fugu() {
    sync_fugu_codex
}


update_fugu() {
    sync_fugu_codex
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
# herdr (コーディングエージェント向けターミナルマルチプレクサ)
# ------------------------------------------------------------------
# 公式 install.sh をそのまま実行。~/.local/bin にバイナリを配置する想定なので
# PATH の先行追加に載っている（install.sh 冒頭で export 済み）。
install_herdr() {
    if command -v herdr >/dev/null 2>&1; then
        log "herdr は既にインストール済み"
        return
    fi
    log "herdr をインストール"
    curl -fsSL https://herdr.dev/install.sh | sh || warn "herdr のインストールに失敗"
}

update_herdr() {
    if ! command -v herdr >/dev/null 2>&1; then
        warn "herdr が無いため update をスキップ"
        return
    fi
    # herdr には公式のセルフアップデートコマンドが未確認なので、
    # インストーラを再実行する（idempotent 想定）。
    log "herdr を更新 (公式インストーラ再実行)"
    curl -fsSL https://herdr.dev/install.sh | sh || warn "herdr の update に失敗"
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
# Cloudflare Tunnel デーモン (apt / brew)
# ------------------------------------------------------------------
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
install_wrangler() {
    if command -v wrangler >/dev/null 2>&1; then
        log "wrangler は既にインストール済み"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が見つからないため wrangler インストールをスキップ"
        return
    fi
    log "wrangler をインストール (bun -g wrangler)"
    bun install -g wrangler
}

update_wrangler() {
    if ! command -v wrangler >/dev/null 2>&1; then
        warn "wrangler が無いため update をスキップ"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が無いため wrangler の update をスキップ"
        return
    fi
    log "wrangler を更新 (bun update -g wrangler)"
    bun update -g wrangler || warn "wrangler の update に失敗"
}

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

# ------------------------------------------------------------------
# 外部 agent-skills (bunx skills / skills.sh マニフェスト方式)
# ------------------------------------------------------------------
# ~/dotfiles/agent-skills.txt を読み、`bunx skills add --agent universal`
# で ~/.agents/skills/ に skill 本体を配置する（agent 個別のディレクトリは
# 汚さない）。その上で link_agent_skills が ~/.claude/skills/<name> と
# ~/.codex/skills/<name> にそれぞれ symlink を張って両 agent から参照
# できるようにする。
#
# ~/.claude は ~/dotfiles/.claude への symlink なので、Claude 側の
# symlink は ~/dotfiles/.claude/skills/ 配下に現れる。リンク先の
# ~/.agents/skills/ はマシン依存なので sync_agent_skills_gitignore で
# .gitignore を自動生成して git 追跡から除外する。
#
# 名前衝突対策: ユーザー自作 skill (実体ディレクトリ) と同名の外部 skill
# が来た場合は自作を優先し、link をスキップする。
install_agent_skills() {
    local manifest="$DOTFILES_DIR/agent-skills.txt"
    [[ -f "$manifest" ]] || { warn "$manifest が無いため agent-skills インストールをスキップ"; return; }
    if ! command -v bunx >/dev/null 2>&1; then
        warn "bunx が無いため agent-skills インストールをスキップ"
        return
    fi

    log "agent-skills をインストール (bunx skills)"

    local line pkg skills_part
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue

        if [[ "$line" == *"@"* ]]; then
            pkg="${line%%@*}"
            skills_part="${line#*@}"
        else
            pkg="$line"
            skills_part="*"
        fi

        log "  + $pkg (skills: $skills_part)"
        bunx skills add "$pkg" --skill "$skills_part" --agent universal --global -y \
            || warn "agent-skill '$line' のインストールに失敗"
    done < "$manifest"

    link_agent_skills
    sync_agent_skills_gitignore
}

# ~/.agents/skills/<name> を ~/.claude/skills/<name> と
# ~/.codex/skills/<name> に symlink。
# 既存の実体ディレクトリ（ユーザー自作 skill）は保護する。
link_agent_skills() {
    local src_root="$HOME/.agents/skills"
    [[ -d "$src_root" ]] || return

    local claude_dst="$HOME/.claude/skills"
    local codex_dst="$HOME/.codex/skills"
    mkdir -p "$claude_dst" "$codex_dst"

    local skill_dir name dst
    for skill_dir in "$src_root"/*/; do
        [[ -d "$skill_dir" ]] || continue
        name="$(basename "$skill_dir")"
        [[ "$name" == .* ]] && continue

        for dst in "$claude_dst/$name" "$codex_dst/$name"; do
            # 自作 skill (実ディレクトリ、または dotfiles を指す symlink) は保護。
            # 上書きしていいのは「存在しない」or「既に ~/.agents/skills/ を指す」場合のみ。
            if [[ -L "$dst" ]]; then
                local current
                current="$(readlink "$dst")"
                if [[ "$current" != "$src_root/$name" ]]; then
                    warn "$dst は既存リンク ($current) と衝突するため link をスキップ"
                    continue
                fi
            elif [[ -e "$dst" ]]; then
                warn "$dst は自作 skill と衝突するため link をスキップ"
                continue
            fi
            make_symlink "$dst" "$src_root/$name" >/dev/null || true
        done
    done
}

# ~/dotfiles/.claude/skills/.gitignore に外部 skill 名を書き出す。
# これらは ~/.agents/skills/ を指す symlink でマシン依存なので、
# git 追跡から外す。ユーザー自作 skill (既に tracked) は無影響。
sync_agent_skills_gitignore() {
    local src_root="$HOME/.agents/skills"
    local gitignore="$DOTFILES_DIR/.claude/skills/.gitignore"
    [[ -d "$src_root" ]] || return
    mkdir -p "$(dirname "$gitignore")"

    local tmp
    tmp="$(mktemp)"
    {
        echo "# Auto-generated by install_agent_skills — do not edit."
        echo "# 外部 agent-skills (~/.agents/skills/) への symlink 群。"
        local skill_dir name
        for skill_dir in "$src_root"/*/; do
            [[ -d "$skill_dir" ]] || continue
            name="$(basename "$skill_dir")"
            [[ "$name" == .* ]] && continue
            echo "/$name"
        done
    } > "$tmp"

    if ! cmp -s "$tmp" "$gitignore" 2>/dev/null; then
        mv "$tmp" "$gitignore"
        log "$gitignore を更新"
    else
        rm -f "$tmp"
    fi
}

update_agent_skills() {
    if ! command -v bunx >/dev/null 2>&1; then
        warn "bunx が無いため agent-skills 更新をスキップ"
        return
    fi
    log "agent-skills を更新 (bunx skills update -g -y)"
    bunx skills update -g -y || warn "agent-skills の update に失敗"
    link_agent_skills
    sync_agent_skills_gitignore
}
