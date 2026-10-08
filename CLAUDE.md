# tcp-tap — Project Context for Claude Code

A fault-injecting TCP proxy written directly against the POSIX sockets API. It
accepts a downstream connection, dials an upstream, relays bytes between them,
logs every chunk with the direction it travelled — and can deliberately degrade
the link while doing it. No frameworks, no wrappers: the syscalls are the point.

This is the sequel to `connection-logger`. That project watched one end of a
connection from the inside. This one sits in the middle, which is where the
interesting problems live: two fds to multiplex instead of one, half-closes to
forward, partial writes to buffer, and backpressure to respect.

## Why this stack

Raw BSD sockets in C++20, built with CMake. Every abstraction that would hide
`bind`/`listen`/`accept`/`recv`/`send` is deliberately absent. Prefer the plain
syscall over a library that wraps it.

## Repo layout

| Path | What it is |
| --- | --- |
| `src/proxy/tap.cpp` | The proxy. Built as `tcptap`. |
| `src/testing/echo_server.cpp` | Test upstream: accepts one connection, echoes it back. Built as `tcptap-echo`. |
| `src/testing/send_client.cpp` | Test client: sends a message, half-closes, reads the reply. Built as `tcptap-send`. |
| `CMakeLists.txt` | Build + test definitions. Warning and sanitizer flags live in the `tcptap_flags` interface target. |
| `tests/smoke_test.sh` | End-to-end relay test: three real processes, two real sockets. |
| `tests/refused_test.sh` | Asserts a dead upstream is reported and exits non-zero. |
| `scripts/dev.sh` | The dev CLI. Every routine task goes through it. |
| `scripts/install_hooks.sh` | Points `core.hooksPath` at `.githooks/`. Run once per clone. |
| `.githooks/commit-msg` | Rejects any commit message containing AI attribution. |
| `ROADMAP.md` | **The work queue.** Thirty dated days, 1–5 commits each. |

## Build system

CMake ≥ 3.20, C++20, Ninja when available. Three binaries, one interface target
(`tcptap_flags`) carrying the warning and sanitizer policy — new targets link it
so flags never drift.

- `-Wall -Wextra -Wpedantic -Wshadow -Wconversion` everywhere.
- `-DTCPTAP_WERROR=ON` turns those into errors. CI builds with it on.
- `-DENABLE_ASAN=ON` adds AddressSanitizer + UBSan, into `build-asan/`.

### Quick start

```bash
./scripts/dev.sh build          # configure + build into build/
./scripts/dev.sh demo           # echo + proxy + client, end to end, one command
./scripts/dev.sh test           # the CTest suite
./scripts/dev.sh ci --strict    # everything CI runs, and fail if a tool is missing
```

Run `./scripts/dev.sh help` for the full list. Use the CLI rather than raw
`cmake`/`ctest` so local runs match CI.

## How to work this repo

The daily loop is driven entirely by `ROADMAP.md`.

1. Open `ROADMAP.md` and find the **lowest-numbered day that is not fully
   ticked**.
2. Work that day's bullets **in order**. Each bullet is exactly one commit.
   Do not squash a day into one commit, and do not run ahead into the next day.
3. Tick each bullet in the same commit as the code it describes.
4. `./scripts/dev.sh ci --strict` must be green **before every commit**. If it
   is red, fix it or revert — never commit a red tree.
5. A day is 100–200 net changed lines. If a bullet turns out larger than its
   estimate, ship the coherent part and leave a new unchecked bullet for the
   rest. Do not blow the budget to finish something.

## Critical rules

### Commits
- **Never add AI attribution of any kind.** No `Co-Authored-By: Claude`, no
  "Generated with Claude Code", no 🤖. Not once, not ever. The `commit-msg`
  hook rejects it, `.claude/settings.json` disables it, and this line exists so
  there is no ambiguity about intent.
- Imperative subject, ≤ 72 characters: "handle partial sends in the relay", not
  "handled partial sends" or "updates".
- Body explains *why* when the diff doesn't already say it. Wrap at 72.
- One logical change per commit, matching one roadmap bullet.
- Don't run `scripts/install_hooks.sh` expecting it to be a no-op — it rewrites
  `core.hooksPath`. It is safe, but it is the owner's to run.

### Syscalls
- **Check every return value.** `socket`, `setsockopt`, `bind`, `listen`,
  `accept`, `connect`, `recv`, `send`, `shutdown`, `close`, `inet_pton`,
  `getaddrinfo`, `poll` — all of them. On failure, print to `stderr` with
  `std::strerror(errno)` and return non-zero.
- `getaddrinfo` reports errors through `gai_strerror`, **not** `errno`.
- **Close every descriptor on every path**, including error paths. A `return 1`
  between `socket()` and `close()` is a descriptor leak. `dial()` closes each
  candidate it rejects — keep that pattern when you touch it.

### recv / send
- `recv` has three outcomes and all three must be handled: `-1` is an error
  (retry on `EINTR`, bail otherwise), `0` means the peer closed its half, `> 0`
  is a byte count. Once sockets go non-blocking, `EAGAIN`/`EWOULDBLOCK` becomes
  a fourth case and is **not** an error.
- A `recv` buffer is **not** a string. It is not NUL-terminated and may contain
  any byte. Print it through `std::string_view(buf, n)`, never `std::cout << buf`.
- Always bound the read by `sizeof(buf)`.
- `send` may transmit fewer bytes than asked. Everything goes out through the
  `send_all` loop, or you explain in a comment why a partial send is impossible.

### Half-close
- A proxy must forward an EOF, not treat it as teardown. When one side stops
  writing, `shutdown(other, SHUT_WR)` and keep relaying the other direction
  until it closes too. `ENOTCONN` from that `shutdown` is benign — the peer got
  there first.

### Addresses and byte order
- `htons`/`htonl` going out, `ntohs`/`ntohl` coming in. A missing conversion is
  a bug even when it happens to work on this machine.
- `reinterpret_cast<sockaddr*>(&addr)` is the expected cast for
  `bind`/`connect`/`accept`. It is not a smell here.
- `inet_ntop` for printing, `inet_pton` for parsing. Never `inet_addr`.
- `sizeof(...)` into a `socklen_t` parameter needs an explicit
  `static_cast<socklen_t>` — `-Wconversion` is on and brace init will not let
  the narrowing through silently.

### C++ style
- C++20. Brace initialization (`int fd{socket(...)}`) — it is the style in the
  tree and it catches narrowing.
- Errors to `stderr`, normal output to `stdout`.
- `std::cout` is block-buffered when redirected, so anything a long-running
  process prints may sit in the buffer. The tests grep the `listening` lines of
  live processes, so **those lines must stay `std::endl`**. Read the header
  comment in `tests/smoke_test.sh` before changing how any of this logs.
- Keep the code readable over clever. A comment explaining *why* a syscall is
  called the way it is earns its place.

### Security
- Never commit secrets, API keys, or credentials.
- Never trust a length that came off the wire without bounding it against the
  buffer. This matters most in the TLS and HTTP parsing on the roadmap: a
  ClientHello is attacker-controlled input.
- Bind to loopback by default. `--listen-host` is the only way to bind wider,
  and it warns when the address is not loopback.

### Portability
- Developed on macOS, built on Linux in CI, and the socket APIs differ.
  `SO_NOSIGPIPE` is BSD/macOS only; Linux suppresses SIGPIPE with `MSG_NOSIGNAL`
  on each `send` instead. The `kSendFlags` / `suppress_sigpipe` pair in every
  source file shows the pattern — guard platform options with `#ifdef` and
  provide the other platform's equivalent. A macOS-only symbol fails the build.

## Testing

The suite runs the real binaries against each other over real sockets. Each
test owns its own pair of ports so `ctest -j` is safe — **keep it that way**; a
hardcoded shared port means tests that cannot run concurrently.

New behaviour needs a test unless there is a reason it can't have one; say so in
the commit when there is. A new program goes in `src/` and gets its own
`add_executable` linking `tcptap_flags`.

## CI

`.github/workflows/ci.yml` runs on every push and PR:

- `build (gcc)` / `build (clang)` — configure, build with `-Werror`, run CTest
- `tests (ASan + UBSan)` — the same suite under sanitizers
- `clang-format` — formatting check
- `shellcheck` — `scripts/*.sh` and `tests/*.sh`

Every one of those is also run by `./scripts/dev.sh ci --strict`, deliberately:
the local gate is a superset of CI, so nothing can land that the pre-commit
check was unable to see. There is **no clang-tidy job yet** — adding it is a
Day 29 roadmap item, because it needs Homebrew's `llvm` on the dev machine and
a check CI runs but the local gate can't is worse than no check at all.
