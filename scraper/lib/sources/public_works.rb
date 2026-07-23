require "json"
require "nokogiri"
require "open-uri"

class PublicWorks
  MAIN_URL = "https://publicsf.com/calendar/"
  API_URL = "https://publicsf.com/wp-json/wp/v2/pages/2515"
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    events = []

    get_events.each do |event|
      break if events.count >= events_limit
      result = parse_event_data(event, &foreach_event_blk)
      events << result if result
    end

    events
  end

  class << self
    private

    def get_events
      response = URI.open(API_URL).read
      page = JSON.parse(response)
      html = page.dig("content", "rendered").to_s
      Nokogiri::HTML.fragment(html).css(".event-item")
    rescue JSON::ParserError => e
      raise "PublicWorks invalid JSON response: #{e.message}"
    end

    def parse_event_data(event, &foreach_event_blk)
      title = event.at_css(".event-title")&.text.to_s.squish
      date_text = event.at_css(".event-date")&.text.to_s.squish
      return if title.blank? || date_text.blank?

      {
        date: parse_date(date_text),
        url: normalize_url(event.at_css("a[href]")&.[]("href")),
        title: title,
        details: "",
        img: normalize_url(event.at_css(".event-thumb img[src]")&.[]("src"))
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date(date_text)
      zone = Time.find_zone!(TIME_ZONE)
      today = zone.today
      parsed = Date.strptime("#{date_text} #{today.year}", "%b %d %Y")
      parsed = parsed.next_year if parsed < today
      zone.local(parsed.year, parsed.month, parsed.day).to_datetime
    rescue ArgumentError
      raise "PublicWorks invalid event date: #{date_text}"
    end

    def normalize_url(url)
      return MAIN_URL if url.blank?
      return "https:#{url}" if url.start_with?("//")
      return "https://publicsf.com#{url}" if url.start_with?("/")
      url
    end
  end
end
