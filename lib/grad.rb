#!/usr/bin/ruby

require 'thread'
require 'logger'
require 'getoptlong'
require 'grad/log_reader'
require 'grad/launcher'
require 'grad/pic'
#require 'grad/processor'
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
  default value: combined

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
    @port      ||= '80'
    @continual ||= false
    @debug     ||= false
    @log_dst   ||= '/tmp/grad.log'
 
    # set logger
    #
    @log_level ||= 'DEBUG'
    log = Logger.new(@log_dst)
    log.level = Object.const_get('Logger').const_get(@log_level)
    log.info "=== Grad started run ===" 

    # check if host is presented
    #
    unless @host
      log.fatal 'Host is missing'
      exit 2
    end

    # setup input device 
    #
    if @read_file
      unless File.exist?(@read_file)
        log.fatal "#@read_file: file not found"
        exit 2
      end
      input_dev = File.open(@read_file, 'r')
    else
      input_dev ||= ARGF
    end

    # set up launcher
    #
    launcher = Grad::Launcher.new
    launcher.log  = log
    launcher.host = @host
    launcher.port = @port
    log.info "Target: #{@host}:#{@port}, #{'Host header: ' + @host_header if @host_header}" 

    # setup log parser
    #
    log_reader = Grad::LogReader.new(@format)
    log_reader.regex = @regex
    log_reader.log = log
    log_reader.host_header = @host_header
    log.info "Log format: #{log_reader.format}"

    # start log reader
    #
    input_max = 1000
    Thread.new do
      until input_dev.eof?
        if launcher.input_q.size <= input_max
          launcher.input_q.push(log_reader.read_line(input_dev.readline))
        else
          log.info "Reader asleep for 1 sec"
          sleep 1
        end
      end
    end
    log.info "Started reader"

    # start launcher
    #
    sleep 1
    launcher.start 
    log.info "Started launcher"

    # setup watcher to start collecting stats 
    # add lancher object for watcher to get access to lancher queues
    #
    watcher = Grad::Watcher.new
    watcher.launcher = launcher
    sleep 1

    # setup dashboard
    #
    dashboard = Grad::Dashboard.new(watcher)
    dashboard.host = @host
    dashboard.port = @port
    dashboard.host_header = @host_header
    dashboard.format = log_reader.format
    dashboard.log_src = @read_file ? @read_file : 'STDIN'
    dashboard.log_dst = @log_dst

    interrupted = false
    trap("INT") { interrupted = true }
    begin
      while true
        abort if interrupted

        # keep checking in order until all queues are done - input_q and run_q
        #
        if launcher.finished? && !@continual
          dashboard.power_off
          launcher.stop
          log.info "All queues are done."
          break
        end
        dashboard.print_out
        sleep 2
      end
    rescue SystemExit
      dashboard.power_off
      launcher.stop
      log.info 'Interrupted. Finishing run.'
    end

    # log successful
    #
    log.info "Successful (#{launcher.done_q.size}):"
    until launcher.done_q.empty?
      log.info launcher.done_q.pop
    end

    # log failed
    #
    log.info "Failed (#{launcher.fail_q.size}):"
    until launcher.fail_q.empty?
      log.info launcher.fail_q.pop
    end
    puts "Logs recorded to #{@log_dst}"
  end
end
