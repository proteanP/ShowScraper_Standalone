require "json"
require "open-uri"

class MacsAt19Broadway
  # Mac's links its official calendar to this Eventbrite organizer. The API gives
  # us the full event description, which lets this music-only source reject the
  # venue's comedy and non-music programming.
  ORGANIZER_EVENTS_URL = "https://www.eventbrite.com/api/v3/organizers/68173536473/events/"
  EVENTBRITE_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
  TIME_ZONE = "America/Los_Angeles"
  NON_MUSIC_PATTERN = /\b(?:comedy|comedian|stand[- ]?up|open mic|trivia|quiz|workshop|class|meeting|private event)\b/i
  MUSIC_PATTERN = /\b(?:music|live|band|dj(?:s)?|karaoke|concert|jazz|blues|reggae|dub|rock|hip[ -]?hop|disco|funk|soul|motown|bluegrass|americana|swing|sinatra|house)\b/i

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
      url = "#{ORGANIZER_EVENTS_URL}?status=live&expand=venue,logo&order_by=start_asc"
      JSON.parse(URI.open(url, "User-Agent" => EVENTBRITE_USER_AGENT, "Accept" => "application/json").read).
        fetch("events", []).
        select { |event| parse_date(event).to_date >= current_pacific_date }.
        sort_by { |event| parse_date(event) }
    end

    def parse_event_data(event, &foreach_event_blk)
      return unless macs_venue_event?(event)
      return unless music_event?(event)

      title = event.dig("name", "text").to_s.strip
      return if title.blank?

      {
        url: event.fetch("url"),
        img: event.dig("logo", "original", "url") || event.dig("logo", "url") || "",
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
      Time.find_zone!(event.dig("start", "timezone") || TIME_ZONE).parse(event.dig("start", "local")).to_datetime
    end

    def current_pacific_date
      Time.current.in_time_zone(TIME_ZONE).to_date
    end

    def macs_venue_event?(event)
      venue = event["venue"] || {}
      address = venue["address"] || {}

      venue.fetch("name", "").include?("Mac's at 19 Broadway") &&
        address["address_1"] == "19 Broadway" &&
        address["city"] == "Fairfax" &&
        address["region"] == "CA"
    end

    def music_event?(event)
      text = [event.dig("name", "text"), event["summary"], event.dig("description", "text")].compact.join(" ")
      !text.match?(NON_MUSIC_PATTERN) && text.match?(MUSIC_PATTERN)
    end
  end
end
