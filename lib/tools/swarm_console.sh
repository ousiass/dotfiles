# shellcheck shell=bash
# swarm-console installer. common.sh の log/warn/err/make_symlink と OS に依存。
#
# GitHub Releases（ousiassllc/swarm-console）の linux/amd64 バイナリを
# ~/bin/swarm-console/swarm-console に通常ファイルとして置き、systemd のユーザーサービスに登録する。
#   - シンボリックリンクにしない。本体の自己更新は、この場所の通常ファイルを入れ替えるため
#   - 一度置いたら再ダウンロードしない。更新は本体の自己更新に任せる（update.sh には載せない）
#   - config.toml とトークンはマシンごと・秘密なので dotfiles では管理しない（README 参照）

SWARM_CONSOLE_RELEASES_URL="https://github.com/ousiassllc/swarm-console/releases"

# バイナリは linux/amd64 だけ。それ以外（macOS / arm64）はスキップ。
swarm_console_supported() {
    local arch
    arch="$(uname -m)"
    if [[ "${OS:-}" != "linux" || ( "$arch" != "x86_64" && "$arch" != "amd64" ) ]]; then
        log "swarm-console は linux/amd64 のみ対応のためスキップ (OS=${OS:-不明}, arch=${arch})"
        return 1
    fi
    return 0
}

swarm_console_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# 最新リリースを取得し、SHA256SUMS と照合してから置く。照合が合わなければ何も置かず失敗にする。
install_swarm_console_binary() {
    local dir="$HOME/bin/swarm-console"
    local bin="$dir/swarm-console"

    if [[ -e "$bin" || -L "$bin" ]]; then
        if [[ -L "$bin" ]]; then
            warn "$bin はシンボリックリンクです。自己更新は通常ファイルが前提なので、通常ファイルに置き換えてください"
        fi
        log "swarm-console は既に配置済み（更新は本体の自己更新に任せる）"
        return 0
    fi

    command -v curl >/dev/null 2>&1 || { err "curl が無いため swarm-console を取得できません"; return 1; }

    local sums matches count expected asset tag
    sums="$(curl -fsSL "$SWARM_CONSOLE_RELEASES_URL/latest/download/SHA256SUMS")" || {
        err "swarm-console の SHA256SUMS の取得に失敗"
        return 1
    }
    # 行の形式: <sha256>  <asset 名>（バイナリモードは名前の前に * が付く）
    matches="$(
        printf '%s\n' "$sums" | awk '{
            n = $2; sub(/^\*/, "", n)
            if (n ~ /^swarm-console_.+_linux_amd64$/) print $1 " " n
        }'
    )"
    count="$(printf '%s\n' "$matches" | grep -c . || true)"
    if [[ "$count" != "1" ]]; then
        err "SHA256SUMS に swarm-console_<版>_linux_amd64 の行が 1 つではありません (${count} 行)"
        return 1
    fi
    expected="${matches%% *}"
    asset="${matches#* }"
    if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
        err "SHA256SUMS のハッシュの形式が不正です"
        return 1
    fi
    tag="${asset#swarm-console_}"
    tag="${tag%_linux_amd64}"

    mkdir -p "$dir"
    # 同じフォルダに一時ファイルを作り、照合後に rename で置く（途中の状態を bin に残さない）
    local tmp actual
    tmp="$(mktemp "$dir/.swarm-console.XXXXXX")"
    log "swarm-console $tag をダウンロード"
    if ! curl -fsSL "$SWARM_CONSOLE_RELEASES_URL/download/$tag/$asset" -o "$tmp"; then
        rm -f "$tmp"
        err "swarm-console のダウンロードに失敗"
        return 1
    fi
    actual="$(swarm_console_sha256 "$tmp")"
    if [[ "$actual" != "$expected" ]]; then
        rm -f "$tmp"
        err "swarm-console の sha256 が SHA256SUMS と一致しません（期待 ${expected} / 実際 ${actual}）。置きません"
        return 1
    fi
    chmod 0755 "$tmp"
    mv -f "$tmp" "$bin"
    log "swarm-console $tag を $bin に配置 (sha256 照合済み)"
}

# systemd のユーザーサービスに登録する。config.toml が無ければ起動せず、設定の手順を案内する。
install_swarm_console_service() {
    local unit_dir="${CONFIG_DIR:-$HOME/.config}/systemd/user"
    # ユニットの --config が %h/.config/swarm-console/config.toml 固定なので、同じ場所を見る
    local config="$HOME/.config/swarm-console/config.toml"
    local user

    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl が無いため swarm-console のサービス登録をスキップ"
        return 0
    fi

    make_symlink "$unit_dir/swarm-console.service" "$DOTFILES_DIR/systemd/swarm-console.service" || true
    systemctl --user daemon-reload || { err "systemctl --user daemon-reload に失敗"; return 1; }

    if [[ -f "$config" ]]; then
        systemctl --user enable --now swarm-console.service || { err "swarm-console.service の enable --now に失敗"; return 1; }
    else
        systemctl --user enable swarm-console.service || { err "swarm-console.service の enable に失敗"; return 1; }
        log "$config がまだ無いため、swarm-console は起動していません。設定してから起動してください:"
        log "  1. ~/bin/swarm-console/swarm-console setup （または config.toml を手で書く）"
        log "  2. ~/bin/swarm-console/swarm-console token add <名前> --scope ops|report"
        log "  3. systemctl --user start swarm-console"
        log "  詳細は README の「swarm-console」を参照"
    fi

    # ログアウトしてもユーザーサービスを止めない。権限が無ければ警告だけにする（パスワードは聞かない）
    user="$(id -un)"
    if command -v loginctl >/dev/null 2>&1; then
        if [[ "$(loginctl show-user "$user" -p Linger 2>/dev/null)" == "Linger=yes" ]]; then
            log "linger は既に有効"
        elif loginctl --no-ask-password enable-linger "$user" </dev/null; then
            log "linger を有効化 ($user)"
        else
            warn "loginctl enable-linger に失敗。ログアウトするとユーザーサービスが止まります"
        fi
    else
        warn "loginctl が無いため linger を有効化できません"
    fi
}

install_swarm_console() {
    swarm_console_supported || return 0
    install_swarm_console_binary || return 1
    install_swarm_console_service
}
