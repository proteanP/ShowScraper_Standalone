# AGENTS.md

## Local Instructions

- Do not create Sprite checkpoints for this repository unless the user explicitly asks for one.

## Purpose

This repository is a standalone Ruby scraper that collects upcoming live-music events from many venue websites, normalizes them into a shared event shape, and writes one JSON file per venue to Google Cloud Storage (GCS).

The runtime is intentionally simple:
- No web server
- No exposed ports
- One batch process (`bin/run_scraper`) run manually or via system scheduler
- Selenium + headless Firefox for dynamic pages, with selective non-browser scrapers for unstable targets

---

## High-Level Architecture

### Core components

- `bin/run_scraper`
  - CLI entrypoint.
  - Parses flags (`--sources`, `--limit`, `--skip-persist`, etc).
  - Calls `Scraper.run(...)`.
  - Emits warnings/errors and appends summary lines to `LOG_PATH`.

- `scraper/scraper.rb`
  - Main orchestrator.
  - Loads environment, source classes, optional persistence layers.
  - Initializes global Selenium driver (`$driver`) once.
  - Iterates all source adapters, applies timeout/error handling, validates required event fields.
  - Persists source metadata + per-source results in static mode.

- `scraper/lib/sources/*.rb`
  - Venue-specific adapters (47 configured in `sources.json`).
  - Each class implements `.run(events_limit:, &foreach_event_blk)` and returns an array of normalized event hashes.
  - Most use Selenium DOM selectors; a few use `URI.open` + `Nokogiri`/`RSS` directly.

- `scraper/lib/gcs.rb`
  - Thin wrapper around `google-cloud-storage`.
  - Uploads `sources.json` and `<SourceClass>.json` outputs.

- `scraper/lib/sources/manually_added.rb`
  - Preserve-only adapter for backend-managed manual shows.
  - Reads the already-published `ManuallyAdded.json` from GCS so scraper runs do not overwrite manual entries with an empty array.

- `scraper/lib/selenium_patches.rb`
  - Monkey patches Selenium element/driver to add convenience helpers (`css`, `new_tab`, hidden text extraction behavior).

- `sources.json`
  - Canonical source registry and metadata used both for source loading and uploaded venue metadata.
  - `name` values must match Ruby class names exactly (via `constantize`).

### Execution flow

1. `bin/run_scraper` loads `scraper/scraper.rb`.
2. `Scraper::SOURCES` is built from `sources.json` (`source["name"].constantize`).
3. Selenium driver is created (Firefox by default; Chrome path exists but is not used by default).
4. If static persistence is enabled, `sources.json` is uploaded to GCS.
5. Each source class is executed (unless class sets `DISABLED = true`).
6. Per event:
   - Source builds normalized hash.
   - `Utils.print_event_preview` optionally logs event info.
   - Orchestrator validates required keys: `:url`, `:date`, `:title` are present.
   - Optional SQL persistence path can upsert to DB (legacy path; DB code is not included in this repo).
7. After each source:
   - Events are de-duplicated (`uniq`) before JSON upload.
   - Results written to GCS as `<SourceClass>.json`.
   - Condensed count line appended to `LOG_PATH`.
8. At process end:
   - CLI prints warnings for empty sources and errors for failed sources.
   - Warning/error lines also appended to `LOG_PATH`.

---

## Runtime Model and State

### Process model

- Single-process Ruby execution.
- Single shared browser session in global variable `$driver`.
- Source adapters run sequentially (not parallelized).
- Global mutable state is used in a few places:
  - `$driver` for browser access
  - `$retried_paramount` for one-off retry behavior

### Timeouts and failure behavior

- Per-source scrape timeout: `3 minutes` (`Timeout.timeout(60 * 3)`).
- Browser timeouts:
  - Page load: `15s`
  - Script timeout: `10s`
- Source errors are collected and do not stop the full run (current code path always rescues at source loop level).
- Special-case retry exists for `Paramount` only.

### Event schema (normalized contract)

All sources are expected to emit hashes with:
- `:url` (required)
- `:date` (required; `DateTime`)
- `:title` (required)
- `:img` (optional but commonly populated)
- `:details` (optional; usually empty string)

Validation of required keys happens in orchestrator callback before persistence.

Source adapters must emit only the established event keys above. Agents must trace the
normalization, persistence, and consumer contract before adding fields; do not invent
source-specific keys just because a venue website exposes them. Adding a new event
field requires an explicitly requested end-to-end schema and consumer change.

---

## Source Adapter Layer

### Adapter contract

Each adapter class in `scraper/lib/sources` should:
1. Define `self.run(events_limit: ..., &foreach_event_blk)`.
2. Return an array of event hashes in normalized schema.
3. Call the callback for each event: `foreach_event_blk&.call(data)`.
4. Optionally call `Utils.print_event_preview(self, data)` for consistent logging.
5. Handle source-specific parse failures (`rescue return` or debugger path).

### Current source inventory

- Configured sources in `sources.json`: `47`
- Ruby source classes present: `48` (extra legacy class `DnaLounge_OLD`, not in `sources.json`)
- Disabled sources (`DISABLED = true`): `Amados`, `Eagle`, `ElboRoom`, `NewParish`, `Starline`

### Scraper strategy variants

Most sources are Selenium-driven DOM parsers, but there are important variants:

- `DnaLounge`: RSS-based (`URI.open` + `RSS::Parser`) to avoid bot friction.
- `GreatAmericanMusicHall`: static HTML via `Nokogiri.parse(URI.open(...))` because live page load is problematic.
- `NewParish` (currently disabled): static fetch + JSON-LD extraction.
- `MakeOutRoom`: one calendar cell can contain multiple events; parser returns multiple hashes per cell.
- `Knockout` and `Winters`: open detail pages in temporary tab via `driver.new_tab`.
- Calendar UI normalization: `RickshawStop` and `StorkClub` resize browser to force a better calendar layout before parsing.
- Anti-overlay cleanup: some adapters remove cookie/ad overlays via JS (`execute_script`) before interaction (e.g., `Warfield`, `Fillmore`, `Masonic`, `AugustHall`).

### Class loading and naming

- All files under `scraper/lib/sources/*.rb` are `require`d.
- Only classes named in `sources.json` are run.
- Renaming a class requires updating `sources.json` `name` field.

---

## Persistence and Output

### Static output mode (default)

- Enabled unless `--skip-persist`.
- Uploads:
  - `sources.json`
  - One JSON file per source: `<SourceClass>.json`
- Event arrays are de-duplicated with `uniq` before upload.
- GCS cache header is `Cache-Control:no-cache`.

### SQL mode (legacy path)

- Supported in code (`persist_mode: :sql`) but not the default CLI path here.
- Expects DB models (`Venue`, `Event`) from `db/db.rb`, which is not present in this standalone repo.
- Keep this path treated as legacy/incomplete unless DB layer is added back.

### No persistence mode

- `--skip-persist` sets `persist_mode` to `nil`.
- Scraping still runs and prints/logs, but does not upload files.

---

## Configuration Surfaces

### Environment variables

Loaded by Dotenv from repo `.env` in `scraper/scraper.rb`.

Primary vars:
- `HEADLESS` (default true in CLI unless overridden)
- `NO_DB` (default true)
- `NO_GCS` (if true, `GCS` constant set to `nil`, uploads are skipped)
- `PRINT_EVENTS`
- `PRINT_FULL_DETAIL`
- `ONLY_UPDATE_VENUES` (upload `sources.json` then quit)
- `LOG_PATH`
- `STORAGE_PROJECT`, `GCS_BUCKET`, `GCS_TEST_BUCKET`
- `GECKODRIVER_PATH`
- `DEBUGGER`

### CLI flags (`bin/run_scraper`)

- `--headless true|false`
- `--limit N`
- `--skip-persist`
- `--rescue BOOL` (sets env var, but top-level source rescue is effectively always on)
- `--no-scrape` (sets `ONLY_UPDATE_VENUES=true`)
- `--debugger`
- `--sources A,B,C` (class names; invalid names abort run)

---

## Execution Architecture

### Setup and Dependencies

- Run `ruby setup.rb` to install system dependencies (Firefox, geckodriver) and Ruby gems.
- Setup script auto-detects system architecture and downloads appropriate geckodriver binary.
- Dependencies are installed locally; no containerization required.

### Running the Scraper

- Run the scraper directly with host Ruby: `bin/run_scraper`
- For one-off runs and source-specific tests: `bin/run_scraper --sources GreatAmericanMusicHall --limit 5 --skip-persist`
- Environment variables are loaded from `.env` file via Dotenv.

---

## Extension and Maintenance Guide

### Adding a new source adapter

1. Add `scraper/lib/sources/<source_file>.rb` with class `<SourceClass>`.
2. Implement `.run(events_limit:, &foreach_event_blk)` returning normalized hashes.
3. Add venue entry in `sources.json` with `"name": "<SourceClass>"` plus metadata.
4. Run:
   - `bin/run_scraper --sources <SourceClass> --limit 5 --skip-persist`
5. Verify no missing required keys (`url`, `date`, `title`) and date parsing stability.
6. Every ready-for-review PR description for scraper additions or repairs must include a fenced `json` block containing an array of two or three representative events actually created by the focused verification run. Preserve the exact emitted JSON keys and exact values for those events; do not convert the sample to a table, Ruby hashes, prose, fabricated examples, or normalized placeholders. The sample should make omitted and present fields truthful to actual output.

### Common implementation patterns

- Start with a single page parse before adding pagination/“load more”.
- Add defensive parse guards (`rescue return`) around brittle date parsing.
- Use `driver.new_tab` only when needed (costly).
- Strip overlays/iframes when click interception occurs.
- Avoid long sleeps; prefer deterministic selectors when possible.

### Typical failure classes

- Selector drift from venue frontend redesign.
- Cookie/ad overlays intercepting clicks.
- Lazy-loaded content not visible without scroll/resize.
- Ambiguous human date strings (e.g., “Tuesday 8PM”).
- Bot mitigation and anti-automation behavior.

---

## Observability and Debugging

- Real-time previews:
  - `PRINT_EVENTS=true`
  - `PRINT_FULL_DETAIL=true` for full payload dump
- Logs:
  - Per-source counts and warnings/errors appended to `LOG_PATH`
- Interactive debugging:
  - `--debugger` enables `binding.pry` on exceptions in source parsers
  - Run single source with small limit for tight feedback cycle

---

## Security and Operational Notes

- GCS credentials are expected at `credentials/credentials.json`.
- Repo contains no HTTP server surface; keep it that way to avoid accidental secret/file exposure.
- When running publicly reachable environments, do not add endpoints that expose filesystem or env vars.
- Keep credentials mount read-only.

---

## Important Couplings and Caveats

- `sources.json` is both runtime source registry and published metadata artifact.
- Source names in `sources.json` are hard-coupled to Ruby class constants.
- Code has a Chrome driver initialization path, but runtime currently uses Firefox path by default.
- Error handling env var `RESCUE_SCRAPING_ERRORS` exists, but current top-level rescue behavior is effectively always enabled.
- `NO_DB=false` requires non-existent DB code in this standalone repo.

---

## Quick File Map

- `setup.rb`: Installation script for dependencies and gems
- `bin/run_scraper`: CLI + run summary logging
- `scraper/scraper.rb`: orchestration, driver lifecycle, persistence hooks
- `scraper/lib/selenium_patches.rb`: Selenium monkey patches
- `scraper/lib/gcs.rb`: GCS upload/download helper
- `scraper/lib/sources/*.rb`: source adapters
- `sources.json`: source registry + metadata
- `.env.example`: environment variables template
- `Gemfile`: Ruby dependencies
