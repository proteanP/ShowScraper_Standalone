require 'nokogiri'
require 'open-uri'
require 'time'

class ThePlanetarium
  MAIN_URL = "https://ragtagshows.com/"
  VENUE_PATTERN = /at\s+the\s+planetarium/i
  ADDRESS_PATTERN = /5327\s+Jacuzzi\s+St/i
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    doc = Nokogiri.parse(URI.open(MAIN_URL).read)
    get_events(doc).each_with_object([]) do |event, events|
      break events if events.count >= events_limit

      result = parse_event_data(event, &foreach_event_blk)
      events.push(result) if result
    end
  end

  class << self
    private

    def get_events(doc)
      doc.css("#calendar .event")
    end

    def parse_event_data(event, &foreach_event_blk)
      description_text = event.css(".event-description").text
      return unless planetarium_event?(description_text)

      date = parse_date(description_text)
      return if date < DateTime.now

      {
        url: parse_url(event),
        img: absolute_url(event.at_css(".flyer-image")&.attribute("src")&.value.to_s),
        date: date,
        title: clean_text(event.at_css("h3")&.text),
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def planetarium_event?(description_text)
      description_text.match?(VENUE_PATTERN) && description_text.match?(ADDRESS_PATTERN)
    end

    def parse_url(event)
      ticket_link = event.css(".event-description a[href]").find do |link|
        link.attribute("href").value.match?(%r{\Ahttps?://})
      end

      ticket_link ? ticket_link.attribute("href").value : MAIN_URL
    end

    def parse_date(description_text)
      date_line = description_lines(description_text).find { |line| line.match?(/\d{1,2}(st|nd|rd|th),\s+\d{4}/i) }
      doors_line = description_lines(description_text).find { |line| line.match?(/doors\s+open\s+at/i) }
      doors_time = doors_line.to_s[/doors\s+open\s+at\s+(.+)/i, 1]

      parse_pacific_time("#{date_line} #{doors_time}")
    end

    def description_lines(description_text)
      description_text.lines.map { |line| clean_text(line) }.reject(&:blank?)
    end

    def parse_pacific_time(value)
      original_tz = ENV["TZ"]
      ENV["TZ"] = TIME_ZONE
      Time.parse(value).to_datetime
    ensure
      ENV["TZ"] = original_tz
    end

    def absolute_url(value)
      value.blank? ? "" : URI.join(MAIN_URL, value).to_s
    end

    def clean_text(value)
      value.to_s.gsub(/\u00a0/, " ").squish
    end
  end
end
