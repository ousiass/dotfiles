# uv が ~/.local/bin/env.fish を生成する（uv 未インストールのマシンでは無視）
if test -f "$HOME/.local/bin/env.fish"
    source "$HOME/.local/bin/env.fish"
end
