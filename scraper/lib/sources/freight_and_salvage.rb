require "faraday"
require "json"
require "nokogiri"

class FreightAndSalvage
  MAIN_URL = "https://secure.thefreight.org/events?view=list"
  API_URL = "https://secure.thefreight.org/api/products/productionseasons"

  cattr_accessor :events_limit, :load_time
  self.events_limit = 200
  self.load_time = 2

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    fetch_events.first(events_limit).map do |event|
      parse_event_data(event, &foreach_event_blk)
    end.compact
  end

  class << self
    private

    def fetch_events
      fetch_productions.flat_map do |production|
        Array(production["performances"]).filter_map do |performance|
          next unless performance["isPerformanceVisible"]

          parse_event(production, performance)
        end
      end
    end

    def fetch_productions
      response = Faraday.post(API_URL) do |req|
        req.headers["RequestVerificationToken"] = fetch_request_verification_token
        req.headers["Content-Type"] = "application/json"
        req.headers["Accept"] = "application/json"
        req.body = JSON.generate(
          startDate: Date.today.strftime("%Y-%m-%dT00:00"),
          endDate: Date.today.next_year.strftime("%Y-%m-%dT23:59"),
          keywords: []
        )
      end

      raise "FreightAndSalvage API fetch failed: #{response.status}" unless response.success?

      data = JSON.parse(response.body)
      data.is_a?(Hash) ? data.fetch("productions", []) : data
    end

    def fetch_request_verification_token
      response = Faraday.get(MAIN_URL)
      raise "FreightAndSalvage list page fetch failed: #{response.status}" unless response.success?

      token = Nokogiri::HTML(response.body).at_css('input[name="__RequestVerificationToken"]')&.[]("value")
      raise "FreightAndSalvage request verification token missing" if token.blank?

      token
    end

    def parse_event(production, performance)
      {
        date: DateTime.parse(performance["performanceDate"] || performance["iso8601DateString"]),
        img: production["listingImageUrl"].to_s,
        title: extract_title(performance),
        url: performance["actionUrl"].presence || production["productionSeasonActionUrl"],
        details: ""
      }
    end

    def extract_title(performance)
      Nokogiri::HTML.fragment(performance["performanceTitle"].to_s)
        .xpath(".//text()")
        .map(&:text)
        .join(" ")
        .gsub(/\s+/, " ")
        .strip
    end

    def parse_event_data(event, &foreach_event_blk)
      {
        date: event[:date],
        img: event[:img],
        title: event[:title],
        url: event[:url],
        details: event[:details]
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end
  end
end
