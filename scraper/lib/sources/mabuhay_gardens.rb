require "cgi"
require "nokogiri"
require "open-uri"

class MabuhayGardens
  MAIN_URL = "https://themab.org/"
  EVENTS_URL = "https://themab.org/events/"
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    get_events.first(events_limit).filter_map do |event|
      parse_event_data(event, &foreach_event_blk)
    end
  end

  class << self
    private

    def get_events
      html = URI.open(EVENTS_URL, "User-Agent" => "Mozilla/5.0").read
      doc = Nokogiri::HTML(html)
      doc.css("article[data-upcoming-event][data-date]").
        select { |event| Date.iso8601(event["data-date"]) >= Time.find_zone!(TIME_ZONE).today }
    end

    def parse_event_data(event, &foreach_event_blk)
      data = {
        url: parse_url(event),
        img: normalize_url(event.at_css("img[src]")&.[]("src")),
        date: parse_date(event),
        title: normalize_text(event.at_css(".upcoming-title")&.text),
        details: ""
      }

      return if data[:title].blank?

      data.
        tap { |event_data| Utils.print_event_preview(self, event_data) }.
        tap { |event_data| foreach_event_blk&.call(event_data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_url(event)
      normalize_url(event.at_css("a.upcoming-title[href]")&.[]("href")) || MAIN_URL
    end

    def parse_date(event)
      date = Date.iso8601(event["data-date"])
      time = parse_time(event)
      Time.find_zone!(TIME_ZONE).local(date.year, date.month, date.day, time[:hour], time[:minute]).to_datetime
    end

    def parse_time(event)
      time_text = normalize_text(event.at_css(".upcoming-date > span")&.text)[/\A\d{1,2}(?::\d{2})?\s*[AP]M\z/i]
      return { hour: 12, minute: 0 } if time_text.blank?

      time = Time.find_zone!(TIME_ZONE).parse(time_text)
      { hour: time.hour, minute: time.min }
    end

    def normalize_url(url)
      return nil if url.blank? || url.start_with?("#")
      return "https:#{url}" if url.start_with?("//")
      return URI.join(MAIN_URL, url).to_s if url.start_with?("/")

      url
    end

    def normalize_text(value)
      CGI.unescapeHTML(Nokogiri::HTML.fragment(value.to_s).text).
        gsub(/[\u2013\u2014]/, "-").
        gsub(/\u2022/, ",").
        gsub(/[[:space:]]+/, " ").
        strip
    end
  end
end
