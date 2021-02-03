#!/bin/bash

# This is a bootstrap script for getting set up on new devices. 

# debug house keeping
set -e  # exit on errors
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

# important dirs
bootstrap_dir=$HOME/bootstrap
dots_dir=$bootstrap_dir/dots
home_bin=$HOME/local/bin
config_dir=$HOME/.config
nvim_dir=$config_dir/nvim
nvim_colors=$nvim_dir/colors
tmux_dir=$HOME/.tmux

# Create the directory structures we need ahead of time
mkdir -p $bootstrap_dir $dots_dir $home_bin $config_dir $nvim_dir $nvim_colors $tmux_dir

# important dot files
my_bash_profile=$HOME/.my_bash_profile
nvim_init=$nvim_dir/init.vim
tmux_conf=$HOME/.tmux.conf
input_rc=$HOME/.inputrc

mkdir -p $bootstrap_dir
mkdir -p $home_bin

unameOut="$(uname -s)"
case "${unameOut}" in
	Linux*)     machine=Linux;;
	Darwin*)    machine=Mac;;
	*)          machine="UNKNOWN:${unameOut}"
esac


echo "successfully aliased $pkg_install"

if ! command -v apt-get
then
	echo "error; apt-get is not valid on this system."
	echo "please specify how to get packages and retry"
	exit 1
fi

#
#
# Begin Script!
#
#
function pkg_install () {
	# choose which package manager to use
	sudo apt-get install $@
}

function maybe_install() {
	if ! command -v $1
	then
		echo "installing $1"
		pkg_install $1
	fi
}

# Install the basics
maybe_install git
maybe_install mosh
maybe_install tmux

# Clone the dots dir if we don't have it
if [[ $(ls -A $dots_dir) = "" ]]
then
	echo "cloning dots repo into $dots_dir"
	git clone git@github.com:alexpopov/dots.git $dots_dir
fi

# Symlink the files we need:
ln -sf $dots_dir/bash_profile $my_bash_profile
ln -sf $dots_dir/init.vim $nvim_init
ln -sf $dots_dir/tmux.conf $tmux_conf
ln -sf $dots_dir/tmux/plugins $tmux_dir/plugins
ln -sf $dots_dir/inputrc $input_rc

# Append and source my bash profile
echo "source $my_bash_profile" >> $HOME/.bashrc
source $my_bash_profile

#

# Figure out what to do with nvim... 
# app images won't work on raspberry pi due to architecture and they won't work on Macs

# Manually install latest nvim
if [[ $machine = "Mac" ]]
then
	echo "You must handle installing nvim yourself. Try to get a nightly version if possible!"
else
	# we're assuming we're on linux now and can use app-images
	wget -P $bootstrap_dir https://github.com/neovim/neovim/releases/download/nightly/nvim.appimage 
	chmod u+x $bootstrap_dir/nvim.appimage
	# make the links
	ln -sf $bootstrap_dir/nvim.appimage $home_bin/vim
	ln -sf $bootstrap_dir/xcode.vim $nvim_colors/xcode.vim
fi



# Install Plug
if [[ ! -f $nvim_dir/site/autoload/plug.vim ]]
then
	curl -fLo "$nvim_dir/site/autoload/plug.vim" --create-dirs 'https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
fi

nvim --headless +PlugInstall +qa
