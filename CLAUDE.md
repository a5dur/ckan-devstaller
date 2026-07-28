# ckan-devstaller

Rust CLI that installs CKAN from source on Ubuntu 22.04. Default target is **CKAN 2.12 (unreleased `dev-v2.12` branch)**. Two modes: interactive (prompts) or `--default` (silent).

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
5. Create Python venv at `/usr/lib/ckan/default`, install CKAN via pip (ref from `ckan_git_ref()`)
6. Set up `/etc/ckan/default/ckan.ini`, add sysadmin
7. Set up DataStore (DB permissions, config)
8. Install ckanext-scheming + DataPusher+ (editable), set DPP config, DB upgrade
9. Install dathere extensions, set authoritative `ckan.plugins`, start Prefect (server + deploy + host worker)
10. Start CKAN dev server (with `PREFECT_API_URL`)

## CKAN version selection

- `ckan_git_ref()` in `main.rs` maps the user-facing version to a git ref: `2.12-dev` / `2.12` / `dev-v2.12` → branch **`dev-v2.12`**; anything else → tag `ckan-{version}`.
- 2.12 has **no release tag** — latest tags are `ckan-2.11.5` / `2.11.4` / `2.11.3`. `dev-v2.12` == `master`.
- Both the pip install and the `git clone` of `/usr/lib/ckan/default/src` use that same ref, so the source tree matches the installed package.
- Prompt options: `2.12-dev`, `2.11.5`, `2.11.3`, `2.10.8`, `Other`.

## CKAN 2.12 vs 2.11.3

Dependency jumps: sqlalchemy `1.4.52 → 2.0.51`, flask `3.0.3 → 3.1.3`, werkzeug `3.0.6 → 3.1.8`, redis `5.0.7 → 8.0.1`, rq `1.16.2 → 2.10.0`, webassets `2.0 → 3.0.0`, pysolr `3.9 → 3.11`, msgspec `0.18.6 → 0.21.1`, new `file-keeper==0.2.4` + `croniter`. Dev pin flask-debugtoolbar `0.14.1 → 0.16.0`.

Breaking changes that affect this stack:

- **CSRF**: `ckan.csrf_protection.ignore_extensions` **removed**. Extension forms must ship the CSRF snippet or POSTs 400 (`dathere_theme`, `ckanext-gztr`, DPP DRUF forms).
- **Template blocks removed** from `package/search.html`: `page_primary_action`, `form`, `package_search_results_list` — theme overrides extending them raise TemplateError.
- **PackageExtra / GroupExtra tables removed** → JSONB fields on the package/group models.
- **Files are first-class entities**: `Upload`/`ResourceUpload` → `FKUpload`/`FKResourceUpload` when storages are configured; `ckan.storage_path` deprecated; new `ckan.uploads_enabled`.
- **`ckan datastore set-permissions` must be re-run** — defines the new `fast_table_row_count` function (#9234). Step 7 already does this.
- Config options are no longer shared with Flask by default (needs `flask: true` in the declaration).
- Deprecated: `context["model"]`, `IGroupForm.form_to_db_*` / `db_to_form_*`, `h.truncate()`, `h.get_site_statistics()`.
- DataStore field names/IDs validated at schema level (no control characters). User emails now case-insensitively unique.
- New: `ckan db check`, `ckan.webassets.debug`, `ckan.datastore.public_table_search`; `ckan jobs worker` runs a scheduler unless `--no-scheduler`.

Unchanged, so no installer work needed: Python 3.10+ (Ubuntu 22.04 ships 3.10.6), PostgreSQL 12+, Solr 9 (2.11 vs 2.12 `schema.xml` differ only in the `schema name` attribute; CKAN checks `version="1.6"`), the `ckan.datastore.*` config keys, and the `generate config` / `db init` / `db upgrade -p` / `config-tool` CLI.

**`who.ini` is gone in 2.12** — the symlink step is now guarded by an existence check on `/usr/lib/ckan/default/src/who.ini`. (The old path `src/ckan/who.ini` never existed under this clone layout; `ln -s` doesn't validate targets, so it silently made a dangling link.)

## DataPusher+ (Prefect-based)

- Source: **`a5dur/datapusher-plus@main`** — Prefect job backend (not RQ), currently version `3.0.0a0`, `requires-python >=3.10`, README claims CKAN 2.10+. Installed **editable** via `git clone` + `pip install -e .` + `pip install -r requirements.txt`.
- Editable is still what the installer needs, but for a different reason than before: the repo moved to `pyproject.toml` with `include-package-data = true`, so a plain install now ships `assets/webassets.yml`, templates and `public/` correctly. The clone is kept because Step 9 reads `docker-compose.prefect.yaml` and `prefect.yaml` out of the source tree.
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
- **DPP non-editable install drops data files**: was true when DPP's `setup.py` had no `package_data`. Fixed upstream — `pyproject.toml` now sets `include-package-data = true`. Editable install retained for the compose/prefect YAMLs (see above).
- **No `extra_template_paths`**: pointing it at DPP's templates dir caused a `RecursionError` (`{% ckan_extends %}` loop). Template priority is handled via plugin order instead.
- **`ckan.plugins` is a list in CKAN 2.11+**: DPP `formula.py should_skip()` handles both list and string (upstream fix present in `@main`).
- **Plugin migrations never applied**: `db init` runs at step 6, before step 9 sets `ckan.plugins`, so plugin alembic branches (activity, tracking, …) were skipped. On 2.12 that leaves `activity` without `permission_labels`; `h.new_activities()` — called from the dathere_theme header for any logged-in user — then raises `UndefinedColumn`, aborting the transaction so every later query in that session fails with `InFailedSqlTransaction` until the process restarts. Fixed by running `ckan db upgrade` at the end of step 9.
- **Extension compat on 2.12 is unverified**: `ckanext-scheming`, `ckanext-spatial@gztr` (GeoAlchemy2 / SQLAlchemy 2.0), `dathere_theme@sandbox`, `ckanext-gztr@sandbox` all target 2.10/2.11. Expect CSRF 400s, removed-template-block errors, and SQLAlchemy 2.0 breakage until they're ported.
- **sudo in non-TTY**: the Prefect `docker-compose up` needs sudo; run it from a terminal (the automated installer runs under a real TTY).

## Adding a sysadmin after install

```bash
/usr/lib/ckan/default/bin/ckan -c /etc/ckan/default/ckan.ini user add <username> email=<email> password=<password>
/usr/lib/ckan/default/bin/ckan -c /etc/ckan/default/ckan.ini sysadmin add <username>
```
