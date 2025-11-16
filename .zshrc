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

# Export path adding neovim
export PATH="$PATH:/opt/nvim-linux-x86_64/bin"
