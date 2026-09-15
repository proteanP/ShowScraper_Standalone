# ShowScraper - Standalone Version

Offline web scraping for music venue events using Ruby, Firefox, and Selenium WebDriver.

## Prerequisites

- Ruby 3.0+
- Firefox browser
- Git (for version control)

## Quick Start

### Option A: Local machine only

1. Run setup:
```bash
ruby setup.rb
```

2. Configure environment (optional):
```bash
cp .env.example .env
# Edit .env with your settings (GCS credentials, etc.)
```

3. Run the scraper:
```bash
# Run once
bin/run_scraper
```

### Option B: Sprite workflow (`sprite_setup.sh` + `setup.rb`)

Use this when you want to run in a Sprite and already have local secrets/config files prepared.

1. On your local machine, make sure these files exist in this repo:
- `.env`
- `credentials/credentials.json`

2. Run:
```bash
./sprite_setup.sh
```

`sprite_setup.sh` does the following:
- Clones this repo onto the target Sprite (`SPRITE_NAME`, default: `show-scraper`)
- Copies local `.env` to `/home/sprite/ShowScraper_Standalone/.env` on the Sprite
- Copies local `credentials/credentials.json` to `/home/sprite/ShowScraper_Standalone/credentials/credentials.json` on the Sprite
- Runs `ruby setup.rb` on the Sprite in `/home/sprite/ShowScraper_Standalone`

3. `setup.rb` then installs runtime dependencies on the Sprite:
- Ensures Firefox is available
- Installs Geckodriver and sets `GECKODRIVER_PATH`
- Installs Ruby gems (`bundle install`)
- Creates required directories (`credentials`, `logs`)

4. Run the scraper (locally or on the Sprite as needed):

```bash
bin/run_scraper --limit 50
bin/run_scraper --sources DnaLounge,Fillmore
bin/run_scraper --headless false
```

### Credential-free Sprite bootstrap

For a freshly cloned Sprite checkout where a separate bootstrap owns any secrets,
run:

```bash
bin/setup_sprite
```

This idempotently installs the repository-local Firefox and pinned geckodriver,
installs the locked Ruby gems into `vendor/bundle`, and runs a 45-second headless Selenium smoke test.
It neither loads nor copies `.env` or `credentials/`, makes no GCS writes, and
removes the temporary Firefox profile when the test exits. To repeat only the
no-network browser check, run `bin/verify_sprite_browser`.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HEADLESS` | `true` | Run browser in headless mode |
| `NO_DB` | `true` | Skip database connection |
| `NO_GCS` | `false` | Skip Google Cloud Storage |
| `PRINT_EVENTS` | `true` | Print events as they are scraped |
| `PRINT_FULL_DETAIL` | `false` | Print full JSON or condensed output |
| `RESCUE_SCRAPING_ERRORS` | `true` | Continue on errors |
| `LOG_PATH` | `./logs/scraper.log` | Local log file path |
| `GECKODRIVER_PATH` | auto-detected | Path to geckodriver binary |

### Google Cloud Storage

To use GCS:

1. Place your credentials JSON file in `credentials/`
2. Set in `.env`:
   ```
   NO_GCS=false
   STORAGE_PROJECT=your-project-id
   GCS_BUCKET=your-bucket-name
   GCS_TEST_BUCKET=your-test-bucket-name
   ```

## Command Line Options

```bash
# Limit number of events
bin/run_scraper --limit 50

# Scrape specific sources
bin/run_scraper --sources DnaLounge,Fillmore

# Run in non-headless mode
bin/run_scraper --headless false

# Skip persisting results
bin/run_scraper --skip-persist

# Enable debugger
bin/run_scraper --debugger
```

## Scheduling Runs

Use your system's native task scheduler to run the scraper on a schedule:

**macOS (launchd):**
Create `~/Library/LaunchAgents/com.showscraper.plist` with your schedule.

**Linux (systemd):**
Create a systemd timer for scheduling.

## Development

### Interactive Shell

```bash
# Run scraper with debugger
bin/run_scraper --debugger

# Start Ruby console in the app context
pry -r ./scraper/scraper.rb
```

### Running Specific Scrapers

```bash
bin/run_scraper --sources DnaLounge --limit 5 --debugger
```

## Troubleshooting

### Firefox not found

**macOS:**
```bash
brew install firefox
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get install firefox-esr
```

### Geckodriver installation issues

If the setup script fails to install Geckodriver, manually download from:
https://github.com/mozilla/geckodriver/releases/

Then move to one of:
- `/usr/local/bin/geckodriver` (system-wide)
- `./bin/geckodriver` (project-local)

And update `.env` with the path:
```
GECKODRIVER_PATH=/path/to/geckodriver
```

### Permission issues

Ensure geckodriver is executable:
```bash
chmod +x /path/to/geckodriver
```

### Viewing logs

```bash
tail -f logs/scraper.log
```

## Project Structure

```
ShowScraper/
├── setup.rb               # Setup script
├── .env.example          # Environment variables template
├── .env                  # Your configuration (gitignored)
├── Gemfile               # Ruby dependencies
├── Gemfile.lock          # Locked gem versions
├── sources.json          # Venues to scrape
├── bin/
│   └── run_scraper       # Main entry point
├── scraper/
│   ├── scraper.rb        # Scraper orchestration
│   └── lib/
│       ├── gcs.rb        # Google Cloud Storage interface
│       ├── selenium_patches.rb  # Browser patches
│       └── sources/      # Individual venue scrapers
├── credentials/          # GCS credentials (gitignored)
└── logs/                 # Log files (gitignored)
```

## License

See parent project LICENSE file.
