#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
app_dir=${script_dir:h}
check_dir=$(mktemp -d /tmp/nestic-live-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library -swift-version 5 -module-cache-path "$check_dir/modules" \
  "$app_dir"/Nestic-iOS/AppCore/*.swift "$script_dir/LiveSyncCheck.swift" \
  -o "$check_dir/check"
"$check_dir/check"
