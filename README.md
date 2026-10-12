# My Dot Files

## Brand new Mac

One command, on a machine with nothing on it -- no git, no Homebrew, no repo:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/alexpopov/dots/master/scripts/new_mac_from_scratch.sh)"
```

That installs the Xcode Command Line Tools (and *waits* for the GUI installer,
which `xcode-select --install` does not do), installs Homebrew and puts it on
PATH, clones this repo with submodules, then hands over to
`new_mac_bootstrap.sh` -> `bootstrap.sh` -> `brew bundle`.

It clones over HTTPS unless a working GitHub SSH key is already present, since
a new Mac has no key enrolled yet. To switch afterwards:

```
git -C ~/dots remote set-url origin git@github.com:alexpopov/dots.git
```

Run it in an interactive terminal: there are sudo and GUI prompts.

If you already have git and the repo, skip straight to `bash ~/dots/new_mac_bootstrap.sh`.

## Cloning manually

When cloning, don't forget to get submodules so that tpm works:

```
git clone --recursive
```

If you forgot to do that:
```
git submodule update --init --recursive
```

## Symlinks

Read the `bootstrap.sh` file or run it.


## Bash

Create your own `.bash_profile` and fill in the variables with what you want

If you have top-secret scripts in all the right places, make sure to set the environment variable
`ENABLE_PRIVATE_FACEBOOK=1`

There is an `example_bash_profile.sh` that you can copy

```
MAIN_BASH_PROFILE="$HOME/.config/bash/bash_profile.sh"
HG_SUPPORT="$HOME/.config/bash/hg_support.sh"
OTHER_SCRIPT="$HOME/.config/bash/private/other_support.sh"

SANITY_CHECK="$HOME/.config/bash/sanity_check.sh"

for file in $MAIN_BASH_PROFILE $HG_SUPPORT $OTHER_SCRIPT
do
    if [ -e "$file" ]; then
        . $file
    else
        echo "WARNING: Could not source $file; file does not exist"
    fi
done

. $SANITY_CHECK
```

## Tmux

