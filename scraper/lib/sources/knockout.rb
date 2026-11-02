require "faraday"
require "json"

class Knockout
  # Squarespace calendar block; its month feed is public JSON, so no browser needed.
  MAIN_URL = "https://theknockoutsf.com/calendar2"
  API_URL = "https://theknockoutsf.com/api/open/GetItemsByMonth"
  COLLECTION_ID = "668dcda020574371451c8e12"
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :months_limit, :events_limit
  self.months_limit = 3
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    events = []
    today = Time.find_zone!(TIME_ZONE).today

    months_limit.times do |offset|
      fetch_month(today >> offset).each do |event|
        break if events.count >= events_limit

        data = parse_event_data(event, &foreach_event_blk)
        events << data if data.present?
      end
      break if events.count >= events_limit
    end

    events
  end

  class << self
    private

    def fetch_month(month)
      response = Faraday.get(API_URL, { month: month.strftime("%m-%Y"), collectionId: COLLECTION_ID },
                             { "accept" => "application/json", "referer" => MAIN_URL })
      raise "Knockout calendar request failed (#{response.status})" unless response.success?

      items = JSON.parse(response.body)
      # Squarespace answers an unknown collection id with lorem-ipsum sample events.
      raise "Knockout calendar returned placeholder data; collection id changed?" if items.any? { |e| e["systemDataId"] == "PLACEHOLDER" }

      items.sort_by { |event| event.dig("structuredContent", "startDate").to_i }
    rescue JSON::ParserError => e
      raise "Knockout invalid JSON response: #{e.message}"
    end

    def parse_event_data(event, &foreach_event_blk)
      title = event["title"].to_s.squish
      return if title.blank?

      {
        date: parse_date(event),
        url: "https://theknockoutsf.com#{event['fullUrl']}",
        title: title,
        img: event["assetUrl"].to_s,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date(event)
      ms = event.dig("structuredContent", "startDate")
      raise "Knockout missing event date" if ms.blank?

      Time.find_zone!(TIME_ZONE).at(ms / 1000).to_datetime
    end
  end
end
