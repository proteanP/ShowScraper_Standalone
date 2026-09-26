require "faraday"
require "json"
require "nokogiri"
require "uri"

class SfJazz
  # SFJAZZ's calendar is Cloudflare-blocked from this runtime. Outgoing's
  # server-rendered SFJAZZ listing is the approved aggregator fallback.
  MAIN_URL = "https://www.outgoing.world/activity/sfjazz-47d3f4ff1bb8"
  DEFAULT_IMG = "https://ybgfestival.org/wp-content/uploads/2014/03/sfjazz-logo-21-300x300-300x300.jpg"
  OUTGOING_PROVENANCE = "Listed by Outgoing (SFJAZZ calendar fallback)."

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
      response = Faraday.get(MAIN_URL) do |req|
        req.options.timeout = 30
        req.options.open_timeout = 10
      end
      raise "SfJazz Outgoing request returned #{response.status}" unless response.success?

      document = Nokogiri::HTML(response.body)
      events = outgoing_events(document)
      official_urls = outgoing_official_urls(document)

      events.each_with_index.filter_map do |event, index|
        date = DateTime.parse(event.fetch("startDate"))
        next if date.to_date < Date.today

        {
          url: official_urls[index].presence || event.fetch("url"),
          img: event["image"].presence || DEFAULT_IMG,
          date: date,
          title: event.fetch("name"),
          details: [OUTGOING_PROVENANCE, event["description"]].compact.join(" ")
        }
      rescue ArgumentError, KeyError
        nil
      end.uniq { |event| [event[:url], event[:date], event[:title]] }.sort_by { |event| event[:date] }
    rescue Faraday::Error => e
      raise "SfJazz Outgoing request failed: #{e.message}"
    end

    def outgoing_events(document)
      script = document.at_css("script#activity-jsonld")
      raise "SfJazz Outgoing listing did not contain event data" unless script

      JSON.parse(script.text).fetch("@graph").select { |item| item["@type"] == "Event" }
    rescue JSON::ParserError, KeyError => e
      raise "SfJazz Outgoing event data could not be parsed: #{e.message}"
    end

    def outgoing_official_urls(document)
      document.css("script").filter_map do |script|
        payload = script.text[/self\.__next_f\.push\((.*)\)\z/m, 1]
        JSON.parse(payload)[1] if payload
      rescue JSON::ParserError
        nil
      end.join.scan(/"direct_booking_urls":(\[[^\]]*\])/).map do |urls|
        JSON.parse(urls.first).find { |url| URI(url).host == "www.sfjazz.org" }
      rescue JSON::ParserError, URI::InvalidURIError
        nil
      end
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
