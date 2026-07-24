require "cgi"
require "nokogiri"
require "open-uri"

class BoomBoomRoom
  MAIN_URL = "https://boomboomroom.com/events/"
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    events_limit ||= self.events_limit
    doc = Nokogiri::HTML(URI.open(MAIN_URL, "User-Agent" => "Mozilla/5.0").read)

    events = []
    doc.css(".eventWrapper.rhpSingleEvent.rhp-event__single-event--list").each do |event|
      break if events.count >= events_limit

      data = parse_event_data(event, &foreach_event_blk)
      events << data if data.present?
    end
    events
  end

  class << self
    private

    def parse_event_data(event, &foreach_event_blk)
      title = normalize_text(event.at_css("#eventTitle h2")&.text)
      return if title.blank?

      date = parse_date(
        normalize_text(event.at_css("#eventDate")&.text),
        normalize_text(event.at_css(".rhp-event__time-text--list")&.text)
      )
      return if date < current_pacific_time.beginning_of_day.to_datetime

      detail_url = normalize_url(event.at_css("a#eventTitle")&.[]("href"))
      ticket_url = normalize_url(event.at_css(".rhp-event-cta a[href]")&.[]("href"))

      {
        url: ticket_url.presence || detail_url,
        img: normalize_url(event.at_css(".rhp-events-event-image img")&.[]("src")),
        date: date,
        title: title,
        details: parse_details(event, detail_url)
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date(date_text, time_text)
      raise "BoomBoomRoom missing event date" if date_text.blank?

      show_time = time_text[/Show:\s*([^\/]+)/i, 1] || time_text[/Doors:\s*([^\/]+)/i, 1]
      parsed = time_zone.parse([date_text, current_pacific_time.year, show_time.presence || "12:00 PM"].join(" "))
      parsed = parsed.advance(years: 1) if parsed < current_pacific_time.beginning_of_day
      parsed.to_datetime
    end

    def parse_details(event, detail_url)
      [
        normalize_text(event.at_css(".eventAgeRestriction")&.text),
        normalize_text(event.at_css(".rhp-event__time-text--list")&.text),
        ("More Info: #{detail_url}" if detail_url.present?)
      ].compact_blank.join(". ")
    end

    def normalize_url(value)
      return "" if value.blank?

      URI.join(MAIN_URL, value.to_s).to_s
    end

    def normalize_text(value)
      CGI.unescapeHTML(value.to_s).squish
    end

    def current_pacific_time
      Time.current.in_time_zone(TIME_ZONE)
    end

    def time_zone
      Time.find_zone!(TIME_ZONE)
    end
  end
end
