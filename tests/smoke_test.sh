#!/usr/bin/env bash
# End-to-end: tcptap-send -> tcptap -> tcptap-echo -> tcptap -> tcptap-send.
#
# Three real processes and two real TCP connections. The proxy is the thing under
# test; the echo server and the client are fixtures.
#
# On buffering: a redirected stdout is block-buffered, so a line a live process
# has "printed" may still be sitting in its buffer. Two things follow. The
# startup handshake below greps for the "listening" lines, which the programs
# flush explicitly for this purpose. Everything else is asserted only after the
# writing process has exited and its buffer has been drained.
#
# The byte-for-byte chunk assertions assume the message arrives in one recv.
# That holds for a short payload on loopback; keep test messages well under the
# 64-byte preview limit so the proxy logs them whole.
set -euo pipefail

bin_dir="${1:?binary directory}"
tap_port="${2:?proxy port}"
echo_port="${3:?upstream port}"
message="${4:?message to relay}"

work="$(mktemp -d)"
echo_pid=""
tap_pid=""

cleanup() {
  [ -n "${tap_pid}" ] && kill "${tap_pid}" 2>/dev/null
  [ -n "${echo_pid}" ] && kill "${echo_pid}" 2>/dev/null
  rm -rf "${work}"
  return 0
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  for log in echo tap send; do
    if [ -f "${work}/${log}.log" ]; then
      echo "--- ${log} ---" >&2
      cat "${work}/${log}.log" >&2
    fi
  done
  exit 1
}

# Wait for a flushed startup line instead of probing the port. A probe
# connection would be swallowed by the single accept() these programs make.
wait_for() {
  local file="$1" pattern="$2" tries=100
  while [ "${tries}" -gt 0 ]; do
    if [ -f "${file}" ] && grep -q "${pattern}" "${file}" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
    tries=$((tries - 1))
  done
  return 1
}

"${bin_dir}/tcptap-echo" "${echo_port}" >"${work}/echo.log" 2>&1 &
echo_pid=$!
wait_for "${work}/echo.log" "echo listening" || fail "upstream never came up"

"${bin_dir}/tcptap" --listen "${tap_port}" --upstream "127.0.0.1:${echo_port}" --once \
  >"${work}/tap.log" 2>&1 &
tap_pid=$!
wait_for "${work}/tap.log" "listening on" || fail "proxy never came up"

"${bin_dir}/tcptap-send" "${tap_port}" "${message}" >"${work}/send.log" 2>&1 \
  || fail "client exited non-zero"

wait "${tap_pid}" || fail "proxy exited non-zero"
tap_pid=""
wait "${echo_pid}" || fail "upstream exited non-zero"
echo_pid=""

size="${#message}"

grep -q "got ${size} bytes \[${message}\]" "${work}/send.log" \
  || fail "client did not get its bytes back"
grep -q "c>u ${size} bytes \[${message}\]" "${work}/tap.log" \
  || fail "proxy did not log the downstream-to-upstream chunk"
grep -q "u>c ${size} bytes \[${message}\]" "${work}/tap.log" \
  || fail "proxy did not log the upstream-to-downstream chunk"
grep -q "c>u eof" "${work}/tap.log" \
  || fail "proxy did not forward the client's half-close"
grep -q "closed: ${size} bytes upstream, ${size} bytes downstream" "${work}/tap.log" \
  || fail "proxy byte counters disagree with what was sent"

echo "PASS: relayed ${size} bytes each way through 127.0.0.1:${tap_port}"
