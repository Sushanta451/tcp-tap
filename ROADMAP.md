# 30-day roadmap

One entry per day. Each day is **100–200 net changed lines** across `src/` and
`tests/`, split into the **1–5 commits** listed under it. Every bullet is one
commit, sized so it stands on its own and passes
`./scripts/dev.sh ci --strict` by itself.

**How to work a day.**

1. Take the lowest-numbered day that is not fully ticked.
2. Do its commits in the order listed. One commit per bullet — do not squash
   the day into a single commit, and do not run ahead into the next day.
3. Tick each bullet in the same commit as the code it describes.
4. `./scripts/dev.sh ci --strict` must be green before every commit.
5. If a bullet turns out bigger than its estimate, ship the coherent part and
   leave a new unchecked bullet behind for the remainder. Do not blow the day's
   line budget to finish something.

Estimates are net changed lines, excluding this file.

---

## Week 1 — from one connection to a real event loop

v1 accepts exactly one connection and exits. This week is about the shape of
the loop, which is the actual step up from `connection-logger`.

### Day 1 — serve connections back to back
- [ ] `--once` flag that keeps today's exit-after-one-connection behaviour, so
      the existing tests still have a proxy that terminates on its own — ~30 lines
- [ ] without `--once`, accept in a loop and serve connections sequentially to
      completion; the listener stays open across connections — ~40 lines
- [ ] test: two connections in a row both relay, against one proxy — ~50 lines

### Day 2 — a child per connection
- [ ] `fork()` after `accept()`; the child relays and `_exit`s, the parent
      closes its copy of the connection fd and goes back to accepting — ~50 lines
- [ ] a `SIGCHLD` handler that reaps with `waitpid(WNOHANG)` in a loop, so
      finished children never linger as zombies — ~35 lines
- [ ] test: two *concurrent* connections relay independently without
      interleaving each other's bytes — ~55 lines

### Day 3 — poll() instead of select()
- [ ] rewrite the relay loop over `poll()`; no rebuilding an `fd_set` every
      iteration and no `FD_SETSIZE` ceiling — ~55 lines
- [ ] record in `CLAUDE.md` why `poll()` is the floor and `select()` is gone — ~25 lines
- [ ] test: relay a payload larger than the 4 KiB buffer, so the loop has to
      iterate and reassembly is actually exercised — ~45 lines

### Day 4 — non-blocking sockets
- [ ] set `O_NONBLOCK` on both the downstream and upstream fds — ~30 lines
- [ ] handle `EAGAIN`/`EWOULDBLOCK` from `recv` as "nothing right now", which
      is distinct from both an error and an EOF — ~45 lines
- [ ] handle a `send` that accepts only part of the buffer by holding the
      remainder instead of spinning on it — ~60 lines

### Day 5 — backpressure
- [ ] a per-direction pending-write buffer, flushed when `poll()` reports the
      far side writable — ~75 lines
- [ ] stop polling a side for readability while its peer's write buffer is over
      the high-water mark, so a slow reader slows the sender instead of
      ballooning memory — ~45 lines
- [ ] test: a deliberately slow reader receives every byte, in order — ~55 lines

### Day 6 — event-loop shim, kqueue backend
- [ ] an event-loop shim header with a tiny interface (`add`, `modify`, `wait`)
      and `poll()` behind it as the portable default — ~60 lines
- [ ] a `kqueue` backend selected by `#ifdef` on macOS/BSD — ~70 lines

### Day 7 — epoll backend, and build it on both platforms
- [ ] an `epoll` backend selected by `#ifdef` on Linux — ~70 lines
- [ ] a macOS job in CI, so the BSD paths get compiled on the platform they
      were written for instead of only on Linux — ~30 lines
- [ ] document the three backends and how one is chosen in `CLAUDE.md` — ~30 lines

## Week 2 — fault injection

The point of the project. A proxy that only mirrors is a mirror. A proxy that
can degrade the link on purpose is a test instrument.

### Day 8 — reproducible randomness
- [ ] `--seed N` feeding a single `std::mt19937` owned by the relay; log the
      seed in use on every run, including the default — ~55 lines
- [ ] `--direction c>u|u>c|both` parsed and stored, defaulting to `both`; no
      fault consumes it yet, but every fault added below will — ~55 lines

### Day 9 — delay and jitter
- [ ] `--delay MS`: hold each chunk for a fixed interval before relaying it,
      respecting `--direction` — ~60 lines
- [ ] `--jitter MS`: randomise each delay within ±MS off the seeded RNG — ~35 lines
- [ ] test: timed relay proves `--delay 300` really takes ≥300 ms — ~45 lines

### Day 10 — forced partial writes
- [ ] `--chunk N`: split every relayed write into N-byte pieces, so the peer is
      forced to handle partial reads — ~50 lines
- [ ] test: `--chunk 4` makes the upstream log four-byte reads — ~45 lines
- [ ] log the split in the relay output so a `--chunk` run is legible — ~25 lines

### Day 11 — bandwidth throttling
- [ ] a token-bucket rate limiter, per direction, refilled off a monotonic
      clock — ~85 lines
- [ ] `--rate BYTES_PER_SEC` wired to the bucket, with the accounting shown in
      the end-of-connection summary — ~40 lines
- [ ] test: 8 KiB at `--rate 4096` takes about two seconds — ~45 lines

### Day 12 — abrupt teardown
- [ ] `--drop-after BYTES`: relay N bytes, then close the connection mid-stream — ~45 lines
- [ ] `--rst`: tear down with `SO_LINGER` set to zero so the peer receives a
      RST rather than an orderly FIN — ~50 lines
- [ ] test: `--rst` surfaces as `ECONNRESET` at the client — ~50 lines

### Day 13 — corruption
- [ ] `--corrupt PROB`: flip one random bit in a relayed chunk with the given
      probability, off the seeded RNG — ~55 lines
- [ ] log every corruption with the byte offset and the before/after values, so
      a failing run downstream can be traced back to it — ~35 lines
- [ ] test: a fixed seed plus `--corrupt 1.0` corrupts deterministically — ~45 lines

### Day 14 — compose the faults
- [ ] apply the faults in a defined, documented order (rate → delay → chunk →
      corrupt → drop) rather than wherever each landed in the loop — ~70 lines
- [ ] `--profile flaky|slow|lossy` as named bundles of the flags above — ~50 lines
- [ ] test: a profile behaves the same as the flags it expands to — ~40 lines

## Week 3 — observability and addressing

### Day 15 — legible logs
- [ ] timestamp every log line from a monotonic clock, as ms since start — ~40 lines
- [ ] `--quiet` (connection open/close only) and `--verbose` (every syscall
      outcome) log levels — ~45 lines
- [ ] `--log FILE` to send the relay log somewhere other than stdout — ~35 lines

### Day 16 — hexdump
- [ ] `--hexdump`: canonical offset / hex / ASCII dump of each chunk — ~70 lines
- [ ] collapse runs of identical lines to `*`, the way `hexdump -C` does — ~35 lines
- [ ] test: a known payload produces a known dump — ~40 lines

### Day 17 — accounting
- [ ] end-of-connection summary: elapsed time, bytes and throughput each way,
      plus a count of every fault that fired — ~60 lines
- [ ] a process-wide total printed on `SIGINT`, so a long multi-connection run
      reports before it exits — ~55 lines
- [ ] test: the summary's byte counts match what was actually sent — ~40 lines

### Day 18 — IPv6
- [ ] parse the bracketed `[::1]:port` upstream form, keeping the bare
      `host:port` path working — ~55 lines
- [ ] bind `AF_INET6` when the listen address is v6, with `IPV6_V6ONLY` set
      explicitly instead of inherited from the system default — ~60 lines
- [ ] test: relay end to end over `[::1]` — ~45 lines

### Day 19 — binding beyond loopback
- [ ] `--listen-host ADDR`, still defaulting to loopback — ~40 lines
- [ ] print a loud warning when the bind address is not a loopback address,
      because that is the moment this tool becomes reachable from the network — ~30 lines
- [ ] `--help` rewritten with a synopsis, every flag, and worked examples — ~55 lines

### Day 20 — HTTP awareness
- [ ] peek the first downstream chunk for an HTTP request line and log the
      method, path and version without consuming the bytes — ~65 lines
- [ ] log the upstream's status line the same way — ~40 lines
- [ ] test: an HTTP-shaped payload is recognised, and a binary one is not
      misreported as HTTP — ~45 lines

### Day 21 — harden the test suite
- [ ] a shared bash helper the test scripts source, instead of three copies of
      the same wait-for-line and cleanup code — ~70 lines
- [ ] run the whole suite under ASan with the faults enabled, which is where a
      buffer bug in the write-buffer code would actually show up — ~40 lines
- [ ] a test for the `--once` / loop boundary: the proxy exits when told to and
      keeps serving when not — ~45 lines

## Week 4 — protocol routing, capture, release

### Day 22 — TLS record layer
- [ ] parse the TLS record header and the handshake header far enough to
      recognise a ClientHello, bounding every length against the buffer — ~75 lines
- [ ] log the TLS version and handshake type; leave non-TLS traffic untouched — ~40 lines

### Day 23 — SNI
- [ ] walk the ClientHello extensions to the `server_name` extension and log
      the SNI hostname — ~85 lines
- [ ] test: a captured ClientHello yields the expected hostname, and a
      truncated one is rejected rather than read past the end — ~50 lines

### Day 24 — route by name
- [ ] `--map NAME=host:port`, repeatable, building a routing table — ~60 lines
- [ ] `--upstream-from-sni`: pick the upstream from the SNI name, falling back
      to `--upstream` when there is no match — ~55 lines
- [ ] test: two names route to two different upstreams — ~50 lines

### Day 25 — configuration file
- [ ] a `key = value` config parser, with comments and unknown-key errors — ~75 lines
- [ ] `--config FILE`, with command-line flags overriding the file — ~50 lines
- [ ] test: a config file and the equivalent flags behave identically — ~45 lines

### Day 26 — pcap writer, part 1
- [ ] write a pcap global header and per-packet records for the relayed
      payloads, with `--pcap FILE` to turn it on — ~80 lines
- [ ] test: the output's magic number and header fields are what libpcap
      expects — ~45 lines

### Day 27 — pcap writer, part 2
- [ ] synthesise plausible Ethernet/IP/TCP framing around each payload, with
      sequence numbers that advance, so the capture opens cleanly in Wireshark — ~110 lines
- [ ] test: a relayed message is recoverable from the pcap payload bytes — ~50 lines

### Day 28 — many listeners
- [ ] `--map-port LOCAL:host:port`, repeatable, so one process can proxy
      several ports at once — ~85 lines
- [ ] fold every listener into the single event loop rather than one loop each — ~55 lines
- [ ] test: two mapped ports relay to two upstreams concurrently — ~50 lines

### Day 29 — tighten the tooling
- [ ] install Homebrew `llvm`, then add `clang-tidy` to both
      `dev.sh ci --strict` and CI as a required check — ~40 lines
- [ ] fix whatever clang-tidy finds on its first real run — ~60 lines
- [ ] `README.md` rewritten around what the tool does now, not what v1 did — ~45 lines

### Day 30 — v1.0
- [ ] a `CHANGELOG.md` covering the thirty days, grouped by milestone — ~50 lines
- [ ] a worked walkthrough in the README: proxy a real HTTP request, throttle
      it, corrupt it, capture it — ~60 lines
- [ ] final pass over `CLAUDE.md` so it describes the finished architecture,
      then tag `v1.0.0` — ~40 lines

---

## Beyond day 30

Parked, unsized, no commitment:

- UDP relay with its own loss and reorder faults
- a curses status view of live connections
- SOCKS5 and HTTP `CONNECT` front ends
- deterministic replay of a recorded session
- a fuzzing harness that drives the parsers off the pcap corpus

---

## Done

- [x] **v1** — single connection, `select()` relay, per-chunk logging with
      direction, half-close forwarding, dead-upstream diagnosis, and three
      end-to-end tests over real sockets
