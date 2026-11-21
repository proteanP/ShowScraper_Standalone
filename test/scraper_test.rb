# Offline tests: no browser, network, database or GCS. Run with `bundle exec ruby test/scraper_test.rb`.
ENV["NO_DB"] = "true"
ENV["NO_GCS"] = "true"

require "minitest/autorun"
require "stringio"
require_relative "../scraper/scraper"

FIXTURES = "#{__dir__}/fixtures"

class ScraperTest < Minitest::Test
  # Serve a fixture file from URI.open for the duration of the block.
  def with_feed(name)
    original = URI.method(:open)
    body = File.read("#{FIXTURES}/#{name}")
    URI.define_singleton_method(:open) { |*_args, **_opts| StringIO.new(body) }
    yield
  ensure
    URI.define_singleton_method(:open, original)
  end

  def test_every_listed_source_has_a_run_method
    assert_operator Scraper::SOURCES.size, :>, 0
    Scraper::SOURCES.each { |source| assert_respond_to source, :run }
  end

  def test_indybay_parses_ical_feed
    events = with_feed("indybay.ics") { Indybay.run }

    assert_equal 2, events.size
    potluck, teach_in = events

    assert_equal "Community potluck and open mic (Location: Lake Merritt)", potluck[:title]
    assert_equal "https://www.indybay.org/newsitems/2026/11/20/1.php", potluck[:url]
    assert_equal "Lake Merritt", potluck[:location]
    assert_equal DateTime.new(2026, 11, 21, 17, 0, 0), potluck[:date]
    assert_includes potluck[:details], "Bring a dish, an instrument; or both.\nAll ages."

    assert_equal "All-day teach-in", teach_in[:title]
    assert_equal Date.new(2026, 12, 5), teach_in[:date].to_date
  end

  def test_indybay_respects_events_limit
    assert_equal 1, with_feed("indybay.ics") { Indybay.run(events_limit: 1) }.size
  end

  def test_dna_lounge_parses_rss_feed
    events = with_feed("dnalounge.rss") { DnaLounge.run }

    assert_equal 2, events.size
    night, matinee = events

    assert_equal "https://www.dnalounge.com/calendar/2026/11-14.html", night[:url]
    assert_equal "Test: Night", night[:title]
    assert_equal "https://cdn.dnalounge.com/flyers/2026/11/14-1-thumb.jpg", night[:img]
    assert_equal DateTime.new(2026, 11, 14, 22, 0, 0), night[:date]

    assert_equal "Flyerless Matinee", matinee[:title]
    assert_equal "https://cdn.dnalounge.com/logo2025.gif", matinee[:img]
  end

  def test_sources_yield_each_event_to_the_block
    seen = []
    with_feed("dnalounge.rss") { DnaLounge.run { |event| seen << event[:title] } }
    assert_equal ["Test: Night", "Flyerless Matinee"], seen
  end

  def test_log_retention_drops_old_dated_lines_and_keeps_undated_ones
    old = (Date.today - 10).strftime("%m/%d/%Y")
    recent = Date.today.strftime("%Y-%m-%d")
    lines = ["#{old} old run", "#{recent} new run", "no date"]

    assert_equal ["#{recent} new run", "no date"], Utils.send(:apply_log_retention, lines)
  end
end
