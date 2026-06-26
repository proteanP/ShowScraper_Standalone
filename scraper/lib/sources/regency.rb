require "json"
require "open-uri"

class Regency
  # No pagination needed here, all events shown at once.
  MAIN_URL = "https://www.theregencyballroom.com/shows/"
  EVENTS_URL = "https://aegwebprod.blob.core.windows.net/json/events/9/events.json"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    events = []
    get_events.each do |event|
      next if events.count >= events_limit
      result = parse_event_data(event, &foreach_event_blk)
      next unless result
      events.push result
    end
    events
  end

  class << self
    private

    def get_events
      JSON.parse(URI.open(EVENTS_URL).read).fetch("events", [])
    end

    def parse_event_data(event, &foreach_event_blk)
      date = event["eventDateTimeISO"] || event["eventDateTimeUTC"] || event["eventDateTime"] || return
      title = event.dig("title", "eventTitleText") || event.dig("title", "headlinersText") || return
      {
        date: DateTime.parse(date),
        url: event_url(event),
        img: event_image(event),
        title: title,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def event_url(event)
      event_id = event["eventId"] || event["id"]
      return event.dig("ticketing", "eventUrl") if event_id.blank?
      "https://www.theregencyballroom.com/events/detail?event_id=#{event_id}"
    end

    def event_image(event)
      media = event["media"] || event["relatedMedia"] || {}
      images = media.is_a?(Hash) ? media.values : Array(media)
      images.find { |item| item.is_a?(Hash) && item["file_name"].present? }&.fetch("file_name", nil)
    end
  end
end
