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
      [ '--format', '-F', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
      [ '--host_header', '-H', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--log', '-l', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--limit', '-L', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--mock', '-m', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--output', '-o', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--picture', '-p', GetoptLong::NO_ARGUMENT ],
      [ '--regex', '-r', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--skip', '-s', GetoptLong::NO_ARGUMENT ],
      [ '--verbose', '-v', GetoptLong::NO_ARGUMENT ]
    )

    port   = '80'
    mock   = false
    skip   = false
    output = 'dash'
    regex  = nil
    limit  = nil
    logto  = '/tmp/grad.log'
    opts.each do |opt, arg|
      case opt
      when '--format'
        @format = arg
      when '--help'
        puts <<-HELP
grad [OPTIONS] HOST[:PORT]

Options:
-F|--format <format>
  specify log format string
  for 'common' and 'combined' formats names can be used as following:
  -F %combined
  or:
  -F "%combined %w"
  or:
  -F "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\""
  default value: combined

-h|--help
  show help

-H|--host_header <host>
  set Host header to <host>

-l|--log </log/to/file>
  output log file

-L|--limit <N>
  set a limit for max requests per second

-m|--mock
  dry run, don't hit the target, just log what would be replayed

-o|--output <dash|pipe>
  set output method. Default is 'dash'
  dash - dashboard, prints 'top' like screen during run
  pipe - pipe, prints entries from log as they are going through a log launcher

-p|--picture
  print ascii picture of Grad BM-21

-r|--regex <regex>
  filter logs by regex

-s|--skip
  skip delays
  by default Grad replays logs respecting time offsets in original log file
  --skip tells to replay logs as fast as possible
  NOTE: you may want to use --skip with --limit option

      HELP
      exit 0
      when '--host_header'
        @host_header = arg
      when '--log'
        logto = arg
      when '--limit'
        limit = arg.to_i
      when '--mock'
        mock = true
      when '--output'
        output = arg
      when '--picture'
        Grad::Pic.print
        exit 0
      when '--regex'
        regex = arg
      when '--skip'
        skip = true
      when '--verbose'
        @log_level = 'DEBUG'
      end
    end

    # set host and port
    #
    host, port = $*[0].split(':')
    port    ||= '80'
    ARGV.delete_at(0)

    # set default values
    #
    @debug   ||= false

    # set output
    #
    dash = pipe = nil
    case output 
    when 'dash'
      dash = true
    when 'pipe'
      pipe = true
    else
      log.fatal "#{output}: no support for output method"
      exit 2
    end

    # set logger
    #
    @log_level ||= 'DEBUG'
    log = Logger.new(logto)
    log.level = Object.const_get('Logger').const_get(@log_level)
    log.info "=== Grad started run ===" 

    # check if host is presented
    #
    unless host
      log.fatal 'Host is missing'
      exit 2
    end

    # set up launcher
    #
    launcher = Grad::Launcher.new(host, port, log, limit)
    launcher.mock = mock
    launcher.skip = skip
    launcher.pipe = pipe
    log.info "Target: #{host}:#{port}, #{"Host header: #@host_header, " if @host_header}, jobs_max: #{launcher.jobs_max}" 

    # setup log parser
    #
    log_reader = Grad::LogReader.new(@format)
    log_reader.regex = regex
    log_reader.log   = log
    log_reader.host_header = @host_header
    log.info "Log format: #{log_reader.format}"

    # start log reader
    #
    input_max = 1000
    reader = Thread.new do
      until ARGF.eof?
        if launcher.input_q.size <= input_max
          launcher.input_q.push(log_reader.read_line(ARGF.readline))
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
    if dash
      dashboard = Grad::Dashboard.new(watcher)
      dashboard.host = host
      dashboard.port = port
      dashboard.host_header = @host_header
      dashboard.format = log_reader.format
      dashboard.log_src = 'STDIN'
      dashboard.log_dst = logto
    end

    interrupted = false
    trap("INT") { interrupted = true }
    begin
      while sleep 2
        # abort if INT is sent
        #
        abort if interrupted

        # keep checking in order until all queues are done
        #
        if launcher.finished? && !reader.alive?
          log.info "All queues are done."
          break
        end

        # update dashboard screen
        #
        dashboard.print_out if dash
      end
    rescue SystemExit
      log.info 'Interrupted. Finishing run.'
    end
    dashboard.stop if dash
    launcher.stop

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
    puts "Logs recorded to #{logto}"
  end
end
