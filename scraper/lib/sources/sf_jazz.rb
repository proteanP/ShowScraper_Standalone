require "faraday"
require "json"
require "nokogiri"
require "uri"

class SfJazz
  # SFJAZZ's calendar is Cloudflare-blocked from this runtime. Outgoing's
  # server-rendered SFJAZZ listing is the approved aggregator fallback.
  MAIN_URL = "https://www.outgoing.world/activity/sfjazz-47d3f4ff1bb8"
  OFFICIAL_CALENDAR_URL = "https://www.sfjazz.org/calendar/"
  JINA_PREFIX = "https://r.jina.ai/http://"
  DEFAULT_IMG = "https://ybgfestival.org/wp-content/uploads/2014/03/sfjazz-logo-21-300x300-300x300.jpg"
  OUTGOING_PROVENANCE = "Listed by Outgoing (SFJAZZ calendar fallback)."
  JINA_PROVENANCE = "Listed by the SFJAZZ calendar via Jina Reader."

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
      return official_calendar_events unless response.success?

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
      official_calendar_events
    end

    def official_calendar_events
      # The date/layout route is Cloudflare-challenged through Jina Reader,
      # while the month route retains the official calendar's featured events.
      url = "#{JINA_PREFIX}#{OFFICIAL_CALENDAR_URL}?month=#{Date.today.strftime('%-m.%Y')}"
      response = Faraday.get(url) do |req|
        req.options.timeout = 30
        req.options.open_timeout = 10
      end
      raise "SfJazz official calendar fallback returned #{response.status}" unless response.success?

      events = []
      current_date = nil
      response.body.lines.map(&:strip).each_with_index do |line, index|
        if (match = line.match(/^([A-Z]{3}) (\d{1,2})(?:[–-](\d{1,2}))?, (\d{4})$/))
          month, start_day, end_day, year = match.captures
          current_date = DateTime.parse("#{month} #{end_day || start_day}, #{year}")
          next
        end

        match = line.match(%r{^\[([^\]]+)\]\((https://www\.sfjazz\.org/tickets/productions/[^)]+)\)$})
        next unless match && current_date && current_date.to_date >= Date.today
        next if match[1] == "Buy Tickets"

        image = response.body.lines[index, 8].to_a.join[/!\[[^\]]*\]\((https:\/\/www\.sfjazz\.org\/media\/[^)]+)\)/, 1]
        events << {
          url: match[2],
          img: image.presence || DEFAULT_IMG,
          date: current_date,
          title: match[1],
          details: JINA_PROVENANCE
        }
      end

      raise "SfJazz official calendar fallback did not contain upcoming events" if events.empty?

      events.uniq { |event| [event[:url], event[:date], event[:title]] }.sort_by { |event| event[:date] }
    rescue Faraday::Error => e
      raise "SfJazz official calendar fallback request failed: #{e.message}"
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
