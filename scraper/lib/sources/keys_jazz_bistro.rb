require "cgi"
require "json"
require "net/http"
require "nokogiri"

class KeysJazzBistro
  MAIN_URL = "https://keysjazzbistro.com/event-calendar/"
  CALENDAR_API_URL = "https://keysjazzbistro.com/wp-json/simple-events/calendar"
  TIME_ZONE = "America/Los_Angeles"

  cattr_accessor :events_limit, :months_limit
  self.events_limit = 200
  self.months_limit = 6

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    fetch_events.first(events_limit).map do |event|
      parse_event_data(event, &foreach_event_blk)
    end
  end

  class << self
    private

    def fetch_events
      months_to_fetch.
        flat_map { |date| parse_calendar_month(date) }.
        select { |event| event[:date] >= current_pacific_time }.
        uniq { |event| event[:url] }.
        sort_by { |event| event[:date] }
    end

    def months_to_fetch
      today = current_pacific_time.to_date
      month_start = Date.new(today.year, today.month, 1)
      (0...months_limit).map { |idx| month_start.next_month(idx) }
    end

    def parse_calendar_month(date)
      doc = Nokogiri::HTML(fetch_calendar_html(date))
      doc.css(".simple-events-calendar-month-mobile-events__mobile-day").flat_map do |day|
        date_text = day.at_css("time[datetime]")&.[]("datetime").to_s
        day.css("article.simple-events-calendar-month__calendar-event").filter_map do |article|
          parse_calendar_event(date_text, article)
        end
      end
    end

    def parse_calendar_event(date_text, article)
      link = article.at_css(".simple-events-calendar-month__calendar-event-title-link")
      time_text = article.at_css(".simple-events-calendar-month__calendar-event-datetime time")&.[]("datetime").to_s
      title = normalize_text(link&.[]("title").presence || link&.text)
      url = normalize_url(link&.[]("href"))
      return if date_text.blank? || time_text.blank? || title.blank? || url.blank?

      {
        url: url,
        img: parse_image(article),
        date: parse_date(date_text, time_text),
        title: title,
        details: ""
      }
    end

    def parse_event_data(event, &foreach_event_blk)
      event.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def fetch_calendar_html(date)
      uri = URI(CALENDAR_API_URL)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["User-Agent"] = "Mozilla/5.0"
      request.body = {
        date: date.strftime("%Y-%m-%d"),
        attributes: {
          eventModalAccess: true,
          showModalTitle: true,
          showModalExcerpt: true
        }
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
      unless response.is_a?(Net::HTTPSuccess)
        raise "KeysJazzBistro calendar request failed (#{response.code}): #{response.body}"
      end

      JSON.parse(response.body).fetch("html")
    rescue JSON::ParserError => e
      raise "KeysJazzBistro invalid calendar JSON response: #{e.message}"
    end

    def parse_image(article)
      image_url = article.xpath("following-sibling::*[1]//img").first&.[]("src").to_s
      normalize_url(image_url)
    end

    def parse_date(date_text, time_text)
      zone = Time.find_zone!(TIME_ZONE)
      zone.parse("#{date_text} #{time_text}").to_datetime
    end

    def current_pacific_time
      Time.current.in_time_zone(TIME_ZONE)
    end

    def normalize_url(url)
      return "" if url.blank?
      return "https://keysjazzbistro.com#{url}" if url.start_with?("/")
      url
    end

    def normalize_text(value)
      CGI.unescapeHTML(value.to_s).
        gsub(/[[:space:]]+/, " ").
        strip
    end
  end
end
