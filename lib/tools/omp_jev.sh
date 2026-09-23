# shellcheck shell=bash
# omp-jev-compaction（TypeSafe Jev context compaction）プラグイン installer/updater。
# common.sh の log/warn と DOTFILES_DIR に依存。意図は omp/README.md の「plugins」節を参照。
#
# https://github.com/jerryfane/omp-jev-compaction は `omp plugin install jerryfane/omp-jev-compaction`
# を公式手順として案内しているが、このリポジトリは dist/ を git 管理外にしており
# （npm の prepare フックでビルドする前提）、omp の github: 経由インストーラは
# そのビルドステップを実行しないため dist/hook.js 不在で検証エラーになる（実機で確認済み）。
# そのため git clone → npm install（prepare が tsc を実行）→ omp plugin install <local path>
# を自前で行う。Fugu と同じ「鍵が無ければ warn してスキップ」パターン。

omp_jev_src_dir() {
    printf '%s/.local/share/omp-plugins/omp-jev-compaction' "$HOME"
}

# TYPESAFE_API_KEY は fish 経由なら secrets.fish が export 済みだが、
# install.sh/update.sh は bash で走るため lib/tools/codex.sh の load_fugu_env と
# 同じパターンで $DOTFILES_DIR/.env から直接拾う。
load_omp_jev_env() {
    local env_file="$DOTFILES_DIR/.env"
    if [[ -z "${TYPESAFE_API_KEY:-}" && -f "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        . "$env_file" || true
        set +a
    fi
}

install_omp_jev() {
    if ! command -v omp >/dev/null 2>&1; then
        warn "omp が無いため omp-jev-compaction のインストールをスキップ"
        return
    fi
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm が無いため omp-jev-compaction のインストールをスキップ"
        return
    fi

    load_omp_jev_env
    if [[ -z "${TYPESAFE_API_KEY:-}" ]]; then
        warn "TYPESAFE_API_KEY が未設定のため omp-jev-compaction のインストールをスキップ"
        warn "  → $DOTFILES_DIR/.env に TYPESAFE_API_KEY=... を追加して再実行"
        return
    fi

    local src_dir
    src_dir="$(omp_jev_src_dir)"

    if [[ -d "$src_dir/.git" ]]; then
        log "omp-jev-compaction を更新 (git pull)"
        git -C "$src_dir" pull --ff-only || warn "omp-jev-compaction の git pull に失敗"
    else
        log "omp-jev-compaction を取得 (git clone)"
        mkdir -p "$(dirname "$src_dir")"
        git clone --depth 1 https://github.com/jerryfane/omp-jev-compaction "$src_dir" \
            || { warn "omp-jev-compaction の clone に失敗"; return; }
    fi

    log "omp-jev-compaction をビルド (npm install; prepare フックが tsc を実行)"
    (cd "$src_dir" && npm install) || { warn "omp-jev-compaction の npm install に失敗"; return; }

    if [[ ! -f "$src_dir/dist/hook.js" ]]; then
        warn "omp-jev-compaction のビルドに失敗（$src_dir/dist/hook.js が無い）"
        return
    fi

    log "omp-jev-compaction を omp に登録 (omp plugin install)"
    omp plugin install "$src_dir" || warn "omp-jev-compaction の omp plugin install に失敗"
}

# git pull + npm install + omp plugin install を毎回やり直すだけなので install と同じ実体でよい
# （Fugu の sync_fugu_codex と同じ「常に再同期」パターン。それぞれ冪等 / 高速に完了する）。
update_omp_jev() {
    install_omp_jev
}
