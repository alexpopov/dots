#!/usr/bin/env bash
# this is not the best script in the world
# it is just a tribute

### set -e, trap and cleanup functions

function cleanup {
  # This function will be called because we pass it to 'trap' below
  #
  # Useful things you can do here:
  #   * rm any files you may have created
  #   * unmount devices
  #   * detach connections
  echo "Good bye"
}

# Exit immediately on error
set -e
# Cancel with set +e

# if any command in the script returns an error code, the cleanup function
# will be called
trap cleanup ERR
# Another useful trap is SIGINT which will trap on ctrl-C. You can list
# multiple signals in a trap call

echo "Everything working as expected!"

# disable trap set above
trap - ERR
