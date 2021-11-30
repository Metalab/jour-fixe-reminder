#!/usr/bin/env ruby

require 'yaml'
require 'strscan'
require 'date'
require 'URI'
require 'open-uri'
require 'nokogiri'
require 'mail'

# The event struct used to hold the Event metadata which is then used to scrape
# events happening in the near future
Event = Struct.new(:name, :date, :url, :location)


# This function parses future events where SUMMARY:Jour Fixe and adds their corresponding
# metadata to an array of possible events
# This function uses the fact that the .ics file is ordered by date, in order future -> past,
# which it uses to short circuit the execution once we find an event in the past.
def parse_calendar(filename, events = ["Jour Fixe"])
  # String scanner lets us search a string in a fast manner using regex matches with captures
  # to extract metadata fast
  s = StringScanner.new(File.read(filename))

  jour_fixes = []

  loop do
    c = s.skip_until(/SUMMARY:Jour Fixe/)

    break if c.nil?

    jour_fixe = Event.new
    jour_fixe.name = 'Jour Fixe'

    # Dates are automatically parsed into Date objects for comparison
    s.scan_until(/DTSTART:(\w+)/)
    jour_fixe.date = DateTime.parse(s.captures[0])

    s.scan_until(/LOCATION:(\w+)/)
    jour_fixe.location = s.captures[0]

    # Turning the URL into a URI object needs to be done for scraping anyways,
    # might as well do it here.
    s.scan_until(/URL:(\S+)/)
    jour_fixe.url = URI.parse(s.captures[0])

    # Here we break the loop if we find a past event, as no more future events
    # will be found as the ics is sorted by date.
    if jour_fixe.date < Date.today
      break
    else
      jour_fixes.append(jour_fixe)
    end

  end

  jour_fixes
end


# generates a list of the form
# "- entry 1
#  - entry 2"
# or returns "None!\n" otherwise
def generate_list_string(xs, default_regex)
  xs_list = xs.inject ("") { |res, x|
    if default_regex =~ x
      res
    else
      res + "- " + x + "\n"
    end
  }

  xs_list.empty? ? "None!\n" : xs_list
end


# extract the h2 headings appearing after the h1 header identified by
# the identifier string, use a css resource identifier string for identifier
# the identifier should identify the span child of the h1, as the h1 does
# not have any identifiers in the mediawiki generated html, but the
# span element comes with an id tag set to the heading's contents
def extract_h2_after_h1(doc, identifier)
  # find the h1 heading corresponding to some identifier
  h1 = doc.at_css(identifier).parent
  working_node = h1.next_element
  h2s = []

  # iterate over all children until the next h1 heading
  while working_node.name != "h1"
    if working_node.name == "h2"
      h2s.append(working_node.text)
    end
    working_node = working_node.next_element
  end

  h2s
end


# this function scrapes the necessary data from the wiki page, return an array containing the
# strings to be interpolated in the message template
def jour_fixe_scraper(event)
  # use nokogiri to extract all h2 headings after certain h1 headings for "Berichte", "Themen" and "Protokoll"
  #first, fetch the HTML using nokogiri
  doc = Nokogiri::HTML(event.url.open)

  # here we extract the location information, as the one given in the
  # calendar is not always up to date
  location_heading =  doc.at_css("span#Ort").parent.next_element
  event.location = location_heading.search(":not(s)").text

  reports = extract_h2_after_h1(doc, "span#Berichte")
  topics = extract_h2_after_h1(doc, "span#Themen")

  # create a list of topics and reports, in plaintext with links stripped
  reports_list = generate_list_string(reports, /Bericht\d* \(you\)/)
  topics_list = generate_list_string(topics, /Thema\d* \(you\)/)

  [event.date.strftime("%A (%Y-%m-%d) at %H:%M"), event.location,
   reports_list, topics_list, event.url]
end


def main
  # load the config and set up the smtp client's data
  config = YAML.load_file('config.yml')
  Mail.defaults do
    delivery_method :smtp, config[:mail_options]
  end

  # fetch the current metalab event calendar
  # this function takes forever, as the calendar endpoint is slow (~10 seconds)
  URI.open(config[:calendar_endpoint]) do |res|
    IO.copy_stream(res, config[:local_filename])
  end

  # get all jour fixes that happen in the future
  jour_fixes = parse_calendar(config[:local_filename])

  # For each eligible event, check if the date is 3 days from now
  jour_fixes.each do |jour_fixe|
    if jour_fixe.date >= Date.today + 2 && jour_fixe.date < Date.today + 3

      # interpolate the (meta)data with the message template and send per mail
      message_body =  config[:message_template] % jour_fixe_scraper(jour_fixe)

      puts message_body

      Mail.deliver do
        to config[:recipient_address]
        from 'OwObot <%s>' % config[:sender_address]
        message_id '<jourfixe%s@owobot.reminder>' % jour_fixe.date.to_s
        subject "Metalab Jour Fixe Reminder"
        body message_body
      end
    end
  end

  # clean up after ourselves
  File.delete(config[:local_filename]) if File.exist? config[:local_filename]
end


if __FILE__ == $0
  main
end
