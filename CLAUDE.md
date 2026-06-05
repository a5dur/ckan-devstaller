# ckan-devstaller

Rust CLI that installs CKAN 2.11.3 from source on Ubuntu 22.04. Two modes: interactive (prompts) or `--default` (silent).

## Build

```bash
cargo build --release
./target/release/ckan-devstaller
```

Requires Rust. Install via `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`.

## Source layout

| File | Purpose |
|------|---------|
| `src/main.rs` | CLI entry, `Config` struct, full install orchestration (~499 lines) |
| `src/questions.rs` | `inquire`-based interactive prompts (SSH, CKAN version, sysadmin) |
| `src/steps.rs` | Step display helpers (intro, numbered steps) |
| `src/styles.rs` | Terminal color helpers via `owo-colors` |
| `install.bash` | Bootstrap script: apt update, curl binary from releases, run installer |

## Key dependencies

- `clap` — CLI arg parsing (`--default` flag)
- `inquire` — interactive terminal prompts (requires real TTY)
- `xshell` / `xshell-venv` — shell command execution and Python venv management
- `rust-ini` — read/write `/etc/ckan/default/ckan.ini`
- `human-panic` — friendly panic messages

## Architecture

`main.rs` builds a `Config` struct (either from prompts or defaults), then runs install steps sequentially:

1. `apt update && apt upgrade`
2. Install curl + optional openssh-server
3. Install Ahoy CLI (arm64 or x86_64 binary from GitHub releases)
4. Clone and start ckan-compose (PostgreSQL, Solr, Redis via Docker)
5. Create Python venv at `/usr/lib/ckan/default`, install CKAN via pip
6. Set up `/etc/ckan/default/ckan.ini`
7. Set up DataStore (DB permissions, config)
8. Optionally install ckanext-scheming, DataPusher+
9. Start CKAN dev server

## Known issues / fixes applied

- **pip 26+ incompatibility**: `#egg=pkg[extras]` fragment syntax rejected. Fixed to use PEP 440 direct URL syntax: `pkg[extras] @ git+https://...`
- **ARM support**: Release binaries are x86_64. On ARM (e.g. Apple Silicon Ubuntu VM), build from source with `cargo build --release`.
- **install.bash unquoted variable**: `$flag` must be quoted in the `if` check to avoid `unary operator expected` error when no arg is passed.

## Adding a sysadmin after install

```bash
/usr/lib/ckan/default/bin/ckan -c /etc/ckan/default/ckan.ini user add <username> email=<email> password=<password>
/usr/lib/ckan/default/bin/ckan -c /etc/ckan/default/ckan.ini sysadmin add <username>
```
