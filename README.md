# Neovim Setup

- brew install nvim
- brew install ripgrep
- brew install xclip
- Install https://iterm2.com/downloads.html
    - v3.4.x not v3.5.x
    - Then https://stackoverflow.com/a/37720002
- Download https://www.nerdfonts.com/font-downloads
    - Open the folder and double click a font and install it
- git clone git@github.com:eedmond/kickstart.nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim

# Utilities Setup

- git clone git@github.com:eedmond/utilities.git ~/Developer/utilities
- cd ~/Developer/utilities
- cp .zshrc ~/.zshrc
- cp .gitconfig ~/.gitconfig
    - Change any git config settings needed like default branch names in ~/.gitconfig
- cp .tmux.conf ~/.tmux.conf
