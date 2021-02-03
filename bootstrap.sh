#!/bin/bash

# This is a bootstrap script for getting set up on new devices. 

# debug house keeping
set -e  # exit on errors
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

bootstrap_dir=$HOME/bootstrap

mkdir -p $bootstrap_dir
cd $bootstrap_dir

function install_lua() {
	echo 'lua not found. Downloading and installing lua'
	curl -R -O http://www.lua.org/ftp/lua-5.4.2.tar.gz 
	tar zxf lua-5.4.2.tar.gz
	cd lua-5.4.2
	sudo make install
}

# Step 0: Do we have git? It's a pre-req
if ! command -v git &> /dev/null
then
	echo "no git; please manually install git"
	set +e
	trap - DEBUG
	trap - EXIT
	exit 1
fi

# Step 1: Get Lua
if ! command -v lua &> /dev/null
then
	echo "no lua at all"
	install_lua
fi

lua_v=$(lua -e "print(_VERSION)")  

if ! [[ $lua_v = "Lua 5.4" ]]
then
	echo "wrong lua version"
	install_lua
fi

cd $bootstrap_dir
echo ''
echo 'lua okay'
echo ''

if ! lua -e 'require("socket")' &> /dev/null
then
	echo 'lua rocks not found. Downloading and installing lua rock'
	wget https://luarocks.org/releases/luarocks-3.5.0.tar.gz
	tar zxpf luarocks-3.5.0.tar.gz
	cd luarocks-3.5.0
	./configure --with-lua-include=/usr/local/include/ --with-lua-version=5.4
	make 
	sudo make install
	cd $HOME
	luarocks install luasocket --local
	lua -e 'require("socket")'

fi

cd $bootstrap_dir
echo ''
echo 'lua rocks okay'
echo ''

if ! lua -e 'require("sh")' &> /dev/null
then
	echo 'missing luas sh package. Installing'
	luarocks install --server=http://luarocks.org/dev luash --local
	lua -e 'require("sh")'
fi

cd $bootstrap_dir
echo ''
echo 'luash installed'
echo ''

unset -f install_lua


