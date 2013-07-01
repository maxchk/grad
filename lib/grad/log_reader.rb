require 'apachelogregex'
require 'time'
require 'uri'

module Grad; class LogReader
  attr_accessor :regex, :log

  def initialize(format = nil)
    format ||= '%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\" %w'
    @parser = ApacheLogRegex.new(format)
  end

  def read_line(line)
    begin
      p_line = @parser.parse line
      entry_time = Time.strptime(p_line['%t'], "[%d/%b/%Y:%H:%M:%S %Z]").to_i
      entry_uri  = p_line['%r'].gsub(/(GET|POST) | HTTP\/.*/,'')
      entry_resp = p_line['%>s']
      @start_time ||= entry_time
      entry_offset = entry_time - @start_time
      uri = URI::parse(entry_uri)
      if uri.path[/#{@regex}/]
        @log.debug "Found match: #{entry_uri} =~ #{@regex}"
        return {:uri => entry_uri, :resp => entry_resp, :t => entry_offset} 
      else
        return nil
      end
    rescue Exception => e
      @log.error "Failed to read line: #{e.message}"
      return nil
    end
  end

end; end

