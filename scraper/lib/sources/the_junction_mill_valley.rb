require "cgi"
require "nokogiri"
require "open-uri"

class TheJunctionMillValley
  MAIN_URL = "https://thejunc.simpletix.com/"
  MILL_VALLEY_PATTERN = /\bmill\s+vall(?:ey|ay)\b/i

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    doc = Nokogiri::HTML(URI.open(MAIN_URL, "User-Agent" => "Mozilla/5.0").read)

    doc.css("#showlist .list-box:not(.archieved)").each_with_object([]) do |event, events|
      break events if events.count >= events_limit

      data = parse_event_data(event, &foreach_event_blk)
      events << data if data
    end
  end

  class << self
    private

    def parse_event_data(event, &foreach_event_blk)
      title = clean_text(event.at_css(".st_event_list_display_body_event_title")&.text)
      return unless title.match?(MILL_VALLEY_PATTERN)

      date = parse_date(event.at_css(".event_date_time")&.text)
      return if date < Date.today.to_datetime

      {
        url: event.at_css("a.links")&.[]("href").to_s,
        img: image_url(event.at_css(".event_image")&.[]("style")),
        date: date,
        title: title,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date(value)
      date_text = clean_text(value).split(" - ").first
      DateTime.strptime(date_text, "%m/%d/%Y %I:%M %p")
    end

    def image_url(style)
      style.to_s[/url\((['\"]?)(.*?)\1\)/, 2].to_s
    end

    def clean_text(value)
      CGI.unescapeHTML(value.to_s).gsub(/[[:space:]]+/, " ").strip
    end
  end
end
