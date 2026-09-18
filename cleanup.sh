#!/usr/bin/env bash
#
# cleanup.sh - ディスク容量と I/O の定期掃除
#
# install.sh / update.sh がツールを入れる・更新するのに対し、こちらは
# 開発ツールが吐き出したキャッシュを掃除する。対象は「消しても再生成される
# もの」だけに限定し、成果物や永続データには触れない。
# 個別の失敗は warn を出して続行し、最後まで走り切る。
#
# 使い方:
#   ./cleanup.sh            # ユーザー権限でできる掃除をすべて実行
#   ./cleanup.sh diag       # 現状を表示するだけ（何も消さない）
#   ./cleanup.sh system     # sudo が必要な掃除（journal / snap / fstrim）
#   ./cleanup.sh go docker  # 個別に実行
#   make clean              # 同上 (Makefile 経由)
#
# 環境変数:
#   GO_CACHE_LIMIT_GB    go-build がこのサイズを超えたときだけ全消し (既定: 30)
#   CLAUDE_ARCHIVE_DAYS  subagents ログをこの日数より古ければ退避 (既定: 7)
#   ARCHIVE_DIR          subagents ログの退避先。親が無ければ退避はスキップ

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:/usr/local/go/bin:$PATH"

LOG_TAG=cleanup

# 掃除にツールのインストール関数は要らないので、log/warn/err だけ読み込む。
# shellcheck source=lib/core/log.sh
. "$DOTFILES_DIR/lib/core/log.sh"

GO_CACHE_LIMIT_GB="${GO_CACHE_LIMIT_GB:-30}"
CLAUDE_ARCHIVE_DAYS="${CLAUDE_ARCHIVE_DAYS:-7}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/mnt/fd016e4c-2b01-40a5-b133-f1f1164cecf3/claude-subagents-archive}"

# --- ヘルパー ---------------------------------------------------------------

# ディレクトリのサイズを GB (小数1桁) で返す。存在しなければ 0。
dir_size_gb() {
    local d="$1"
    [[ -d "$d" ]] || { echo "0.0"; return; }
    # -D: 引数のシンボリックリンクだけ辿る (キャッシュを NVMe へ逃がしてあるため)
    du -sbD "$d" 2>/dev/null | awk '{printf "%.1f", $1/1073741824}'
}

# $1 >= $2 を小数で比較する（bc に依存しない）。
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }

# ルートファイルシステムが載っている物理デバイス名（例: sdc）を返す。
root_disk() {
    local src; src="$(findmnt -no SOURCE / 2>/dev/null)"
    lsblk -no PKNAME "$src" 2>/dev/null | head -1
}

# --- 掃除 -------------------------------------------------------------------

# go-build は放置すると数百GBまで育つが、消すと次のビルドが全部やり直しになる。
# 毎回消すと常にビルドが遅くなるので、閾値を超えたときだけ全消しする。
clean_go() {
    command -v go >/dev/null || { warn "go が無いのでスキップ"; return; }
    local cache; cache="$(go env GOCACHE 2>/dev/null)"
    [[ -d "$cache" ]] || { warn "GOCACHE が見つからないのでスキップ"; return; }

    local size; size="$(dir_size_gb "$cache")"
    if ge "$size" "$GO_CACHE_LIMIT_GB"; then
        log "go-build: ${size}GB (閾値 ${GO_CACHE_LIMIT_GB}GB) → 全消しします"
        go clean -cache || warn "go clean -cache が失敗しました"
    else
        log "go-build: ${size}GB (閾値 ${GO_CACHE_LIMIT_GB}GB) → 残します"
    fi
}

clean_uv() {
    command -v uv >/dev/null || { warn "uv が無いのでスキップ"; return; }
    log "uv キャッシュを掃除します"
    uv cache clean || warn "uv cache clean が失敗しました"
}

clean_pip() {
    local pip; pip="$(command -v pip3 || command -v pip)"
    [[ -n "$pip" ]] || { warn "pip が無いのでスキップ"; return; }
    log "pip キャッシュを掃除します"
    "$pip" cache purge || warn "pip cache purge が失敗しました"
}

# goimports は自前のキャッシュを持ち、go clean では消えない。
clean_goimports() {
    local cache="$HOME/.cache/goimports"
    [[ -d "$cache" ]] || return
    log "goimports キャッシュ ($(dir_size_gb "$cache")GB) を削除します"
    rm -rf "$cache" || warn "goimports キャッシュの削除に失敗しました"
}

# volume には DB などの永続データが入るため、意図的に対象外にしている。
# volume も消したいときは docker volume prune を手で実行すること。
clean_docker() {
    command -v docker >/dev/null || { warn "docker が無いのでスキップ"; return; }
    docker info >/dev/null 2>&1 || { warn "docker が動いていないのでスキップ"; return; }
    log "docker の未使用イメージとビルドキャッシュを掃除します (volume は残します)"
    docker system prune -a -f || warn "docker system prune が失敗しました"
}

# Claude Code の subagents ログはファイル数が万単位まで増え、起動時のスキャンを
# 遅くする。会話履歴そのもの (*.jsonl) には触らず、古い subagents だけ退避する。
clean_claude() {
    # projects は NVMe への シンボリックリンクのことがある。find は既定で
    # 引数のリンクを辿らないので -H が要る (無いと黙って 0 件になる)。
    local projects="$HOME/.claude/projects"
    [[ -d "$projects" ]] || { warn "$projects が無いのでスキップ"; return; }

    if [[ ! -d "$(dirname "$ARCHIVE_DIR")" ]]; then
        warn "退避先 $(dirname "$ARCHIVE_DIR") が無いので subagents の退避をスキップ"
        warn "別の場所へ退避するには ARCHIVE_DIR=/path ./cleanup.sh claude"
        return
    fi

    local count
    count="$(find -H "$projects" -type f -path '*/subagents/*' -mtime "+$CLAUDE_ARCHIVE_DAYS" 2>/dev/null | wc -l)"
    if [[ "$count" -eq 0 ]]; then
        log "subagents: ${CLAUDE_ARCHIVE_DAYS}日より古いログはありません"
        return
    fi

    log "subagents: ${count} ファイルを $ARCHIVE_DIR へ退避します"
    mkdir -p "$ARCHIVE_DIR"
    ( cd "$projects" \
        && find . -type f -path '*/subagents/*' -mtime "+$CLAUDE_ARCHIVE_DAYS" -print0 2>/dev/null \
        | rsync -a --from0 --files-from=- --remove-source-files ./ "$ARCHIVE_DIR/" ) \
        || { warn "subagents の退避に失敗しました"; return; }

    # 中身を移したあとに残る空ディレクトリを片付ける。
    find -H "$projects" -mindepth 2 -type d -empty -delete 2>/dev/null
    log "subagents の退避が完了しました"
}

# tide は非同期プロンプトのために _tide_prompt_<PID> というユニバーサル変数を作る。
# tmux や SSH が切れて fish が強制終了されると、この変数が消えずに残る。
# fish のユニバーサル変数は単一ファイルに入っていて、1つ書き換えるたびに全体を
# 書き直すため、溜まるとキー入力のたびに数百KBの読み書きが走って端末が重くなる。
clean_fish() {
    command -v fish >/dev/null || { warn "fish が無いのでスキップ"; return; }

    local removed
    # fish のコードなので bash 側で $ を展開させない（意図的なシングルクォート）
    # shellcheck disable=SC2016
    removed="$(fish -c '
        set -l n 0
        for v in (set --universal --names | string match "_tide_prompt_*")
            set -l pid (string replace "_tide_prompt_" "" $v)
            if not test -d /proc/$pid
                set --erase --universal $v
                set n (math $n + 1)
            end
        end
        echo $n
    ' 2>/dev/null)"
    log "fish: 終了済みセッションの _tide_prompt_ を ${removed:-0} 個削除しました"

    # ユニバーサル変数の書き込みに失敗すると fish_variables<ランダム> が残る。
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
    local stale
    stale="$(find "$conf" -maxdepth 1 -name 'fish_variables?*' 2>/dev/null | wc -l)"
    if [[ "$stale" -gt 0 ]]; then
        find "$conf" -maxdepth 1 -name 'fish_variables?*' -delete 2>/dev/null
        log "fish: 書き込み失敗の残骸ファイルを ${stale} 個削除しました"
    fi
}

# sudo が要るもの。ログの整理と、SSD へ空きブロックを通知して書き込み性能を戻す。
clean_system() {
    log "journal ログを 500MB に縮小します"
    sudo journalctl --vacuum-size=500M || warn "journalctl --vacuum-size が失敗しました"

    log "snap の保持リビジョン数を 2 にします"
    sudo snap set system refresh.retain=2 || warn "snap set system が失敗しました"

    log "snap の旧リビジョンを削除します"
    snap list --all 2>/dev/null | awk '/disabled|無効/{print $1, $3}' | while read -r name rev; do
        sudo snap remove "$name" --revision="$rev" || warn "snap remove $name ($rev) をスキップ"
    done

    log "fstrim で SSD の空きブロックを通知します"
    sudo fstrim -av || warn "fstrim が失敗しました"
}

# --- 診断 -------------------------------------------------------------------

diag() {
    log "ディスク使用量"
    df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | grep -vE '^(efivarfs)'

    echo
    log "資源の詰まり具合 (some = 一部が待たされた時間の割合 %)"
    local r
    for r in cpu io memory; do
        printf '  %-7s %s\n' "$r" "$(grep '^some' "/proc/pressure/$r" 2>/dev/null)"
    done

    local disk; disk="$(root_disk)"
    if [[ -n "$disk" && -r "/sys/block/$disk/stat" ]]; then
        echo
        local a b
        a="$(awk '{print $10}' "/sys/block/$disk/stat")"
        sleep 5
        b="$(awk '{print $10}' "/sys/block/$disk/stat")"
        log "ルートディスク ($disk) の稼働率: $(( (b - a) / 50 ))% (5秒間)"
    fi

    echo
    log "キャッシュの大きいもの"
    du -shD "$HOME/.cache"/* 2>/dev/null | sort -rh | head -8

    echo
    log "Claude Code の履歴"
    printf '  %s ファイル / %s\n' \
        "$(find -H "$HOME/.claude/projects" -type f 2>/dev/null | wc -l)" \
        "$(du -shD "$HOME/.claude/projects" 2>/dev/null | cut -f1)"
}

# --- エントリポイント -------------------------------------------------------

clean_all() {
    clean_go
    clean_uv
    clean_pip
    clean_goimports
    clean_docker
    clean_claude
    clean_fish
}

main() {
    if [[ $# -gt 0 ]]; then
        local target
        for target in "$@"; do
            case "$target" in
                diag)   diag ;;
                system) clean_system ;;
                all)    clean_all ;;
                *)
                    local fn="clean_${target}"
                    if ! declare -F "$fn" >/dev/null; then
                        err "$fn は未定義です"
                        exit 1
                    fi
                    "$fn"
                    ;;
            esac
        done
        return
    fi

    clean_all
    echo
    log "掃除完了 (sudo が要る分は ./cleanup.sh system)"
    df -h / | tail -1
}

# テストから source したときは main を走らせない。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
