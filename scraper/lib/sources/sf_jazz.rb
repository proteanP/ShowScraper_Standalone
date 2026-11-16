require "faraday"
require "json"
require "nokogiri"

class SfJazz
  # sfjazz.org and Outgoing's SFJAZZ listing both answer with a Cloudflare
  # challenge from this runtime, so read Songkick's public SFJAZZ Center venue
  # pages (one per room) and their schema.org MusicEvent data instead.
  VENUE_URLS = [
    "https://www.songkick.com/venues/2222064-miner-auditorium-sfjazz-center",
    "https://www.songkick.com/venues/2588888-joe-henderson-lab-sfjazz-center",
    "https://www.songkick.com/venues/2020904-sfjazz-center"
  ].freeze
  DEFAULT_IMG = "https://ybgfestival.org/wp-content/uploads/2014/03/sfjazz-logo-21-300x300-300x300.jpg"
  PROVENANCE = "Listed by Songkick."

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
      events = VENUE_URLS.flat_map { |url| venue_events(url) }
      raise "SfJazz Songkick venue pages did not contain upcoming events" if events.empty?

      # Songkick often lists one show twice (e.g. "Brian Blade" and "Brian Blade
      # Fellowship") or once per set, so keep one event per room and day.
      events.
        sort_by { |event| [event[:date].to_date, event[:has_time] ? 0 : 1] }.
        uniq { |event| [event[:room], event[:date].to_date] }.
        sort_by { |event| event[:date] }
    end

    def venue_events(url)
      response = Faraday.get(url) do |req|
        req.options.timeout = 30
        req.options.open_timeout = 10
      end
      raise "SfJazz Songkick venue page returned #{response.status}" unless response.success?

      Nokogiri::HTML(response.body).css('script[type="application/ld+json"]').flat_map do |script|
        Array(JSON.parse(script.text))
      rescue JSON::ParserError
        []
      end.filter_map do |item|
        next unless item.is_a?(Hash) && item["@type"] == "MusicEvent"

        start = item.fetch("startDate")
        date = DateTime.parse(start)
        next if date.to_date < Date.today

        {
          url: item.fetch("url").sub(/\?.*\z/, ""),
          img: item["image"].presence || DEFAULT_IMG,
          date: date,
          title: item.fetch("name").sub(/\s+@\s+.*\z/, ""),
          details: PROVENANCE,
          room: item.dig("location", "name"),
          has_time: start.include?("T")
        }
      rescue ArgumentError, KeyError
        nil
      end
    rescue Faraday::Error => e
      raise "SfJazz Songkick venue page request failed: #{e.message}"
    end

    def parse_event_data(event, &foreach_event_blk)
      title = event[:title].to_s.strip
      return if title.blank?

      {
        url: event[:url],
        img: event[:img],
        date: event[:date],
        title: title.gsub(/\s{2,}/, " "),
        details: event[:details].to_s.strip
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end
  end
end
