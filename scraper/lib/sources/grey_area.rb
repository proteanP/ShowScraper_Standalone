class GreyArea
  MAIN_URL = "https://grayarea.org/events/"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    get_events.each.map.with_index do |event, index|
      next if index >= events_limit
      parse_event_data(event, &foreach_event_blk)
    end.reject(&:blank?)
  end

  class << self
    private

    def get_events
      $driver.navigate.to(MAIN_URL)
      $driver.css(".featured-items")[0].css(".item-link")
    end

    def parse_event_data(event, &foreach_event_blk)
      date = DateTime.parse(event.css(".date")[0].text) rescue return
      # Dates are listed as "MM/DD" with no year; roll past dates into next year.
      date = date.next_year if date < DateTime.now - 30
      title = event.css(".item-title")[0]&.text
      return if title.blank?
      {
        img: parse_img(event),
        title: title,
        url: event.attribute("href"),
        date: date,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_img(event)
      style = event.css(".image")[0]&.attribute("style")
      return "" unless style
      style.scan(/url\(([^)]+)\)/)[0][0]
    end
  end
end
