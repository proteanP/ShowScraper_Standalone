require "open-uri"
require "nokogiri"

class Fillmore
  cattr_accessor :events_limit
  self.events_limit = 200

  MAIN_URL = "https://www.livenation.com/venue/KovZpZAE6eeA/the-fillmore-events"

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    get_events.map.with_index do |event, index|
      next if index >= events_limit
      parse_event_data(event, &foreach_event_blk)
    end.compact
  end

  class << self
    private

    def get_events
      document = Nokogiri::HTML(URI.open(MAIN_URL))
      document.css("[role='group']").select do |box|
        box.at_css("time[datetime]") && box.at_css("h2, .chakra-heading")
      end
    end

    def parse_event_data(event, &foreach_event_blk)
      date = DateTime.parse(event.at_css("time[datetime]")["datetime"].split("/").first) rescue nil
      return if date.blank?

      title = event.at_css("h2, .chakra-heading")&.text&.strip
      return if title.blank?

      link = event.at_css("a[href]")&.[]("href")
      link = MAIN_URL if link.blank?

      {
        date: date,
        url: link,
        img: parse_img(event),
        title: title,
        details: "",
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_img(event)
      img = event.at_css("img")&.[]("src").to_s
      return "" if img.blank?

      URI.join(MAIN_URL, img).to_s
    rescue
      ""
    end
  end
end
