USAGE="Usage: alert.sh simple title"

if [ "$#" == "0" ]; then
	echo "$USAGE"
	exit 1
fi

case $1 in
  'simple')
    shift
    title="${1// /%20}"
    open -g "hammerspoon://hsAlert?text=$title"
    ;;

  'debug')
    open -g "hammerspoon://hsAlertDebug"
    ;;
  *)
    open -g "hammerspoon://hsAlert?text=alert:%20unhandled%20argument:%20$1"
    ;;

esac
