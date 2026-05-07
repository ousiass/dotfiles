# fish/conf.d/paths.fish に対応する POSIX shell 版。
#
# bash の login shell (~/.profile から source) で PATH に各種ツールを追加する。
# Claude Code の Bash ツールのような non-interactive bash でも、login shell が
# PATH を設定済みであれば親プロセス経由で継承される。
# fish 側 (paths.fish) と同じ集合を扱うこと。両者を同期して更新する。

for _p in \
    "$HOME/.local/bin" \
    "$HOME/.bun/bin" \
    "$HOME/.cargo/bin" \
    "$HOME/.local/share/fnm" \
    "$HOME/.local/share/pnpm" \
    "$HOME/.opencode/bin" \
    "$HOME/go/bin" \
    "/usr/local/go/bin" \
    "/opt/nvim" \
    "/opt/homebrew/bin" \
    "/opt/homebrew/sbin"
do
    if [ -d "$_p" ]; then
        case ":$PATH:" in
            *":$_p:"*) ;;
            *) PATH="$_p:$PATH" ;;
        esac
    fi
done
unset _p
export PATH
