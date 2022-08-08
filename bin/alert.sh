USAGE="Usage: alert.sh simple title"

if [ "$#" == "0" ]; then
	echo "$USAGE"
	exit 1
fi

function simple {
  hs -c
}

case $1 in
  'simple')
    shift
    title=$1
    hs -c "hs.alert.show(\"$title\")" > /dev/null
    ;;

  *)
    hs -c 'hs.alert.show("unhandled argument: $1")'
    ;;

esac

