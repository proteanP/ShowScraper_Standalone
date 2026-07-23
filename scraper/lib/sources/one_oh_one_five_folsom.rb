require "cgi"
require "json"
require "nokogiri"
require "open-uri"

class OneOhOneFiveFolsom
  MAIN_URL = "https://1015.com/"
  TICKETMASTER_VENUE_URL = "https://www.ticketmaster.com/1015-folsom-tickets-san-francisco/venue/338370"
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    timed_events = fetch_ticketmaster_event_times
    official_events = fetch_official_events
    official_date_counts = official_events.map { |event| event.fetch(:date) }.tally

    official_events.first(events_limit).filter_map do |event|
      parse_event_data(event, timed_events, official_date_counts, &foreach_event_blk)
    end
  end

  class << self
    private

    def fetch_official_events
      html = URI.open(MAIN_URL, "User-Agent" => "Mozilla/5.0").read
      doc = Nokogiri::HTML(html)

      doc.css(".nectar-hor-list-item").filter_map do |node|
        columns = node.css(".nectar-list-item").first(3).map { |item| normalize_text(item.text) }
        date_text, title, billing = columns
        next if date_text.blank? || title.blank?

        {
          date: parse_official_date(date_text),
          title: [title, billing].reject(&:blank?).join(" - "),
          url: node.at_css("a.nectar-list-item-btn")&.[]("href").presence || MAIN_URL
        }
      end
    end

    def fetch_ticketmaster_event_times
      html = URI.open(TICKETMASTER_VENUE_URL, "User-Agent" => "Mozilla/5.0").read
      scripts = Nokogiri::HTML(html).css('script[type="application/ld+json"]')

      scripts.flat_map { |script| parse_json_ld_events(script.text) }.
        select { |event| event["startDate"].present? }.
        group_by { |event| Date.parse(event.fetch("startDate")) }
    rescue OpenURI::HTTPError, JSON::ParserError
      {}
    end

    def parse_json_ld_events(json)
      payload = JSON.parse(json)
      json_ld_items(payload).select { |item| item["@type"] == "Event" }
    end

    def json_ld_items(payload)
      case payload
      when Array
        payload.flat_map { |item| json_ld_items(item) }
      when Hash
        [payload] + json_ld_items(payload["@graph"])
      else
        []
      end
    end

    def parse_event_data(event, timed_events, official_date_counts, &foreach_event_blk)
      {
        url: event.fetch(:url),
        img: "",
        date: parse_date(event, timed_events, official_date_counts),
        title: event.fetch(:title),
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date(event, timed_events, official_date_counts)
      official_date = event.fetch(:date)
      candidates = Array(timed_events[official_date])
      timed_event = match_timed_event(event.fetch(:title), candidates, official_date_counts.fetch(official_date))

      return parse_ticketmaster_datetime(timed_event.fetch("startDate")) if timed_event

      # 1015's official calendar omits start times for some shows. Noon in venue
      # local time preserves the official Pacific calendar date when serialized.
      local_time(official_date.year, official_date.month, official_date.day, 12, 0).to_datetime
    end

    def match_timed_event(title, candidates, official_events_on_date)
      return candidates.first if candidates.one? && official_events_on_date == 1

      normalized_title = comparable_title(title)
      candidates.find do |candidate|
        candidate_title = comparable_title(candidate["name"])
        normalized_title.include?(candidate_title) || candidate_title.include?(normalized_title)
      end
    end

    def parse_ticketmaster_datetime(value)
      date, time = value.split("T", 2)
      year, month, day = date.split("-").map(&:to_i)
      hour, minute = time.to_s.split(":").first(2).map(&:to_i)
      local_time(year, month, day, hour, minute).to_datetime
    end

    def parse_official_date(value)
      date_text = value.gsub(/(\d+)(st|nd|rd|th)\b/i, "\\1")
      parsed = Date.parse("#{date_text} #{Date.current.in_time_zone(TIME_ZONE).year}")
      today = Date.current.in_time_zone(TIME_ZONE).to_date
      parsed < today ? parsed.next_year : parsed
    end

    def local_time(year, month, day, hour, minute)
      Time.find_zone!(TIME_ZONE).local(year, month, day, hour, minute)
    end

    def comparable_title(value)
      normalize_text(value).downcase.gsub(/\b(?:ages?\s*)?21\+?\b/, "").gsub(/[^0-9a-z]+/, "")
    end

    def normalize_text(value)
      CGI.unescapeHTML(value.to_s).tr("\u2013\u2014", "-").gsub(/[[:space:]]+/, " ").strip
    end
  end
end
