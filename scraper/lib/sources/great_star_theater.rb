require 'nokogiri'
require 'open-uri'

class GreatStarTheater
  MAIN_URL = "https://www.greatstartheater.org/whats-playing"
  TIME_ZONE = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    doc = Nokogiri.parse(URI.open(MAIN_URL).read)
    events = []

    get_events(doc).each do |event|
      break if events.count >= events_limit
      data = parse_event_data(event, &foreach_event_blk)
      events.push(data) if data
    end

    events
  end

  class << self
    private

    def get_events(doc)
      doc.css(".event-list-item.event-list-element")
    end

    def parse_event_data(event, &foreach_event_blk)
      title = parse_title(event)
      return if title.blank? || event["href"].blank?

      start_time, end_time = parse_date_range(event)
      return if start_time.blank? || end_time.blank?
      return if end_time.to_date < today_in_pacific

      {
        url: absolute_url(event["href"]),
        img: parse_img(event),
        date: start_time,
        title: title,
        details: parse_details(event)
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_title(event)
      event.at("h3")&.text&.squish
    end

    def parse_img(event)
      src = event.at("img")&.attribute("src")&.value
      src.present? ? absolute_url(src) : ""
    end

    def parse_details(event)
      event.at(".event-desc")&.text&.squish || ""
    end

    def parse_date_range(event)
      date_text = event.at(".event-time")&.text&.squish
      return [nil, nil] if date_text.blank?

      start_date_text, end_date_text = expand_date_range(date_text)
      [
        parse_in_pacific(start_date_text),
        parse_in_pacific(end_date_text)
      ]
    end

    def expand_date_range(date_text)
      normalized = date_text.gsub(/[–—]/, "-").gsub(/\s+/, " ").strip
      year = normalized[/\b(\d{4})\b/, 1]
      return [normalized, normalized] if year.blank?

      no_year = normalized.sub(/,?\s*#{year}\b/, "").strip
      parts = no_year.split(/\s*(?:-|&|and)\s*/, 2)
      return [normalized, normalized] if parts.length == 1

      start_part, end_part = parts
      month = start_part[/\A([A-Za-z]+)/, 1]
      end_part = "#{month} #{end_part}" unless end_part.match?(/[A-Za-z]/)

      ["#{start_part}, #{year}", "#{end_part}, #{year}"]
    end

    def parse_in_pacific(date_text)
      TIME_ZONE.parse(date_text).to_datetime
    end

    def today_in_pacific
      TIME_ZONE.now.to_date
    end

    def absolute_url(url)
      URI.join(MAIN_URL, url).to_s
    end
  end
end
