class HopMonkNovato
  MAIN_URL = "https://wl.eventim.us/HopMonkNovato"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    $driver.navigate.to(MAIN_URL)

    $driver.css(".search-event").first(events_limit).filter_map do |event|
      parse_event_data(event, &foreach_event_blk)
    end
  end

  class << self
    private

    def parse_event_data(event, &foreach_event_blk)
      return unless event.css(".event-location")[0]&.text&.include?("Novato, CA")

      {
        url: URI.join(MAIN_URL, event.css("a[href*='/event/']")[0].attribute("href")).to_s,
        img: event.css("img")[0]&.attribute("src") || "",
        date: parse_date(event.css(".event-date")[0].text),
        title: event.css(".event-name")[0].text,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date(date_str)
      date = DateTime.parse("#{date_str}, #{Date.today.year}")
      date.to_date < Date.today ? date >> 12 : date
    end
  end
end
