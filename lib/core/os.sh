# shellcheck shell=bash
# OS 検出。OS 変数に依存。

# ------------------------------------------------------------------
# OS 検出
# ------------------------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Linux)  OS=linux ;;
        Darwin) OS=mac ;;
        *) err "Unsupported OS: $(uname -s)"; exit 1 ;;
    esac
    log "OS: $OS"
}
