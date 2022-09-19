#!/usr/bin/env /bin/bash

A_RESIZE="resize"
A_ATTACH="attach"
ACTION=$(gum choose $A_RESIZE $A_ATTACH)

function do_resize {
    SIZE=$(gum choose '=' 4 3 2 1)
    case $SIZE in


        *)
            echo "ERROR: unknown option"
            ;;
    esac

}

function do_attach {
    SESSION=$(tmux list-sessions -F \#S | gum filter --placeholder "Pick session...")
    tmux switch-client -t $SESSION || tmux attach -t $SESSION
}

case $ACTION in
    $A_RESIZE)
        do_resize
        ;;
    $A_ATTACH)
        do_attach
        ;;
    *)
        echo "ERROR: unknown option"
        ;;


esac


