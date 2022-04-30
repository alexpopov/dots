source ~/.config/bash/color.sh

if [ -z ${NVIM_PYTHON+x} ]
then
    echo -e "${red}ERROR:$reset" '$NVIM_PYTHON not set. This will break neovim'
    echo '  Suggestion: create a virtual environment just for neovim with the following commands:'
    echo -e $purple
    echo '  mkdir -p $HOME/.local/virtualenvs/'
    echo '  pushd $!  # Enter directory above'
    echo '  python3 -m venv nvim'
    echo -e $reset
fi


