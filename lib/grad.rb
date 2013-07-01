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
      [ '--header_host', '-H', GetoptLong::REQUIRED_ARGUMENT ],
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

-h|--help:
  show help

-H|--header_host <host>
  set Host header to <host>

-l|--logto </log/to/file>
  output log file

-p|--picture:
  print ascii picture of Grad BM-21

-r|--regex <regex>:
  filter logs by regex

      HELP
      exit 0
      when '--header_host'
        @header_host = arg
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
    @header_host ||= nil
    @continual ||= false
    @debug ||= false
    @log_dst ||= '/tmp/grad.log'
 
    # set logger
    #
    @log_level ||= 'DEBUG'
    @log = Logger.new(@log_dst)
    @log.level = Object.const_get('Logger').const_get(@log_level)

    # check if host is presented
    #
    unless @host
      @log.fatal 'Host is missing'
      exit 2
    end

    # set up launcher:
    # - input_q   : parsed log entries go here
    # - run_q     : scheduled jobs add themself to this queue when start running and remove themself on completion
    # - results_q : job results saved here 
    @launcher = Grad::Launcher.new
    @launcher.log  = @log
    @launcher.host = @host
    @launcher.port = @port
    @launcher.header_host = @header_host 

    # read input and populate @input_q 
    #
    input_dev = File.open(@read_file, 'r') if @read_file
    input_dev ||= ARGF
    log_parser = Grad::LogReader.new
    log_parser.regex = @regex
    log_parser.log = @log
    Thread.new do
      input_dev.each_line do |line|
        until @launcher.input_q.size < 1000
          sleep 1
        end
        line_parsed = log_parser.read_line(line)
        @launcher.input_q.push(line_parsed) if line_parsed
      end
    end

    # activate launcher 
    #
    sleep 1 
    Thread.new do
      while sleep 0.5 do
        until @launcher.input_q.empty?
          @launcher.run_job
        end
      end
    end

    # setup watcher to start collecting stats 
    # add lancher object for watcher to get access to lancher queues
    #
    grad_watcher = Grad::Watcher.new
    grad_watcher.launcher = @launcher
    sleep 2

    # setup dashboard
    #
    grad_dashboard = Grad::Dashboard.new(grad_watcher)
    grad_dashboard.host = @host
    grad_dashboard.port = @port
    grad_dashboard.header_host = @header_host
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
