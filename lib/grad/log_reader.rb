require 'apachelogregex'
require 'time'
require 'uri'

module Grad; class LogReader
  attr_accessor :regex, :log, :host_header
  attr_reader :format_common, :format_combined, :format

  def initialize(format = nil)
    @format_common = '%h %l %u %t \"%r\" %>s %b'
    @format_combined = '%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"'
    case format
    when /%combined/
      @format = format.gsub(/%combined/, @format_combined)
    when /%common/
      @format = format.gsub(/%common/, @format_common)
    when nil
      @format = @format_combined
    else
      @format = format
    end
    @parser = ApacheLogRegex.new(@format)
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
        host_header = @host_header ? @host_header : uri.hostname
        return { :uri => "#{uri.path}#{uri.query}", :resp => entry_resp, :t => entry_offset, :host_header => host_header, :raw => line }
      else
        return nil
      end
    rescue Exception => e
      @log.error "Failed to read line: \"#{line}\", #{e.message}"
      return nil
    end
  end

end; end

