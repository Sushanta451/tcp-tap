#!/usr/bin/env bash
# Two connections in a row through one proxy started without --once.
#
# tcptap-echo serves a single connection, so it is restarted between the two
# clients; the proxy is not, and its listener has to survive the first close.
# Every log line asserted on here is flushed with std::endl, which is what
# makes grepping a still-running proxy's log safe.
set -euo pipefail

bin_dir="${1:?binary directory}"
tap_port="${2:?proxy port}"
echo_port="${3:?upstream port}"

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
  cat "${work}"/*.log >&2
  exit 1
}

wait_for() {
  local tries=100
  until grep -q "$2" "$1" 2>/dev/null; do
    tries=$((tries - 1))
    [ "${tries}" -gt 0 ] || return 1
    sleep 0.1
  done
}

"${bin_dir}/tcptap" --listen "${tap_port}" --upstream "127.0.0.1:${echo_port}" \
  >"${work}/tap.log" 2>&1 &
tap_pid=$!
wait_for "${work}/tap.log" "listening on" || fail "proxy never came up"

for message in first-connection second-connection; do
  "${bin_dir}/tcptap-echo" "${echo_port}" >"${work}/echo.log" 2>&1 &
  echo_pid=$!
  wait_for "${work}/echo.log" "echo listening" || fail "upstream never came up"
  "${bin_dir}/tcptap-send" "${tap_port}" "${message}" >"${work}/send.log" 2>&1 \
    || fail "client exited non-zero on ${message}"
  wait "${echo_pid}" || fail "upstream exited non-zero on ${message}"
  grep -q "got ${#message} bytes \[${message}\]" "${work}/send.log" \
    || fail "${message} did not come back"
  wait_for "${work}/tap.log" "closed: ${#message} bytes upstream" \
    || fail "proxy never finished ${message}"
done

[ "$(grep -c '^closed:' "${work}/tap.log")" -eq 2 ] || fail "proxy did not serve both"
kill -0 "${tap_pid}" 2>/dev/null || fail "proxy exited after serving"

echo "PASS: one proxy relayed two connections back to back"
