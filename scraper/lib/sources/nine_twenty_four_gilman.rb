require "nokogiri"
require "open-uri"

class NineTwentyFourGilman
  MAIN_URL = "https://app.showslinger.com/e1/460/924-gilman/8c96699fd6?is_embedded=true"
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    doc = Nokogiri::HTML(URI.open(MAIN_URL, "User-Agent" => "Mozilla/5.0").read)
    events = []

    doc.css(".shadow-sm-custom.list-layout-1").each do |event|
      break if events.count >= events_limit

      data = parse_event_data(event, &foreach_event_blk)
      events << data if data.present?
    end

    events
  end

  class << self
    private

    def parse_event_data(event, &foreach_event_blk)
      title = normalize_text(event.at_css(".widget-name")&.text)
      return if title.blank?

      date = parse_date(
        normalize_text(event.at_css(".widget-date-month")&.text),
        normalize_text(event.at_css(".widget-time")&.text)
      )
      return if date < Time.now.in_time_zone(TIME_ZONE).beginning_of_day.to_datetime

      price = normalize_text(event.at_css(".widget-price")&.text)
      {
        url: absolute_url(event.at_css("a.mrk_ticket_event_url")&.[]("href")),
        img: absolute_url(event.at_css("img.grid-img")&.[]("src")),
        date: date,
        title: title,
        details: price.present? ? "Price: #{price}" : ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date(date_text, time_text)
      raise "NineTwentyFourGilman missing date" if date_text.blank?

      zone = Time.find_zone!(TIME_ZONE)
      current_time = zone.now
      parsed = zone.parse([date_text, current_time.year, time_text.presence || "12:00 AM"].join(" "))
      parsed = parsed.advance(years: 1) if parsed < current_time.beginning_of_day
      parsed.to_datetime
    end

    def absolute_url(value)
      return "" if value.blank?

      URI.join(MAIN_URL, value.to_s).to_s
    end

    def normalize_text(value)
      value.to_s.squish
    end
  end
end
