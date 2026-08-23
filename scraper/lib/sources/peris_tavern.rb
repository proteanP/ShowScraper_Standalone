require "nokogiri"
require "open-uri"
require "json"

class PerisTavern
  SITE_URL = "https://peristavern.com/"
  CALENDAR_URL = "https://peristavern.com/music-calendar/"
  PLUGIN_URL = "https://plugin.vbotickets.com/Plugin/events/showevents"

  cattr_accessor :events_limit
  self.events_limit = 200

  def self.run(events_limit: self.events_limit, &foreach_event_blk)
    events = []
    music_events.each do |event|
      break if events.count >= events_limit

      result = parse_event_data(event, &foreach_event_blk)
      events << result if result
    end
    events
  end

  class << self
    private

    def music_events
      Nokogiri::HTML(URI.open(events_url, "User-Agent" => "Mozilla/5.0").read).
        css('.EventGridItem[data-event-category="Music"]')
    end

    def events_url
      site_id = calendar_content[/var SiteID = "([^"]+)"/, 1]
      raise "Peri's Tavern ticket site ID was not found" unless site_id

      loader = URI.open(
        "https://plugin.vbotickets.com/plugin/loadplugin?siteid=#{site_id}&page=ListEvents&w=1440&h=900",
        "User-Agent" => "Mozilla/5.0"
      ).read
      session_id = loader[/window\.location\.href = "[^"]*[?&]s=([^"]+)"/, 1]
      raise "Peri's Tavern ticket session was not found" unless session_id

      "#{PLUGIN_URL}?ViewType=grid&EventType=current&day=&s=#{session_id}"
    end

    def calendar_content
      JSON.parse(
        URI.open("#{SITE_URL}wp-json/wp/v2/pages?slug=music-calendar", "User-Agent" => "Mozilla/5.0").read
      ).first.dig("content", "rendered")
    end

    def parse_event_data(event, &foreach_event_blk)
      date = parse_date(event.at_css(".TextEventDate").text)
      return unless date && date.to_date >= Date.today

      event_id = event["id"]&.delete_prefix("EID")
      return unless event_id

      {
        url: "https://plugin.vbotickets.com/Plugin/event/details/#{event_id}",
        img: event.at_css(".PosterList")&.[]("src") || "",
        date: date,
        title: event.at_css(".HeaderEventName").text.strip,
        details: event.at_css(".EventIntroText").text.strip
      }.
        tap { |data| Utils.print_event_preview(self, data) }.
        tap { |data| foreach_event_blk&.call(data) }
    rescue => e
      ENV["DEBUGGER"] == "true" ? binding.pry : raise
    end

    def parse_date(date_text)
      text = date_text.strip
      if (match = text.match(/\A(?:\w{3},\s+)?(\d{1,2}\/\d{1,2}\/\d{4})\s+@\s+(.+)\z/))
        DateTime.strptime("#{match[1]} #{match[2]}", "%m/%d/%Y %I:%M %p")
      elsif (match = text.match(/\A(\d{1,2}\/\d{1,2}\/\d{4})\s+-\s+\1\z/))
        DateTime.strptime(match[1], "%m/%d/%Y")
      end
    end
  end
end
