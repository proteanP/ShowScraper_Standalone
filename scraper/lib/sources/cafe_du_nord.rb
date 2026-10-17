require "open-uri"
require "nokogiri"

class CafeDuNord
  MAIN_URL = "https://cafedunord.com/"

  cattr_accessor :events_limit
  self.events_limit = 200

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
      document.css("section.tonight-card[data-date], li.show-row[data-date]").select do |event|
        event.at_css(".room-tag--cdn")
      end
    end

    def parse_event_data(event, &foreach_event_blk)
      title = event.at_css(".tonight-card__headliner, .show-row__headliner")&.text&.strip
      return if title.blank?

      date = DateTime.parse(event.at_css("time[datetime]")["datetime"]) rescue nil
      return if date.blank?

      url = event.at_css(".tonight-card__headliner a, .show-row__headliner a")&.[]("href")
      return if url.blank?

      {
        date: date,
        img: event.at_css("img")&.[]("src").to_s,
        title: title,
        url: URI.join(MAIN_URL, url).to_s,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

  end
end
