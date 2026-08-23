require "date"
require "open-uri"
require "rss"
require "nokogiri"

class CoyoteCalendar
  # Coyote publishes one calendar post each week. The tag RSS feed is more stable
  # than an individual weekly-post URL and keeps this source browser-free.
  MAIN_URL = "https://www.coyotemedia.org/tag/calendar/rss/"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    events = []
    get_sections.each do |date, section, image|
      section.element_children.select { |child| child.name == "li" }.each do |event|
        break if events.count >= events_limit

        result = parse_event_data(date, event, image, &foreach_event_blk)
        events << result if result
      end
      break if events.count >= events_limit
    end
    events
  end

  class << self
    private

    def get_sections
      post = RSS::Parser.parse(URI.open(MAIN_URL, "User-Agent" => "Mozilla/5.0").read, false).items.first
      return [] unless post

      start_date, end_date = parse_date_range(post.title)
      return [] unless start_date && end_date

      doc = Nokogiri::HTML(post.content_encoded)
      # Each day has a banner image followed by that day's list. Calendar posts
      # are written chronologically, so the post title supplies the actual dates.
      doc.css("img.kg-image").each_with_index.filter_map do |image, index|
        date = start_date + index
        break if date > end_date
        section = image.parent.next_element
        next unless section&.name == "ul"
        [date, section, image["src"]]
      end
    end

    def parse_event_data(date, event, image, &foreach_event_blk)
      title = event.at("strong")&.text&.strip
      url = event.css("a").find { |link| link.text.strip.casecmp?("more info") }&.[]("href")
      return unless title.present? && url.present? && date >= Date.today

      {
        url: url,
        img: image || "",
        date: date.to_datetime,
        title: title,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date_range(title)
      match = title.match(/COYOTE Calendar:\s+([A-Za-z]+)\s+(\d+)\s*-\s*(?:([A-Za-z]+)\s+)?(\d+)/i)
      return unless match

      start_month, start_day, end_month, end_day = match.captures
      year = Date.today.year
      start_date = Date.parse("#{start_month} #{start_day}, #{year}")
      end_date = Date.parse("#{end_month || start_month} #{end_day}, #{year}")
      end_date = end_date.next_year if end_date < start_date
      [start_date, end_date]
    end
  end
end
