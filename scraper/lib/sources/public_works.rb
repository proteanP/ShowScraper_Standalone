class PublicWorks
  MAIN_URL = "https://publicsf.com/calendar/"
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
      $driver.navigate.to(MAIN_URL)
      $driver.css(".event-item")
    end

    def parse_event_data(event, &foreach_event_blk)
      title = event.css(".event-title")[0]&.text.to_s.squish
      date_text = event.css(".event-date")[0]&.text.to_s.squish
      return if title.blank? || date_text.blank?

      {
        date: parse_date(date_text),
        url: normalize_url(event.css("a[href]")[0]&.attribute("href")),
        title: title,
        details: "",
        img: normalize_url(event.css(".event-thumb img[src]")[0]&.attribute("src"))
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
