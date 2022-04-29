
function jk_amend() {
    echo '> hg amend';
    hg amend;
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

function jk_diff_vim() {
    echo 'hg diff | vimdiff -R'
    hg diff $@ | vimdiff -R
}

function jk_flire() {
    echo "arc f && arc lint && pyre"
    arc f && arc lint && pyre
}

