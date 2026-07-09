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
| `src/main.rs` | CLI entry, `Config` struct, full install orchestration |
| `src/questions.rs` | `inquire`-based interactive prompts (SSH, CKAN version, sysadmin) |
| `src/steps.rs` | Step display helpers (intro, numbered steps) |
| `src/styles.rs` | Terminal color helpers via `owo-colors` |
| `install.bash` | Bootstrap script: apt update, curl binary from releases, run installer |
| `install_extensions.sh` | Standalone alt for the dathere extensions + `ckan.plugins` (same as main.rs Step 9); run after base install in an activated venv |

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
6. Set up `/etc/ckan/default/ckan.ini`, add sysadmin
7. Set up DataStore (DB permissions, config)
8. Install ckanext-scheming + DataPusher+ (editable), set DPP config, DB upgrade
9. Install dathere extensions, set authoritative `ckan.plugins`, start Prefect (server + deploy + host worker)
10. Start CKAN dev server (with `PREFECT_API_URL`)

## DataPusher+ (Prefect-based)

- Source: **`a5dur/datapusher-plus@main`** — Prefect job backend (not RQ). Installed **editable** via `git clone` + `pip install -e .` + `pip install -r requirements.txt`. Editable is required: `setup.py` declares no `package_data`, so a non-editable install drops `assets/webassets.yml`, templates, and `public/` — breaking DRUF overrides and suggestion assets.
- Jobs dispatch to Prefect (`prefect_client.run_deployment`). main.rs brings up `postgres` + `prefect-server` from the repo's `docker-compose.prefect.yaml` (the compose `prefect-worker` service is **skipped** — bare `prefecthq/prefect` image has no CKAN, can't import the flow or reach the datastore), runs `ckan datapusher_plus prefect-deploy`, then starts a **host-side** `prefect worker --pool datapusher-plus` in the venv. Prefect UI: `http://localhost:4200`.
- Deps of note (requirements.txt): `prefect>=3.7,<3.8`, `importlib_metadata`, `blake3`, `babel`.

## Extensions & plugin config (Step 9 / install_extensions.sh)

- Installs `ckanext-envvars`, `ckanext-spatial@gztr`, `dathere_theme@sandbox`, `ckanext-gztr@sandbox` (idempotent clones).
- Sets authoritative `ckan.plugins` (order matters):
  `envvars activity datastore datapusher_plus scheming_datasets spatial_metadata spatial_query dathere_theme dathere_custom_css dathere_custom_homepage dathere_custom_header dathere_custom_footer gztr`
- `datapusher_plus` **before** `scheming_datasets`: under `IConfigurer._reverse_iteration_order`, earlier-listed plugins get higher template priority, so DPP's scheming `form_snippet` overrides (suggestion buttons) win only in this order.
- `scheming.dataset_schemas = ckanext.gztr:schemas/dataset.yaml` — that schema carries the 5 DRUF `suggestion_formula` fields (`description`, `spatial_description`, `coordinate_system`, `update_frequency`, `primary_key_field`). Without it, scheming has no schema for type `dataset` and DPP's DRUF `add_dataset` snippet renders zero "Add Dataset" buttons.
- `scheming.presets = ckanext.scheming:presets.json ckanext.gztr:schemas/presets.yaml`.

## Known issues / fixes applied

- **pip 26+ incompatibility**: `#egg=pkg[extras]` fragment syntax rejected. Fixed to use PEP 440 direct URL syntax: `pkg[extras] @ git+https://...`
- **ARM support**: Release binaries are x86_64. On ARM (e.g. Apple Silicon Ubuntu VM), build from source with `cargo build --release`. qsv `aarch64` binary = arm64 (correct for Apple Silicon).
- **install.bash unquoted variable**: `$flag` must be quoted in the `if` check to avoid `unary operator expected` error when no arg is passed.
- **DPP non-editable install drops data files**: `setup.py` has no `package_data` → use editable install (see above).
- **No `extra_template_paths`**: pointing it at DPP's templates dir caused a `RecursionError` (`{% ckan_extends %}` loop). Template priority is handled via plugin order instead.
- **`ckan.plugins` is a list in CKAN 2.11.3**: DPP `formula.py should_skip()` handles both list and string (upstream fix present in `@main`).
- **sudo in non-TTY**: the Prefect `docker-compose up` needs sudo; run it from a terminal (the automated installer runs under a real TTY).

## Adding a sysadmin after install

```bash
/usr/lib/ckan/default/bin/ckan -c /etc/ckan/default/ckan.ini user add <username> email=<email> password=<password>
/usr/lib/ckan/default/bin/ckan -c /etc/ckan/default/ckan.ini sysadmin add <username>
```
