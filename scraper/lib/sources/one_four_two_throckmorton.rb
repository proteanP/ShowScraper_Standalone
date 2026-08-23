require "date"
require "nokogiri"
require "open-uri"

class OneFourTwoThrockmorton
  MAIN_URL = "https://www.throckmortontheatre.org/events"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    doc = Nokogiri::HTML(URI.open(MAIN_URL, "User-Agent" => "Mozilla/5.0").read)

    doc.css("article.eventlist-event--upcoming").each_with_object([]) do |event, events|
      data = parse_event_data(event, &foreach_event_blk)
      events << data if data
      break events if events.count >= events_limit
    end
  end

  class << self
    private

    def parse_event_data(event, &foreach_event_blk)
      title = event.at_css(".eventlist-title")&.text&.strip
      excerpt = event.at_css(".eventlist-excerpt")&.text.to_s.gsub(/\s+/, " ").strip
      return unless title.present?

      date = event.at_css(".event-date")&.[]("datetime")
      time = event.at_css(".event-time-localized-start")&.text&.strip
      return unless date.present? && Date.parse(date) >= Date.today

      {
        url: absolute_url(event.at_css(".eventlist-title a")&.[]("href")),
        img: event.at_css(".eventlist-column-thumbnail img")&.[]("data-image").to_s,
        date: DateTime.parse([date, time].compact.join(" ")),
        title: title,
        details: excerpt
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def absolute_url(url)
      return MAIN_URL if url.blank?
      return "https://www.throckmortontheatre.org#{url}" if url.start_with?("/")

      url
    end
  end
end
