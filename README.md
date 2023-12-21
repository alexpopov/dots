# My Dot Files

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

