require "faraday"
require "json"
require "uri"

class SfJazz
  # The public calendar is Cloudflare-blocked from this runtime. Its calendar
  # app reads this first-party API, which Jina Reader can retrieve in full.
  OFFICIAL_SITE_URL = "https://www.sfjazz.org"
  OFFICIAL_CALENDAR_API_URL = "#{OFFICIAL_SITE_URL}/ace-api/events/"
  JINA_PREFIX = "https://r.jina.ai/http://"
  DEFAULT_IMG = "https://ybgfestival.org/wp-content/uploads/2014/03/sfjazz-logo-21-300x300-300x300.jpg"
  CALENDAR_PROVENANCE = "Listed by the SFJAZZ calendar API via Jina Reader."

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
      start_date = Date.today
      query = URI.encode_www_form(
        startDate: start_date.iso8601,
        endDate: (start_date >> 12).iso8601
      )
      # Jina Reader treats an unescaped ampersand as its own query separator.
      url = "#{JINA_PREFIX}#{OFFICIAL_CALENDAR_API_URL.delete_prefix('https://')}?#{query.gsub('&', '%26')}"
      response = Faraday.get(url) do |req|
        req.options.timeout = 30
        req.options.open_timeout = 10
      end
      raise "SfJazz official calendar API returned #{response.status}" unless response.success?

      events = calendar_events(response.body).filter_map do |event|
        date = DateTime.parse(event.fetch("eventDate"))
        detail_path = event.fetch("viewDetailCtaUrl")
        next if date.to_date < start_date || !detail_path.start_with?("/tickets/productions/")

        {
          url: URI.join(OFFICIAL_SITE_URL, detail_path).to_s,
          img: event["thumbnail"].presence ? URI.join(OFFICIAL_SITE_URL, event["thumbnail"]).to_s : DEFAULT_IMG,
          date: date,
          title: event.fetch("name"),
          details: CALENDAR_PROVENANCE
        }
      rescue ArgumentError, KeyError, URI::InvalidURIError
        nil
      end

      raise "SfJazz official calendar API did not contain upcoming events" if events.empty?

      events.uniq { |event| [event[:url], event[:date], event[:title]] }.sort_by { |event| event[:date] }
    rescue Faraday::Error, JSON::ParserError => e
      raise "SfJazz official calendar API request failed: #{e.message}"
    end

    def calendar_events(response_body)
      start_index = response_body.index("[{")
      end_index = response_body.rindex("}]")
      raise JSON::ParserError, "SfJazz calendar API did not return an event array" unless start_index && end_index

      JSON.parse(response_body[start_index..end_index + 1])
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
