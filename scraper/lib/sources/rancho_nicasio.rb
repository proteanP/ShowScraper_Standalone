require "cgi"
require "json"
require "open-uri"

class RanchoNicasio
  EVENTS_API_URL = "https://ranchonicasio.com/wp-json/tribe/events/v1/events/?venue=53&per_page=50"
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    events = []

    fetch_events.each do |event|
      break if events.count >= events_limit
      result = parse_event_data(event, &foreach_event_blk)
      events << result if result
    end

    events
  end

  class << self
    private

    def fetch_events
      first_page = fetch_page(1)
      events = first_page.fetch("events", [])

      (2..first_page.fetch("total_pages", 1)).each do |page|
        events.concat(fetch_page(page).fetch("events", []))
      end

      events.select { |event| parse_date(event).to_date >= current_pacific_date }.
        sort_by { |event| parse_date(event) }
    rescue JSON::ParserError => e
      raise "RanchoNicasio invalid events JSON: #{e.message}"
    end

    def fetch_page(page)
      JSON.parse(URI.open("#{EVENTS_API_URL}&page=#{page}", "User-Agent" => "Mozilla/5.0").read)
    end

    def parse_event_data(event, &foreach_event_blk)
      title = normalize_text(event["title"])
      url = event["url"].to_s
      return if title.blank? || url.blank?

      {
        url: url,
        img: event.dig("image", "url").to_s,
        date: parse_date(event),
        title: title,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date(event)
      DateTime.parse(event.fetch("start_date"))
    end

    def current_pacific_date
      Time.current.in_time_zone(TIME_ZONE).to_date
    end

    def normalize_text(value)
      CGI.unescapeHTML(value.to_s).gsub(/[[:space:]]+/, " ").strip
    end
  end
end
