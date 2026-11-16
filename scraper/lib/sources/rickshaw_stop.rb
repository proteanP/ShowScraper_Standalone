require "net/http"
require "nokogiri"

class RickshawStop
  # rickshawstop.com blocks the scraper (403), so read the venue's own
  # ticketing white-label page on SeeTickets/Eventim instead.
  MAIN_URL = "https://wl.eventim.us/RickshawStop"
  PAGE_SIZE = 12

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    get_events(events_limit).map do |event|
      parse_event_data(event, &foreach_event_blk)
    end.compact
  end

  class << self
    private

    def get_events(events_limit)
      events = []
      cookies = {}
      url = MAIN_URL
      while url && events.length < events_limit
        document = Nokogiri::HTML(fetch(url, cookies))
        page = document.css(".search-event")
        break if page.empty?
        events.concat(page)
        url = next_page_url(document, events.length)
      end
      events.first(events_limit)
    end

    # Later pages need the session cookies set by the first page.
    def fetch(url, cookies, redirects = 5)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Cookie"] = cookies.map { |k, v| "#{k}=#{v}" }.join("; ") if cookies.any?
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
      Array(response.get_fields("set-cookie")).each do |cookie|
        name, value = cookie.split(";", 2).first.split("=", 2)
        cookies[name] = value
      end
      if response.is_a?(Net::HTTPRedirection) && redirects > 0
        return fetch(URI.join(url, response["location"]).to_s, cookies, redirects - 1)
      end
      response.value
      response.body
    end

    # Pagination links offset by "_lfv" (events already shown).
    def next_page_url(document, offset)
      link = document.css("a[href*='_lfv=#{offset}']").first
      link && URI.join(MAIN_URL, link["href"]).to_s
    end

    def parse_event_data(event, &foreach_event_blk)
      link = event.at_css(".get-tickets-overlay a[aria-label]")
      return if link.blank?

      title = event.at_css(".event-name")&.text&.strip
      return if title.blank?

      # aria-label: "Buy tickets for <title> on November 18 2026"
      date_str = link["aria-label"][/ on (\w+ \d{1,2} \d{4})\z/, 1]
      return if date_str.blank?

      {
        date: DateTime.parse(date_str),
        img: event.at_css(".img-holder img")&.[]("src").to_s,
        title: title,
        url: URI.join(MAIN_URL, link["href"]).to_s,
        details: ""
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end
  end
end
