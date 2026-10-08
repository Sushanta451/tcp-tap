#!/usr/bin/env bash
# The proxy must fail loudly when the upstream is not listening.
#
# A proxy that accepts a downstream connection and then silently exits 0 because
# it could not reach the upstream is worse than useless: the client sees a clean
# close and cannot tell a healthy empty response from a broken link.
set -euo pipefail

bin_dir="${1:?binary directory}"
tap_port="${2:?proxy port}"
dead_port="${3:?a port nothing is listening on}"

work="$(mktemp -d)"
tap_pid=""

cleanup() {
  [ -n "${tap_pid}" ] && kill "${tap_pid}" 2>/dev/null
  rm -rf "${work}"
  return 0
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  [ -f "${work}/tap.log" ] && cat "${work}/tap.log" >&2
  exit 1
}

"${bin_dir}/tcptap" --listen "${tap_port}" --upstream "127.0.0.1:${dead_port}" \
  >"${work}/tap.log" 2>&1 &
tap_pid=$!

tries=100
while [ "${tries}" -gt 0 ]; do
  grep -q "listening on" "${work}/tap.log" 2>/dev/null && break
  sleep 0.1
  tries=$((tries - 1))
done
[ "${tries}" -gt 0 ] || fail "proxy never came up"

# The client will not get a reply; it only exists to trigger the accept() that
# makes the proxy try, and fail, to reach the upstream.
"${bin_dir}/tcptap-send" "${tap_port}" "never-arrives" >"${work}/send.log" 2>&1 || true

status=0
wait "${tap_pid}" || status=$?
tap_pid=""

[ "${status}" -ne 0 ] || fail "proxy exited 0 even though the upstream was dead"
grep -qi "connect" "${work}/tap.log" || fail "proxy did not report the failed connect"

echo "PASS: dead upstream reported, proxy exited ${status}"
