# fnm (Fast Node Manager) の fish 統合
#
# `fnm env --use-on-cd` は PATH や FNM_* 環境変数をセットするスクリプトを
# fish 構文で出力する。--use-on-cd で .nvmrc / .node-version のあるディレクトリに
# cd した時に Node バージョンを自動切替する。

if status is-interactive
    # conf.d はアルファベット順にロードされ、fnm.fish は paths.fish より先に走る。
    # Tailscale SSH login のように execve 環境の PATH が最小なケースでも fnm を
    # 見つけられるよう、ここで fnm のインストールパスを先に追加しておく。
    if test -d $HOME/.local/share/fnm; and not contains -- $HOME/.local/share/fnm $PATH
        set -gx PATH $HOME/.local/share/fnm $PATH
    end

    if command -v fnm >/dev/null 2>&1
        fnm env --use-on-cd | source
    end
end
