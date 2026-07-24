require "cgi"
require "json"
require "open-uri"

class FourStarTheater
  MAIN_URL = "https://www.4-star-movies.com/"
  EVENTS_URL = "#{MAIN_URL}calendar-of-events"
  FEED_URL = "#{EVENTS_URL}?format=json"
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    fetch_events.first(events_limit).map do |event|
      parse_event_data(event, &foreach_event_blk)
    end.compact
  end

  class << self
    private

    def fetch_events
      JSON.parse(URI.open(FEED_URL).read).fetch("upcoming", [])
    rescue JSON::ParserError => e
      raise "FourStarTheater invalid events JSON: #{e.message}"
    end

    def parse_event_data(event, &foreach_event_blk)
      title = normalize_text(event["title"])
      date = parse_date(event)
      return if title.blank? || date < Time.current.in_time_zone(TIME_ZONE).to_datetime

      {
        url: event_url(event),
        img: event["assetUrl"].to_s,
        date: date,
        title: title,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date(event)
      start_ms = event["startDate"] || event.dig("structuredContent", "startDate")
      raise "FourStarTheater missing startDate for #{event["title"]}" unless start_ms

      Time.at(start_ms.to_f / 1000).in_time_zone(TIME_ZONE).to_datetime
    end

    def event_url(event)
      path = event["fullUrl"].to_s
      return EVENTS_URL if path.blank?
      return "#{MAIN_URL.delete_suffix("/")}#{path}" if path.start_with?("/")
      path
    end

    def normalize_text(value)
      CGI.unescapeHTML(value.to_s).
        gsub(/[[:space:]]+/, " ").
        strip
    end
  end
end
