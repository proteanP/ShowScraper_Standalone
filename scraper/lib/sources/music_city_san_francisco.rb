require 'json'
require 'open-uri'

class MusicCitySanFrancisco
  ORGANIZER_EVENTS_URL = "https://www.eventbrite.com/api/v3/organizers/12803819712/events/"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    events = []
    page = 1

    loop do
      response = fetch_events_page(page)
      response.fetch("events", []).each do |event|
        break if events.count >= events_limit

        data = parse_event_data(event, &foreach_event_blk)
        events.push(data) if data
      end

      break if events.count >= events_limit
      break unless response.dig("pagination", "has_more_items")

      page += 1
    end

    events
  end

  class << self
    private

    def fetch_events_page(page)
      url = "#{ORGANIZER_EVENTS_URL}?status=live&expand=venue,logo&order_by=start_asc&page=#{page}"
      JSON.parse(URI.open(url).read)
    end

    def parse_event_data(event, &foreach_event_blk)
      return unless music_city_venue_event?(event)
      return unless live_show?(event)
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
      if event.dig("start", "local").present?
        zone = Time.find_zone!(event.dig("start", "timezone") || "America/Los_Angeles")
        zone.parse(event.dig("start", "local")).to_datetime
      else
        DateTime.parse(event.dig("start", "utc")).in_time_zone("America/Los_Angeles").to_datetime
      end
    end

    def music_city_venue_event?(event)
      venue = event["venue"] || {}
      venue_name = venue.fetch("name", "").downcase
      address = [
        venue.dig("address", "address_1"),
        venue.dig("address", "city"),
        venue.dig("address", "region")
      ].compact.join(" ").downcase

      venue_name.include?("music city") &&
        address.include?("san francisco") &&
        (address.include?("1355 bush") || address.include?("1353 bush"))
    end

    def live_show?(event)
      title = event.dig("name", "text").to_s.downcase
      summary = event["summary"].to_s.downcase
      text = "#{title} #{summary}"

      return false if text.match?(/hall of fame|gallery|guided tour|industry meetup/)

      text.match?(/live|show|concert|band|dj|open mic|pro jam|karaoke|performance|performer|tribute/)
    end
  end
end
