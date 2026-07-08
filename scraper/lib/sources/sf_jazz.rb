require "faraday"
require "uri"

class SfJazz
  MAIN_URL = "https://www.sfjazz.org/calendar/"
  MIRROR_PREFIX = "https://r.jina.ai/http://"
  DEFAULT_IMG = "https://ybgfestival.org/wp-content/uploads/2014/03/sfjazz-logo-21-300x300-300x300.jpg"
  CALENDAR_MONTHS_AHEAD = 12
  MIRROR_RETRY_STATUSES = [429, 500, 502, 503, 504].freeze
  MIRROR_MAX_ATTEMPTS = 3
  MIRROR_WORKERS = 4

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    fetch_events.first(events_limit).map do |event|
      parse_event_data(event, &foreach_event_blk)
    end.compact
  end

  class << self
    private

    def fetch_events
      fetch_calendar_markdowns.flat_map { |markdown| extract_calendar_events(markdown) }.
        select { |event| event[:date].to_date >= Date.today }.
        sort_by { |event| event[:date] }.
        uniq { |event| [event[:url], event[:date], event[:title]] }
    rescue Faraday::Error => e
      raise "SfJazz mirror request failed: #{e.message}"
    end

    def fetch_calendar_markdowns
      urls = calendar_urls
      results = Array.new(urls.length)
      errors = Queue.new
      jobs = Queue.new
      urls.each_with_index { |url, index| jobs << [index, url] }

      [MIRROR_WORKERS, urls.length].min.times.map do
        Thread.new do
          loop do
            index, url = jobs.pop(true)
            results[index] = fetch_markdown(url)
          rescue ThreadError
            break
          rescue => e
            errors << e
            break
          end
        end
      end.each(&:join)

      raise errors.pop unless errors.empty?

      results.compact
    end

    def calendar_urls
      ([Date.today] + (1..CALENDAR_MONTHS_AHEAD).map { |month| Date.today.next_month(month).beginning_of_month }).
        map { |date| "#{MAIN_URL}?date=#{date.iso8601}&layout=A" }
    end

    def parse_event_data(event, &foreach_event_blk)
      title = event[:title].to_s.strip
      return if title.blank?

      {
        url: absolutize_url(event[:url].presence || MAIN_URL),
        img: absolutize_url(event[:img].presence || DEFAULT_IMG),
        date: event[:date],
        title: title.gsub(/\s{2,}/, " "),
        details: event[:details].to_s.strip
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def fetch_markdown(url)
      response = nil
      MIRROR_MAX_ATTEMPTS.times do |attempt|
        response = Faraday.get("#{MIRROR_PREFIX}#{url}") do |req|
          req.options.timeout = 20
          req.options.open_timeout = 10
          req.headers["accept"] = "text/plain, text/markdown;q=0.9, */*;q=0.8"
        end

        break if response.success? || !MIRROR_RETRY_STATUSES.include?(response.status)

        sleep(2**attempt)
      end

      unless response.success?
        raise "SfJazz mirror returned #{response.status} for #{url}"
      end

      response.body
    end

    def extract_calendar_events(markdown)
      current_date = nil
      current_title = nil
      year = Date.today.year

      markdown.lines.map(&:strip).filter_map do |line|
        date_text = line[/\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+[A-Z][a-z]{2}\s+\d{1,2}\b/]
        if date_text.present?
          current_date = DateTime.parse("#{date_text} #{year}")
          current_date = current_date.next_year if current_date.to_date < Date.today - 31
          current_title = line[%r{#### \[([^\]]+)\]\(https://www\.sfjazz\.org/[^)]+\)}, 1]
          next
        end

        match = line.match(%r{\[!\[Image \d+(?:: [^\]]+)?\]\((https://www\.sfjazz\.org/media/[^)]+)\)\]\((https://www\.sfjazz\.org/[^)]+)\)})
        next unless match && current_date

        img, url = match.captures
        {
          url: url,
          img: img,
          date: current_date,
          title: current_title.presence || title_from_url(url),
          details: details_from_url(url)
        }
      end
    end

    def title_from_url(url)
      slug = URI(url).path.split("/").reject(&:blank?).last.to_s
      slug.tr("-", " ").squish.titleize
    rescue
      "SFJAZZ Event"
    end

    def details_from_url(url)
      return "At Home" if url.include?("/athome/")
      return "Education" if url.include?("/education/")

      ""
    end

    def absolutize_url(url)
      URI.join(MAIN_URL, url).to_s
    rescue
      url
    end
  end
end
