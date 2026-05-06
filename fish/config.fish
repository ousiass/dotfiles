if status is-interactive
    # Commands to run in interactive sessions can go here
    alias g='git'
    alias m='make'
    alias ga='git add .'
    alias gp='git push'
    alias reload='source ~/.config/fish/config.fish'
    alias t='tmux'
    alias e='exit'
    alias ns='nvidia-smi'
    alias v='nvim'
    alias vo='nvim .'
    alias c='claude --dangerously-skip-permissions'
    alias cc='claude --dangerously-skip-permissions --continue'
    alias cs='claude --dangerously-skip-permissions --settings '\''{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false}}'\'''
end

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
