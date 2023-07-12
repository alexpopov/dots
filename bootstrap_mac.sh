WHOAMI="$0"

function run_main_bootstrap {
  local dir="$(dirname $WHOAMI)"
  local main_bootstrap="${dir}/bootstrap.sh"
  echo "Running main bootstrap script..."
  echo "${main_bootstrap}"
  . "$main_bootstrap"
}

function install_brew_stuff {
  local dir="$(dirname $WHOAMI)"
  pushd "$dir"
  brew bundle
  popd
}

source $HOME/.local/bin/scripts/color.sh


run_main_bootstrap

set -o xtrace

xcode-select --install

install_brew_stuff


echo 'To be continued...'

