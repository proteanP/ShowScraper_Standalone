require "cgi"
require "nokogiri"
require "open-uri"

class TheLostChurch
  MAIN_URL = "https://thelostchurch.org/san-francisco/"
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    fetch_events.first(events_limit).filter_map do |event|
      parse_event_data(event, &foreach_event_blk)
    end
  end

  class << self
    private

    def fetch_events
      html = URI.open(MAIN_URL, "User-Agent" => "Mozilla/5.0").read
      doc = Nokogiri::HTML(html)

      doc.css(".performances_performance").filter_map do |node|
        title = parse_title(node)
        url = node.at_css(".buy a, .read a")&.[]("href").to_s
        month = node.at_css(".calendar .month")&.text
        day = node.at_css(".calendar .day")&.text
        year = node.at_css(".calendar .year")&.text

        next if title.blank? || url.blank? || month.blank? || day.blank? || year.blank?

        {
          title: title,
          url: url,
          img: parse_image(node),
          date: parse_date(month, day, year)
        }
      end
    end

    def parse_event_data(event, &foreach_event_blk)
      {
        url: event.fetch(:url),
        img: event.fetch(:img),
        date: event.fetch(:date),
        title: event.fetch(:title),
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_title(node)
      normalize_text(node.at_css(".title")&.text).
        sub(/\s+-\s+(?:San Francisco|SF)\z/i, "")
    end

    def parse_image(node)
      style = node.at_css(".performances_performance_image")&.[]("style").to_s
      CGI.unescapeHTML(style[/background:\s*url\(([^)"]+)/i, 1].to_s)
    end

    def parse_date(month, day, year)
      date = Date.parse("#{month} #{day}, #{year}")

      # The official SF event list omits start times. Noon in venue local time
      # preserves the Pacific calendar date when serialized downstream.
      Time.find_zone!(TIME_ZONE).local(date.year, date.month, date.day, 12, 0).to_datetime
    end

    def normalize_text(value)
      CGI.unescapeHTML(value.to_s).
        tr("\u2013\u2014", "-").
        gsub(/[[:space:]]+/, " ").
        strip
    end
  end
end
