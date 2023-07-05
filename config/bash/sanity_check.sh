source $HOME/.local/bin/scripts/color.sh

if ! command -v nvim &> /dev/null
then
    echo -e "${color_yellow}WARNING:$color_reset nvim not installed"
    echo -e "  you're in for a lot of pain"
    echo -e "  ADVICE: go to$color_purple" 'https://github.com/neovim/neovim/releases' $color_reset
    echo -e "  or install from package manager"
fi

if [ -z ${NVIM_PYTHON+x} ]
then
    echo -e "${color_red}ERROR:$color_reset" '$NVIM_PYTHON not set. This will break neovim'
    echo '  ADVICE: create a virtual environment just for neovim with the following commands:'
    echo -e $color_purple
    echo '  mkdir -p $HOME/.local/virtualenvs/'
    echo '  pushd !$  # Enter directory above'
    echo '  python3 -m venv nvim'
    echo -e $color_reset
fi

if ! command -v fzf &> /dev/null
then
    echo -e "${color_yellow}WARNING:$color_reset fzf not installed."
    echo -e "  ADVICE: go to$color_purple" 'https://github.com/junegunn/fzf#using-git' $color_reset
    echo '  and install using git or package manager'
    echo
fi

if ! command -v ag &> /dev/null
then
    echo -e "${color_yellow}WARNING:$color_reset ag (the_silver_searcher) not installed."
    echo -e "  ADVICE: go to$color_purple" 'https://github.com/ggreer/the_silver_searcher#installing' $color_reset
    echo "  and install from package manager"
    echo
fi


if ! command -v fd &> /dev/null
then
    echo -e "${color_yellow}WARNING:$color_reset fd (find alternative) not installed."
    echo -e "  ADVICE: go to$color_purple" 'https://github.com/sharkdp/fd#installation' $color_reset
    echo "  and install from package manager"
    echo
fi


if ! command -v rg &> /dev/null
then
    echo -e "${color_yellow}WARNING:$color_reset rg (ripgrep) not installed."
    echo -e "  ADVICE: go to$color_purple" 'https://github.com/BurntSushi/ripgrep#installation' $color_reset
    echo "  and install from package manager"
    echo
fi

if ! command -v gum &> /dev/null
then
    echo -e "${color_yellow}WARNING:$color_reset gum not installed"
    echo -e "  it's a neat little utility for making interactive scripts"
    echo -e "  some scripts may not work without it"
    echo -e "  ADVICE: go to$color_purple" 'https://github.com/charmbracelet/gum#installation' $color_reset
    echo -e "  and install from package manager"
fi

if ! command -v lazygit &> /dev/null
then
    echo -e "${color_yellow}WARNING:$color_reset lazygit not installed"
    echo -e "  nice little tui for git"
    echo -e "  ADVICE: go to$color_purple" 'https://github.com/jesseduffield/lazygit' $color_reset
    echo -e "  and install from package manager"
fi

if [[ -n $NVIM_PYTHON ]]; then
  if ! [[ -f $NVIM_PYTHON ]]; then
    echo -e "${color_yellow}WARNING:$color_reset NVIM_PYTHON set but invalid"
  fi
fi
