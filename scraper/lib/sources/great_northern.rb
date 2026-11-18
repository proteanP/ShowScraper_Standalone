class GreatNorthern
  # Single page!!
  MAIN_URL = "https://www.thegreatnorthernsf.com"
  EVENTS_WAIT_TIMEOUT = 10

  cattr_accessor :events_limit, :load_time
  self.events_limit = 200
  self.load_time = 3

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    $driver.get(MAIN_URL)

    # The Eventbrite listing lives in an iframe and can load slowly.
    $driver.navigate.to embedded_events_url
    wait_for_events

    get_events.map.with_index do |event, index|
      next if index >= events_limit
      parse_event_data(event, &foreach_event_blk)
    end.compact
  end

  class << self
    private

    def embedded_events_url
      wait.until do
        $driver.css("iframe").map { |frame| frame.attribute("src") }.find(&:present?)
      end
    end

    def get_events
      $driver.css(".event.row")
    end

    def wait_for_events
      wait.until { get_events.any? }
    end

    def wait
      Selenium::WebDriver::Wait.new(timeout: EVENTS_WAIT_TIMEOUT)
    end

    def parse_event_data(event, &foreach_event_blk)
      date = DateTime.parse(event.css(".date")[0].text)
      # The listing omits the year, so dates that already passed belong to next year.
      date = date.next_year if date < DateTime.now - 1

      {
        date: date,
        img: event.css(".logo img")[0]&.attribute("src"),
        title: event.css(".title")[0].text,
        url: event.css(".title a")[0].attribute("href"),
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end
  end
end
