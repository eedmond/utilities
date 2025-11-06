# Mac/Linux/WSL Setup

- Convert Caps Lock to ctrl
    - Settings -> Keyboard -> Shortcuts -> Modifier Keys
- Change setting to make each display part of the same desktop
- Download https://www.nerdfonts.com/font-downloads
    - Open the folder and double click a font and install it
```shell
brew install nvim
brew install ripgrep
brew install xclip
```

#### On WSL:
```shell
sudo apt-get install build-essential
```
Also, edit `/etc/wsl.conf` to include:
```
[user]
default=eedmond
```

# Neovim
- `git clone git@github.com:eedmond/kickstart.nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim`
- I’m now trying:
    - https://github.com/wojciech-kulik/ios-dev-starter-nvim
        - Had to run ":XcodebuildSetup"
- MarkdownPreview setup:
    - After installing the plugin, open a markdown file and run `:call mkdp#util#install()`

# iTerm2
- Install https://iterm2.com/downloads.html
    - v3.4.x not v3.5.x
- Set up shortcuts https://stackoverflow.com/a/37720002
    - Remove alt+left and alt+right in Settings -> Profiles -> Keys -> Key Mappings
    - system settings > keyboard > keyboard shortcuts > input sources > uncheck both of those.
    - `Settings -> General -> Selection` check `Applications in terminal may access clipboard`
- In Settings, use the nerdfonts that was installed
- Enable Settings -> Profiles -> Terminal -> Enable mouse reporting
- Download catppuccin theme
    - https://github.com/catppuccin/iterm/blob/main/colors/catppuccin-mocha.itermcolors
    - Set it under Settings -> Profiles -> Colors -> Presets

# tmux
- Learning it: https://www.youtube.com/watch?v=niuOc02Rvrc&ab_channel=typecraft
- Setup:
    - https://www.youtube.com/watch?v=jaI3Hcw-ZaA&ab_channel=typecraft
    - https://www.youtube.com/watch?v=DzNmUNvnB04&ab_channel=DreamsofCode
- I use ctrl+space (ctrl == caps lock) for leader
- TPM
    - git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
    - tmux-resurrect
        - Amazing plugin for saving and restoring entire sessions! Just <leader>+C-s to save and <leader>+C-r to restore.
    - Install plugins (one-time setup)
        - Run `ctrl+space I`
- Color theme setup:
    - https://github.com/catppuccin/tmux
        - mkdir -p ~/.config/tmux/plugins/catppuccin
        - git clone -b v2.1.3 https://github.com/catppuccin/tmux.git ~/.config/tmux/plugins/catppuccin/tmux
- Connecting to a remote machine's tmux
```shell
ssh username@{ip/device} -t "/usr/local/bin/tmux" a
```

# Utilities Setup
```shell
git clone git@github.com:eedmond/utilities.git ~/Developer/utilities
cd ~/Developer/utilities
cp .zshrc ~/.zshrc
cp .gitconfig ~/.gitconfig
cp .tmux.conf ~/.tmux.conf
```
