require "selenium-webdriver"
require 'pry'
require 'active_support/all'
require 'dotenv'
require 'date'

Dotenv.load("#{__dir__}/../.env")

require "#{__dir__}/lib/selenium_patches.rb"
Dir.glob("#{__dir__}/lib/sources/*.rb").each { |path| require path }

unless ENV["NO_DB"] == "true"
  require "#{__dir__}/../db/db.rb"
end

if ENV["NO_GCS"] == "true"
  GCS = nil
else
  require "#{__dir__}/lib/gcs.rb"
end

class Utils
  DEFAULT_LOG_GCS_PATH = "scraper.log"
  DEFAULT_LOG_RETENTION_DAYS = 2
  DEFAULT_LOG_MAX_LINES = 200

  def self.print_event_preview(source, data)
    return unless ENV["PRINT_EVENTS"] == "true"
    if ENV["PRINT_FULL_DETAIL"] == "true"
      pp data
    else
      puts("#{source.name} #{data[:date]&.strftime("%m/%d")}: #{data[:title]&.gsub("\n", " ")}")
    end
  end

  def self.quit!
    $driver&.quit
    exit!
  end

  def self.append_log_lines(lines)
    lines = Array(lines).map(&:to_s).reject(&:blank?)
    return if lines.empty?

    if log_to_gcs?
      append_lines_to_gcs(lines)
    elsif ENV["LOG_PATH"].present?
      File.open(ENV["LOG_PATH"], "a") do |f|
        lines.each { |line| f.puts(line) }
      end
    end
  rescue => e
    puts "WARNING: failed to write logs: #{e.class} #{e.message}"
    return if ENV["LOG_PATH"].blank?
    File.open(ENV["LOG_PATH"], "a") do |f|
      lines.each { |line| f.puts(line) }
    end
  end

  def self.log_to_gcs?
    GCS.present? && log_gcs_path.present?
  end

  def self.log_gcs_path
    return nil if ENV.key?("LOG_GCS_PATH") && ENV["LOG_GCS_PATH"].blank?
    ENV["LOG_GCS_PATH"].presence || DEFAULT_LOG_GCS_PATH
  end

  def self.log_retention_days
    (ENV["LOG_RETENTION_DAYS"].presence || DEFAULT_LOG_RETENTION_DAYS).to_i
  end

  def self.log_max_lines
    (ENV["LOG_MAX_LINES"].presence || DEFAULT_LOG_MAX_LINES).to_i
  end

  def self.append_lines_to_gcs(new_lines)
    existing_text = GCS.download_file_as_text(source: log_gcs_path).to_s
    existing_lines = existing_text.lines.map(&:chomp)
    final_lines = apply_log_retention(existing_lines + new_lines)
    payload = final_lines.join("\n")
    payload += "\n" unless payload.empty?
    GCS.upload_text_as_file(
      text: payload,
      dest: log_gcs_path,
      cache_control: GCS::CACHE_CONTROL_NO_STORE
    )
  end
  private_class_method :append_lines_to_gcs

  def self.apply_log_retention(lines)
    cutoff_date = Date.today - log_retention_days.days
    recent_lines = lines.select do |line|
      line_date = parse_log_date(line)
      line_date.nil? || line_date >= cutoff_date
    end
    recent_lines.last(log_max_lines)
  end
  private_class_method :apply_log_retention

  def self.parse_log_date(line)
    if (mdy = line.match(/\A(\d{2}\/\d{2}\/\d{4})/))
      return Date.strptime(mdy[1], "%m/%d/%Y")
    end
    if (iso = line.match(/\A(\d{4}-\d{2}-\d{2})/))
      return Date.strptime(iso[1], "%Y-%m-%d")
    end
    nil
  rescue ArgumentError
    nil
  end
  private_class_method :parse_log_date
end

def quit!; Utils.quit! end

class Scraper
  SOURCE_LIST_JSON = "#{__dir__}/../sources.json"

  SOURCES = JSON.parse(File.read(SOURCE_LIST_JSON)).map { |source| source["name"].constantize }

  class << self

    def run(sources=SOURCES, events_limit: nil, persist_mode: :static)
      sources = SOURCES if sources.nil?

      $driver ||= init_driver
      at_exit { $driver.quit }

      persist_sources_list if persist_mode == :static

      if ENV["ONLY_UPDATE_VENUES"] == "true"
        Utils.quit!
      end

      results = {}
      errors = []
      sources.each do |source|
        next if source.const_defined?(:DISABLED) && source::DISABLED
        event_list = run_scraper(source, events_limit: events_limit) do |event_data|
          unless %i[url date title].all? { |key| event_data[key].present? }
            raise "#{source.name} had missing data keys"
          end
          if persist_mode == :sql
            persist_sql(source, event_data)
          end
        end
        persist_event_list(source, event_list) if persist_mode == :static
        results[source.name] = event_list
      rescue => e
#        if ENV["RESCUE_SCRAPING_ERRORS"] == "true"
          if source == Paramount && !$retried_paramount
            $retried_paramount = true
            puts "RETRYING PARAMOUNT"
            sleep 5
            retry
          else
            puts e, e.backtrace
            errors.push({ source: source.name, error: e })
          end
 #       else
 #         raise
 #       end
      end

      # persist_error_list

      [results, errors]
    end

    private

    def persist_sql(source, event_data)
      venue = Venue.find_by!(name: source.name)
      existing_event = venue.events.find_by(
        date: event_data[:date],
        title: event_data[:title]
      )
      if existing_event
        existing_event.update(event_data)
      else
        venue.events.create!(event_data)
      end
    end

    def persist_sources_list
      GCS&.upload_file(source: SOURCE_LIST_JSON, dest: "sources.json")
    end

    def persist_event_list(source, event_list)
      # Sometimes there are duplicate events, mainly caused by calendar views
      # showing the previous / next months events.
      json = event_list.uniq.to_json

      # upload to GCS
      GCS&.upload_text_as_file(text: json, dest: "#{source}.json")

      Utils.append_log_lines(
        "#{Time.now.strftime("%m/%d/%Y")}: scraped #{event_list.uniq.count.to_s.ljust(4)} events from #{source}"
      )
    end

    def init_driver
      # init_driver_chrome
      init_driver_firefox
    end

    def init_driver_firefox
      options = Selenium::WebDriver::Firefox::Options.new
      options.add_argument('--headless') unless ENV["HEADLESS"] == "false"
      options.add_argument('--width=1920')
      options.add_argument('--height=1080')
      # Set user agent to avoid bot detection
      options.add_preference('general.useragent.override', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:130.0) Gecko/20100101 Firefox/130.0')

      # Set Firefox binary path if specified
      if ENV["FIREFOX_PATH"]
        options.binary = ENV["FIREFOX_PATH"]
      end

      service = Selenium::WebDriver::Service.firefox(path: ENV.fetch("GECKODRIVER_PATH", "/usr/local/bin/geckodriver"))
      driver = Selenium::WebDriver.for :firefox, options: options, service: service

      # Anti-bot fingerprinting - mask webdriver detection
      driver.execute_script(<<~JS)
        Object.defineProperty(navigator, 'webdriver', {
          get: () => undefined
        });
        window.navigator.chrome = { runtime: {} };
        Object.defineProperty(navigator, 'plugins', {
          get: () => [1, 2, 3, 4, 5]
        });
        Object.defineProperty(navigator, 'languages', {
          get: () => ['en-US', 'en']
        });
      JS

      SeleniumPatches.patch_driver(driver) # if compatible
      driver.manage.timeouts.page_load = 15
      driver.manage.timeouts.script_timeout = 10

      driver
end


    def init_driver_chrome
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless=new') unless ENV["HEADLESS"] == "false"
      options.add_argument('--window-size=1920,1080')
      options.add_argument('--disable-blink-features=AutomationControlled')
      options.add_argument('--no-sandbox')
      options.add_argument('--disable-dev-shm-usage')
      options.add_argument('--disable-extensions')
      options.add_argument('--disable-background-networking')
      options.add_argument('--disable-sync')
      options.add_argument('--metrics-recording-only')
      options.add_argument('--mute-audio')
      options.add_argument('--ignore-certificate-errors')
      options.add_argument('--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36')

      if File.exist?("/proc/device-tree/model") && `cat /proc/device-tree/model`.include?("Raspberry Pi")
        driver_path = "/usr/bin/chromedriver"
        service = Selenium::WebDriver::Chrome::Service.new(path: driver_path)
      else
        service = Selenium::WebDriver::Chrome::Service.chrome
      end

      driver = Selenium::WebDriver.for :chrome, options: options, service: service

      # Patches
      SeleniumPatches.patch_driver(driver)

      # Hard timeouts
      driver.manage.timeouts.page_load = 15
      driver.manage.timeouts.script_timeout = 10

      # Anti-bot fingerprint patch
      driver.execute_cdp('Page.addScriptToEvaluateOnNewDocument', source: <<~JS)
        Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
        window.navigator.chrome = { runtime: {} };
        Object.defineProperty(navigator, 'plugins', { get: () => [1,2,3,4,5] });
        Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
      JS

      driver
    end

    require 'timeout'
    def run_scraper(source, events_limit: nil, &foreach_event_blk)
      Timeout.timeout(60 * 3) do
        source.run(**{ events_limit: events_limit }.compact, &foreach_event_blk)
      end
    end

  end
end

# Scraper.run([DnaLounge], persist: true)
