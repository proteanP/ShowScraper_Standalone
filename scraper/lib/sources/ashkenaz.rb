require "faraday"
require "json"

class Ashkenaz
  MAIN_URL = "https://www.ashkenaz.com/full-calendar"
  GRAPHQL_URL = "https://www.venuepilot.co/graphql"
  ACCOUNT_ID = 1228
  TIME_ZONE = "America/Los_Angeles"

  GRAPHQL_QUERY = <<~GRAPHQL.freeze
    query ($accountIds: [Int!]!, $startDate: String!, $endDate: String, $search: String, $searchScope: String, $limit: Int, $page: Int) {
      paginatedEvents(arguments: {accountIds: $accountIds, startDate: $startDate, endDate: $endDate, search: $search, searchScope: $searchScope, limit: $limit, page: $page}) {
        collection {
          id
          name
          date
          doorTime
          startTime
          promoter
          support
          description
          websiteUrl
          ticketsUrl
          announceImages {
            highlighted
            versions {
              thumb {
                src
              }
              cover {
                src
              }
            }
          }
        }
        metadata {
          totalPages
        }
      }
    }
  GRAPHQL

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    events = []
    page = 1
    total_pages = nil

    while total_pages.nil? || page <= total_pages
      payload = fetch_events_page(page: page)
      paginated = payload.fetch("data", {}).fetch("paginatedEvents", {})
      source_events = paginated.fetch("collection", [])
      total_pages = paginated.fetch("metadata", {}).fetch("totalPages", 1).to_i

      break if source_events.empty?

      source_events.each do |event|
        break if events.count >= events_limit

        data = parse_event_data(event, &foreach_event_blk)
        events << data if data.present?
      end

      break if events.count >= events_limit
      page += 1
    end

    events
  end

  class << self
    private

    def fetch_events_page(page:)
      response = Faraday.post(GRAPHQL_URL) do |req|
        req.headers["accept"] = "*/*"
        req.headers["content-type"] = "application/json"
        req.headers["origin"] = "https://www.ashkenaz.com"
        req.headers["referer"] = "#{MAIN_URL}#/events"
        req.body = {
          operationName: nil,
          variables: {
            accountIds: [ACCOUNT_ID],
            startDate: Time.find_zone!(TIME_ZONE).today.strftime("%Y-%m-%d"),
            endDate: nil,
            search: "",
            searchScope: "",
            page: page
          },
          query: GRAPHQL_QUERY
        }.to_json
      end

      raise "Ashkenaz GraphQL request failed (#{response.status}): #{response.body}" unless response.success?

      parsed = JSON.parse(response.body)
      raise "Ashkenaz GraphQL errors: #{parsed['errors'].to_json}" if parsed["errors"].present?

      parsed
    rescue JSON::ParserError => e
      raise "Ashkenaz invalid JSON response: #{e.message}"
    end

    def parse_event_data(event, &foreach_event_blk)
      title = parse_title(event)
      return if title.blank?

      {
        url: event_url(event),
        img: parse_image(event),
        date: parse_date(event),
        title: title,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_title(event)
      [event["promoter"], event["name"], event["support"]].
        map { |part| normalize_text(part) }.
        reject(&:blank?).
        join(", ")
    end

    def parse_date(event)
      date = event["date"].presence
      time = event["startTime"].presence || event["doorTime"].presence || "12:00:00"
      raise "Ashkenaz missing event date" if date.blank?

      Time.find_zone!(TIME_ZONE).parse("#{date} #{time}").to_datetime
    end

    def parse_image(event)
      images = Array(event["announceImages"])
      preferred = images.find { |img| img["highlighted"] } || images.first || {}
      preferred.dig("versions", "cover", "src").presence ||
        preferred.dig("versions", "thumb", "src").to_s
    end

    def event_url(event)
      id = event["id"].presence
      return "#{MAIN_URL}#/events/#{id}" if id

      event["ticketsUrl"].presence || event["websiteUrl"].presence || MAIN_URL
    end

    def normalize_text(value)
      value.to_s.gsub(/<[^>]+>/, " ").squish
    end
  end
end
