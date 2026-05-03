# fnm (Fast Node Manager) の fish 統合
#
# `fnm env --use-on-cd` は PATH や FNM_* 環境変数をセットするスクリプトを
# fish 構文で出力する。--use-on-cd で .nvmrc / .node-version のあるディレクトリに
# cd した時に Node バージョンを自動切替する。

if status is-interactive
    if command -v fnm >/dev/null 2>&1
        fnm env --use-on-cd | source
    end
end
