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
    hs -c "hs.alert.show(\"$title\", {textSize = 24, radius = 20, fillColor = { white = 0, alpha = 0.5}})" > /dev/null
    ;;

  'debug')
    shift
    title="$(hs -c 'hs.application.frontmostApplication():name()')"
    hs -c "hs.alert.show(\"$title\", {textSize = 24, radius = 20, fillColor = { white = 0, alpha = 0.5}})" > /dev/null
    ;;
  *)
    hs -c 'hs.alert.show("alert: unhandled argument: $1")'
    ;;

esac

