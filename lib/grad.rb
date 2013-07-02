#!/usr/bin/ruby

require 'thread'
require 'logger'
require 'getoptlong'
require 'grad/log_reader'
require 'grad/launcher'
require 'grad/pic'
require 'grad/processor'
require 'grad/watcher'
require 'grad/dashboard'

module Grad

  def self.main

    # read options
    #
    opts = GetoptLong.new(
      [ '--continual', '-c', GetoptLong::NO_ARGUMENT ],
      [ '--dummy', '-d', GetoptLong::NO_ARGUMENT ],
      [ '--file',  '-f', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--format', '-F', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
      [ '--host_header', '-H', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--picture', '-p', GetoptLong::NO_ARGUMENT ],
      [ '--regex', '-r', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--verbose', '-v', GetoptLong::NO_ARGUMENT ]
    )
    opts.each do |opt, arg|
      case opt
      when '--continual'
        @continual = true
      when '--dummy'
        $dummy = true
      when '--file'
        @read_file = arg
      when '--format'
        @format = arg
      when '--regex'
        @regex = arg
      when '--help'
        puts <<-HELP
grad [OPTIONS] HOST[:PORT]

Options:
-c|--continual
  keep reading input even when there is no data
  useful when used with tools like varnishreplay

-d|--dummy:
  dryrun

-f|--file <file>:
  file to read log from
  otherwise reads STDIN, i.e 
    cat apache.log | grad localhost:80
    and
    grad -f apache.log localhost:80
  do same thing

-F|--format <format>:
  specify log format string
  for 'common' and 'combined' formats names can be used as following:
  -F %combined
  or:
  -F "%combined %w"
  or:
  -F "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\""

-h|--help:
  show help

-H|--host_header <host>
  set Host header to <host>

-l|--logto </log/to/file>
  output log file

-p|--picture:
  print ascii picture of Grad BM-21

-r|--regex <regex>:
  filter logs by regex

      HELP
      exit 0
      when '--host_header'
        @host_header = arg
      when '--logto'
        @log_dst = arg
      when '--picture'
        Grad::Pic.print
        exit 0
      when '--verbose'
        @log_level = 'DEBUG'
      end
    end

    # set host, port, format, regex and start_time
    #
    @host, @port = $*[0].split(':')
    ARGV.delete_at(0)
    @port ||= '80'
    @format ||= nil
    @regex ||= nil
    @host_header ||= nil
    @host_header_lock = false
    @continual ||= false
    @debug ||= false
    @log_dst ||= '/tmp/grad.log'
 
    # set logger
    #
    @log_level ||= 'DEBUG'
    @log = Logger.new(@log_dst)
    @log.level = Object.const_get('Logger').const_get(@log_level)
    @log.info "=== Grad started run ===" 

    # check if host is presented
    #
    unless @host
      @log.fatal 'Host is missing'
      exit 2
    end

    # set up launcher:
    # - input_q   : parsed log entries go here
    # - run_q     : jobs add themself to this queue when start running and remove themself on completion
    # - results_q : job results saved here 
    # - failed_q  : failed jobs saved here 
    @input_q_max = 1000
    @run_q_max  = 1000
    @launcher = Grad::Launcher.new
    @launcher.log  = @log
    @launcher.host = @host
    @launcher.port = @port
    @log.info "Target: #{@host}:#{@port}, #{'Host header: ' + @host_header if @host_header_lock}" 

    # setup input device 
    #
    input_dev = File.open(@read_file, 'r') if @read_file
    input_dev ||= ARGF

    # setup log parser
    #
    log_parser = Grad::LogReader.new(@format)
    log_parser.regex = @regex
    log_parser.log = @log
    log_parser.host_header = @host_header
    @log.info "Log format: #{log_parser.format}"

    # run log parser
    #
#    Thread.niew do
#      input_dev.each_line do |line|
#        until @launcher.input_q.size < input_q_max
#          sleep 1
#        end
#        line_parsed = log_parser.read_line(line)
#        @launcher.input_q.push(line_parsed) if line_parsed
#      end
#    end
    Thread.new do
      until input_dev.eof?
        if @launcher.input_q.size > @input_q_max
          sleep 0.2
          next
        end
        line_parsed = log_parser.read_line(input_dev.readline)
        @launcher.input_q.push(line_parsed) if line_parsed
      end
    end

    # run launcher
    #
    sleep 1 
    Thread.new { @launcher.run_jobs }

    # setup watcher to start collecting stats 
    # add lancher object for watcher to get access to lancher queues
    #
    grad_watcher = Grad::Watcher.new
    grad_watcher.launcher = @launcher
    sleep 1

    # setup dashboard
    #
    grad_dashboard = Grad::Dashboard.new(grad_watcher)
    grad_dashboard.host = @host
    grad_dashboard.port = @port
    grad_dashboard.host_header = @host_header
    grad_dashboard.format = log_parser.format
    grad_dashboard.log_src = @read_file ? @read_file : 'STDIN'
    grad_dashboard.log_dst = @log_dst

    interrupted = false
    trap("INT") { interrupted = true }
    begin
      while true
        abort if interrupted
        # keep checking in order until all queues are done - input_q and run_q
        if @launcher.input_q.empty? and @launcher.run_q.empty? and not @continual
          grad_dashboard.power_off
          @log.info "All queues are done."
          break
        end
        grad_dashboard.print_out
        sleep 2
#        Grad::Processor.print_graph(@launcher.results_q)
      end
    rescue SystemExit
      grad_dashboard.power_off
      @log.info 'Interrupted. Finishing run.'
    end

    until @launcher.results_q.empty?
      @log.info @launcher.results_q.pop
    end
    puts "Logs recorded to #{@log_dst}"
  end
end
