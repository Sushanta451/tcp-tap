# tcp-tap

A fault-injecting TCP proxy built straight on the POSIX sockets API. It sits
between a client and a server, relays bytes in both directions, logs every
chunk it carries — and is being taught to degrade the link on purpose, so the
programs on either end can be tested against a network that misbehaves.

`connection-logger` watched one end of a connection from the inside. This sits
in the middle, which is where the harder problems are: two descriptors to
multiplex, half-closes to forward, partial writes to buffer, backpressure to
respect. No frameworks — the syscalls are the point.

```
$ ./scripts/dev.sh demo
--- upstream ---
echo listening on 127.0.0.1:9101
--- proxy ---
listening on 127.0.0.1:9100, upstream 127.0.0.1:9101
--- client ---
sent 21 bytes [hello-through-the-tap]
accepted 127.0.0.1:57137
c>u 21 bytes [hello-through-the-tap]
c>u eof
echo 21 bytes hello-through-the-tap
echo saw eof
u>c 21 bytes [hello-through-the-tap]
u>c eof
closed: 21 bytes upstream, 21 bytes downstream
got 21 bytes [hello-through-the-tap]
```

`c>u` is downstream-to-upstream, `u>c` the other way.

## Getting started

```bash
brew install cmake ninja clang-format shellcheck   # apt: cmake ninja-build clang-format shellcheck
./scripts/install_hooks.sh                         # once per clone
./scripts/dev.sh build
./scripts/dev.sh demo
```

Or drive the three processes yourself, in three terminals:

```bash
./scripts/dev.sh echo 9101                          # the upstream
./scripts/dev.sh tap --listen 9100 --upstream 127.0.0.1:9101
./scripts/dev.sh send 9100 "hello-through-the-tap"  # the client
```

Anything that speaks TCP works as the upstream — point it at a real server and
watch the conversation:

```bash
./scripts/dev.sh tap --listen 8080 --upstream example.com:80
```

## The dev CLI

Everything routine goes through `./scripts/dev.sh`:

| Command | What it does |
| --- | --- |
| `build [--release\|--asan\|--werror]` | Configure + build |
| `tap [args...]` | Run the proxy (default `9100` → `127.0.0.1:9101`) |
| `echo [port]` | Run the echo upstream (default `9101`) |
| `send [port] [msg]` | Run the client (default `9100`) |
| `demo` | Upstream + proxy + client, end to end, in one command |
| `test` | Build, then run the CTest suite |
| `lint` | clang-tidy over every source file |
| `fmt [--check]` | clang-format |
| `ci [--strict]` | Everything CI runs, locally. `--strict` fails on a missing tool |
| `branch <name>` | Start `feature/<name>` off `main` |
| `pr` | Push the branch and open a PR against `main` |
| `clean` | Remove `build/` and `build-asan/` |

## Repo layout

```
src/proxy/
  tap.cpp              the proxy — select() relay, chunk logging, half-close forwarding
src/testing/
  echo_server.cpp      test upstream: accepts one connection, echoes it back
  send_client.cpp      test client: sends, half-closes, reads the reply
CMakeLists.txt         build + test definitions
tests/
  smoke_test.sh        end-to-end relay over real sockets
  refused_test.sh      a dead upstream must be reported, not silently tolerated
scripts/
  dev.sh               the dev CLI
  install_hooks.sh     points core.hooksPath at .githooks/
.githooks/commit-msg   rejects commit messages carrying AI attribution
ROADMAP.md             the work queue — thirty dated days
CLAUDE.md              project rules
```

## Status

v1 is working: one connection at a time, relayed with `select()`, every chunk
logged with its direction, half-closes forwarded so each direction can drain
independently, and a dead upstream reported rather than silently tolerated.
Three end-to-end tests cover the relay, a longer payload, and a refused
upstream.

Where it goes next — a real event loop, then the fault injection that is the
point of the whole thing — is laid out day by day in [ROADMAP.md](ROADMAP.md).

## Tests

```bash
./scripts/dev.sh test            # CTest suite
./scripts/dev.sh test --asan     # same suite under ASan + UBSan
./scripts/dev.sh ci --strict     # everything CI runs, nothing skipped
```

The tests run the real binaries against each other over real sockets — three
processes, two TCP connections, no mocks. The only way to find out whether a
proxy relays bytes is to relay bytes.
