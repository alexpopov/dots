#!/usr/bin/env bash
# Meta work macbook specific configuration
# This file is only sourced when /opt/facebook/ exists

# Connect to devvm with yubikey tokens
# Usage: dev_connect <devvm-name|helheim|collosus|default> [token1] [token2]
# If tokens are not provided, you will be prompted to tap your yubikey
function dev_connect {
  local devvm_arg="$1"
  local token1="$2"
  local token2="$3"
  local devvm

  if [ -z "$devvm_arg" ]; then
    echo "Error: devvm name required"
    echo "Usage: dev_connect <devvm-name|helheim|collosus|default> [token1] [token2]"
    return 1
  fi

  # Map aliases to actual devvm addresses
  case "$devvm_arg" in
    helheim)
      devvm="devvm23176.cln0.facebook.com"
      ;;
    collosus|default)
      devvm="devvm36070.lla0.facebook.com"
      ;;
    *)
      devvm="$devvm_arg"
      ;;
  esac

  # If tokens not provided, prompt for them
  if [ -z "$token1" ] || [ -z "$token2" ]; then
    echo -n "Tap yubikey for first token and press Enter: "
    read -n 32 token1
    echo ""  # New line after read

    echo -n "Tap yubikey for second token and press Enter: "
    read -n 32 token2
    echo ""  # New line after read
  fi

  echo "Connecting to $devvm..."
  ek dev connect -n "$devvm" -y "$token1" && dev connect -n "$devvm" -y "$token2"
}
