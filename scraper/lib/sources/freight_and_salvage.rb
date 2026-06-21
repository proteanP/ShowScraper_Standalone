require "faraday"
require "open3"

class FreightAndSalvage
  MAIN_URL = "https://thefreight.org/shows/"
  MIRROR_URL = "https://r.jina.ai/http://https://thefreight.org/"

  cattr_accessor :events_limit, :load_time
  self.events_limit = 200
  self.load_time = 2

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    fetch_events.first(events_limit).map do |event|
      parse_event_data(event, &foreach_event_blk)
    end.compact
  end

  class << self
    private

    def fetch_events
      upcoming_section = fetch_markdown.split("## Upcoming Shows\n", 2)[1].to_s

      upcoming_section
        .split(/\n(?=\[!\[Image )/)
        .filter_map { |block| parse_event_block(block) }
    end

    def fetch_markdown
      output, status = Open3.capture2("curl", "-sL", "--max-time", "25", MIRROR_URL)
      raise "FreightAndSalvage mirror fetch failed" unless status.success?
      raise "FreightAndSalvage mirror did not include Upcoming Shows" unless output.include?("## Upcoming Shows")

      output
    end

    def parse_event_block(block)
      return if block.blank?
      return if block.include?("CANCELED")

      img, url = block.match(/\[!\[Image \d+\]\((.*?)\)\]\((https:\/\/[^)]+)\)/m)&.captures
      title = block[/## \[(.*?)\]\(https:\/\/[^)]+\)/m, 1].to_s.strip
      date_match = block.match(/^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\s+([A-Za-z]{3})\s+(\d{1,2})(?:st|nd|rd|th)\s+(\d{4}).*?Show:\s*(\d{1,2}:\d{2}\s*[AP]M)/m)

      return if title.blank? || date_match.blank?

      _weekday, month, day, year, show_time = date_match.captures
      date = DateTime.parse("#{month} #{day} #{year} #{show_time}")

      {
        date: date,
        img: img.to_s,
        title: title,
        url: url,
        details: ""
      }
    end

    def parse_event_data(event, &foreach_event_blk)
      {
        date: event[:date],
        img: event[:img],
        title: event[:title],
        url: event[:url],
        details: event[:details]
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end
  end
end
