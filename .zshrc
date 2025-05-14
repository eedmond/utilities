parse_git_branch() {
    git branch 2> /dev/null | sed -n -e 's/^\* \(.*\)/[\1]/p'
}
function grt() {
    git rev-parse --show-toplevel
}
COLOR_DEF='%f'
COLOR_USR='%F{#6c7086}'
COLOR_DIR='%F{#f38ba8}'
COLOR_GIT='%F{#89b4fa}'
# About the prefixed `$`: https://tldp.org/LDP/Bash-Beginners-Guide/html/sect_03_03.html#:~:text=Words%20in%20the%20form%20%22%24',by%20the%20ANSI%2DC%20standard.
NEWLINE=$'\n'
# Set zsh option for prompt substitution
setopt PROMPT_SUBST
export PROMPT='${COLOR_USR}%n@%M ${COLOR_DIR}%d ${COLOR_GIT}$(parse_git_branch)${COLOR_DEF}${NEWLINE}%% '

alias gwt='(){ pushd ~/Developer/worktrees/$1/src ; }'
alias gohome='(){ pushd ~/Developer ; }'
alias xcode='(){ xed $(grt)/src/Project.xcodeproj ; }'

bindkey "^X\\x7f" backward-kill-line
bindkey "\e[H" beginning-of-line
bindkey "\e[F" end-of-line
