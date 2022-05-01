source ~/.config/bash/color.sh

if [ -z ${NVIM_PYTHON+x} ]
then
    echo -e "${red}ERROR:$reset" '$NVIM_PYTHON not set. This will break neovim'
    echo '  ADVICE: create a virtual environment just for neovim with the following commands:'
    echo -e $purple
    echo '  mkdir -p $HOME/.local/virtualenvs/'
    echo '  pushd $!  # Enter directory above'
    echo '  python3 -m venv nvim'
    echo -e $reset
fi

if ! command -v fzf &> /dev/null
then
    echo -e "${yellow}WARNING:$reset fzf not installed."
    echo -e "  ADVICE: go to$purple" 'https://github.com/junegunn/fzf#using-git' $reset
    echo '  and install using git or package manager'

fi

if ! command -v ag &> /dev/null
then
    echo -e "${yellow}WARNING:$reset ag (the_silver_searcher) not installed."
    echo -e "  ADVICE: go to$purple" 'https://github.com/ggreer/the_silver_searcher#installing' $reset
    echo "  and install from package manager"

fi
