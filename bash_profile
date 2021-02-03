# interactive shells.  However, in some circumstances, bash sources bashrc even
# in non-interactive shells (e.g., when using scp), so it is standard practice
# to check for interactivity at the top of .bashrc and return immediately if
# the shell is not interactive.  The following line does that; don't remove it!
#fi

# vi: ft=sh

#if [ -z "$PS1" ]; then
    #return
#fi

# Load CentOS stuff and Facebook stuff (don't remove these lines).
source /etc/bashrc
source /usr/facebook/ops/rc/master.bashrc

# Keep oodles of command history (see https://fburl.com/bashhistory).
HISTFILESIZE=-1
HISTSIZE=1000000
shopt -s histappend

# Set up personal aliases, functions, etc.  See https://fburl.com/bash.
alias notify='echo SEND_TERMINAL_NOTIFICATION'

PS1="\[\033[1;38m\]\]\[\$\] \[\033[0;38m\]"

export no_proxy=".fbcdn.net,.facebook.com,.thefacebook.com,.tfbnw.net,.fb.com,.fburl.com,.facebook.net,.sb.fbsbx.com,localhost"
export http_proxy=fwdproxy:8080
export https_proxy=fwdproxy:8080

PATH=$PATH:/home/alexpopov/.local/bin
PATH=$PATH:/home/alexpopov/local/my_clones/bin
export PATH
PATH=/home/alexpopov/bin:$PATH
PATH=$HOME/fbsource/xplat/third-party/yarn/:$PATH
export PATH
export NODE_PATH="/usr/local/lib/node_modules"

test -e "${HOME}/.iterm2_shell_integration.bash" && source "${HOME}/.iterm2_shell_integration.bash"


export CACHEDIR='/dev/shm/fbcode-vimcache'

# export PYENV_ROOT="/home/alexpopov/virtualenvs/"
# eval "$(pyenv global)"

alias vimdiff='/home/alexpopov/bin/vim -d'

# My Functions

UPM_PATH=~/fbsource/fbcode/upm
function jk_goto_upm() {
    echo "> cd $UPM_PATH";
    cd $UPM_PATH;
}

function jk_test_frontend() {
    local jk_PWD=$(pwd);
    cd $UPM_PATH;
    echo '> buck test //upm/frontend/tests:tests' $@
    buck test //upm/frontend/tests:tests $@;
    cd $jk_PWD;
    echo '> buck test //upm/frontend/tests:tests' $@
}

function jk_test_sql() {
    pushd $UPM_PATH
    case $1 in
        sql)
            target_name="sql_tests"
            ;;
        hql)
            target_name="hql_tests"
            ;;
        fluent)
            target_name="fluent_tests"
    esac
    shift
    buck test //upm/frontend/tests:$target_name "$@"
    popd
}

function jk_test_all() {
    local jk_PWD=$(pwd);
    cd $UPM_PATH;
    echo '> buck test //upm/tests/...'
    buck test //upm/frontend/...;
    echo '> buck test //upm/tests/...'
    cd $jk_PWD;
}

function jk_amend() {
    echo '> hg amend';
    hg amend;
}

function jk_pull_and_rebase() {
    echo '> hg pull && hg rebase -d remote/fbcode/warm';
    hg pull;
    hg rebase -d remote/fbcode/warm;
}

function jk_submit() {
    if [ -e "$1" ] && [ "$1" == 'true' ]
    then
        echo '> publishing...';
        echo '> jf submit -s';
        jf submit -s;
    else
        echo '> submitting but not publishing...';
        echo '> jf submit -s --no-publish';
        jf submit -s --no-publish;
    fi
}

function jk_source_profile() {
    echo '> sourcing bash_profile...';
    source ~/.bash_profile;
}

function jk_diff_stat() {
    local jk_PWD=$(pwd)
    cd $UPM_PATH;
    echo '> hg diff -r master --stat'
    hg diff -r master --stat
    cd $jk_PWD
}

function jk_warm() {
    local jk_PWD=$(pwd)
    cd $UPM_PATH;
    echo '> hg up remote/fbcode/warm'
    hg up remote/fbcode/warm
    cd $jk_PWD
}

function jk_diff_vim() {
    echo 'hg diff | vimdiff -R'
    hg diff $@ | vimdiff -R
}

function jk_rebase_diffs() {
    local warm="remote/fbcode/warm"
    for hash in $@
    do
        echo "  jk: rebasing $hash onto $warm"
        hg rebase -b $hash -d $warm
    done
}

function agr {
    ag -0 -l "$1" | AGR_FROM="$1" AGR_TO="$2" xargs -r0 perl -pi -e 's/$ENV{AGR_FROM}/$ENV{AGR_TO}/g';
}


#alias tmux="TERM=tmux-256color tmux"

PS1="\[\033[1;38m\]\]\[\$\] \[\033[0;38m\]"

# Add colors to `ls`
alias ls="ls -G --color=always"

# Set this to what editor you want to use if
# Bash needs to show you one
export EDITOR=/home/alexpopov/bin/vim

# Unbinds '\C-l'; usually it clears the screen. I find I do it by accident
# too often when I think I'm in vim
bind -r '\C-l'

[ -f ~/.fzf.bash ] && source ~/.fzf.bash

warm=fbcode/warm

