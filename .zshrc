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
COLOR_ERR='%F{#f38ba8}'
COLOR_DIM='%F{#6c7086}'
# About the prefixed `$`: https://tldp.org/LDP/Bash-Beginners-Guide/html/sect_03_03.html#:~:text=Words%20in%20the%20form%20%22%24',by%20the%20ANSI%2DC%20standard.
NEWLINE=$'\n'
# Set zsh option for prompt substitution
setopt PROMPT_SUBST

# Track command execution time
zmodload zsh/datetime
_cmd_start=0.0
preexec() { _cmd_start=$EPOCHREALTIME }
precmd() {
  if (( _cmd_start > 0 )); then
    _cmd_elapsed=$(( EPOCHREALTIME - _cmd_start ))
    _cmd_start=0.0
  else
    _cmd_elapsed=0.0
  fi
}

_fmt_elapsed() {
  local s=$_cmd_elapsed
  if (( s < 5 )); then
    echo ""
  elif (( s < 60 )); then
    printf "%.1fs " $s
  elif (( s < 3600 )); then
    echo "$(( int(s/60) ))m$(( int(s)%60 ))s "
  else
    echo "$(( int(s/3600) ))h$(( (int(s)%3600)/60 ))m "
  fi
}

export PROMPT='${COLOR_DIR}%d ${COLOR_GIT}$(parse_git_branch)${COLOR_DEF}${NEWLINE}%(?..[${COLOR_ERR}%?${COLOR_DEF}] )${COLOR_DIM}$(_fmt_elapsed)${COLOR_DEF}%% '
export RPROMPT='${COLOR_DIM}%*${COLOR_DEF}'

alias gwt='(){ pushd ~/Developer/worktrees/$1/src ; }'
alias gohome='(){ pushd ~/Developer ; }'
function xcopen() {
    # 1. Find the root of the git repository.
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null)

    if [[ -z "$git_root" ]]; then
        echo "Error: Not inside a git repository." >&2
        return 1
    fi

    # 2. Find all project/workspace files, filtering out unwanted internal ones.
    local files=()
    while IFS= read -r -d $'\0' file; do
        # We check if the path contains ".xcodeproj/" which indicates it's inside another project.
        if [[ "$file" != *".xcodeproj/"* ]]; then
            files+=("$file")
        fi
    done < <(find "$git_root" -path "$git_root/.git" -prune -o \( -name "*.xcodeproj" -o -name "*.xcworkspace" \) -print0)

    local count=${#files[@]}

    # 3. Handle the different cases.
    if [[ $count -eq 0 ]]; then
        echo "No .xcodeproj or .xcworkspace found in this project." >&2
        return 1
    elif [[ $count -eq 1 ]]; then
        echo "Opening the only project found: ${files[1]##*/}"
        xed "${files[1]}"
    else
        # 4. If multiple projects are found, prompt the user.
        echo "Multiple Xcode projects/workspaces found. Please choose one:"
        for i in {1..$count}; do
            printf "  %d) %s\n" "$i" "${files[i]#$git_root/}"
        done

        local choice
        while true; do
            printf "Enter number (or Ctrl+C to cancel): "
            read -r choice

            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
                local selected_file="${files[choice]}"
                echo "Opening ${selected_file##*/}..."
                xed "$selected_file"
                break
            else
                echo "Invalid choice. Please enter a number between 1 and $count."
            fi
        done
    fi
}

# Function to combine searching recursively for a file and opening it in Neovim
function fvim() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: fvim <filename>" >&2
        return 1
    fi
    local file
    file=$(find . -name "$name" -not -path '*/.git/*' | head -1)
    if [[ -z "$file" ]]; then
        echo "No file named '$name' found." >&2
        return 1
    fi
    nvim "$file"
}

bindkey "^X\\x7f" backward-kill-line
bindkey "\e[H" beginning-of-line
bindkey "\e[F" end-of-line
### ctrl+arrows
bindkey "\e[1;5C" forward-word
bindkey "\e[1;5D" backward-word
# urxvt
bindkey "\eOc" forward-word
bindkey "\eOd" backward-word
### ctrl+delete
bindkey "\e[3;5~" kill-word
# urxvt
bindkey "\e[3^" kill-word
### ctrl+backspace
bindkey '^H' backward-kill-word
### ctrl+shift+delete
bindkey "\e[3;6~" kill-line
# urxvt
bindkey "\e[3@" kill-line

# History
export HISTFILE=~/.hist_zsh
export HISTSIZE=100000
export SAVEHIST=$HISTSIZE

# HISTORY
setopt EXTENDED_HISTORY          # Write the history file in the ':start:elapsed;command' format.
setopt HIST_EXPIRE_DUPS_FIRST    # Expire a duplicate event first when trimming history.
setopt HIST_FIND_NO_DUPS         # Do not display a previously found event.
setopt HIST_IGNORE_ALL_DUPS      # Delete an old recorded event if a new event is a duplicate.
setopt HIST_IGNORE_DUPS          # Do not record an event that was just recorded again.
setopt HIST_IGNORE_SPACE         # Do not record an event starting with a space.
setopt HIST_SAVE_NO_DUPS         # Do not write a duplicate event to the history file.
setopt SHARE_HISTORY             # Share history between all sessions.
# END HISTORY

# Bash-like navigation
autoload -U select-word-style
select-word-style bash

export BAT_THEME="Catppuccin Mocha"

# Setup cd to map to zoxide
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
  alias cd='z'
fi

# Setup ls to map to eza
if command -v eza &>/dev/null; then
  alias ls='eza -lh --no-permissions --no-user --no-time --icons'
fi

# Setup fzf keybindings and fuzzy completion
if command -v fzf &>/dev/null; then
  eval "$(fzf --zsh)"
fi
