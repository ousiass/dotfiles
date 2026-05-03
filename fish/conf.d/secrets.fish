# ~/.config/fish/conf.d/secrets.fish
#
# ~/.env から KEY=VALUE 形式の環境変数を読み込んで global にセットする。
# .env 自体は dotfiles に含まれず、各マシンで個別に作成（~/.env.example 参照）。
# .mcp.json の ${VAR} 形式の参照もここで設定された変数から解決される。

if test -f $HOME/.env
    for line in (cat $HOME/.env)
        # コメント行・空行をスキップ
        if string match -q -r '^\s*(#|$)' -- $line
            continue
        end
        # KEY=VALUE をパース
        set -l kv (string split --max 1 = -- $line)
        if test (count $kv) -eq 2
            # 値の前後のクォートを剥がす
            set -l val (string trim --chars '"\'' -- $kv[2])
            set -gx $kv[1] $val
        end
    end
end
