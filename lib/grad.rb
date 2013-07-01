#!/usr/bin/ruby

require 'thread'
require 'logger'
require 'getoptlong'
require 'curses'
require 'grad/log_reader'
require 'grad/launcher'
require 'grad/pic'
require 'grad/processor'
require 'grad/monitor'

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
      [ '--header', '-H', GetoptLong::REQUIRED_ARGUMENT ],
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

-H|--header "<name>: <value>"
  set header

-p|--picture:
  print ascii picture of Grad BM-21

-r|--regex <regex>:
  filter logs by regex

      HELP
      exit 0
      when '--header'
        @header = arg 
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
    @continual ||= false
    @debug ||= false
 
    # set logger
    #
    log_dst ||= STDERR
    @log_level ||= 'WARN'
    @log = Logger.new(log_dst)
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

    # read input and populate @input_q 
    #
    input_dev = File.open(@read_file, 'r') if @read_file
    input_dev ||= ARGF
    @log.info "Host: #{@host}, Input: #{input_dev}, Regex: #{@regex}, Header: #{@header}"

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

    # keep checking in order until all queues are done - input_q and run_q
    #
    gm = Grad::Monitor.new
    sleep 2
    Curses.init_screen

    interrupted = false
    trap("INT") { interrupted = true }
    begin
      while true
        abort if interrupted
        if @launcher.input_q.empty? and @launcher.run_q.empty? and not @continual
          Curses.close_screen
          sleep 1
          @log.info "All queues are done."
          break
        end
        Curses.setpos(0, 0)
        Curses.addstr("=============== Grad ===============\n")
        Curses.addstr("\nGrad vehicle stats>\n")

        # print load average stats
        Curses.addstr("load average: #{gm.loadavg[:min1]}, #{gm.loadavg[:min5]}, #{gm.loadavg[:min15]}\n")

        # print cpu stats
        Curses.addstr("Cpu(s): \
#{gm.cpu[:us]}%us, \
#{gm.cpu[:sy]}%sy, \
#{gm.cpu[:ni]}%ni, \
#{gm.cpu[:id]}%id, \
#{gm.cpu[:wa]}%wa, \
#{gm.cpu[:hi]}%hi, \
#{gm.cpu[:si]}%si, \
#{gm.cpu[:st]}%st\n")

        # print network stats
        Curses.addstr("Network: #{gm.network[:tcp_conn]} tcp total, #{gm.network[:tcp_conn_port]} tcp port #{@port} total\n")

        # print memory stats
        mem_u = gm.memory[:units]
        gm.memory[:m_total] >= gm.memory[:s_total] ? l = gm.memory[:m_total].to_s.length : l = gm.memory[:s_total].to_s.length
        m_used_p    = l - gm.memory[:m_used].to_s.length
        m_free_p    = l - gm.memory[:m_free].to_s.length
        m_buffers_p = l - gm.memory[:m_buffers].to_s.length
        s_used_p    = l - gm.memory[:s_used].to_s.length
        s_free_p    = l - gm.memory[:s_free].to_s.length
        s_cached_p  = l - gm.memory[:s_cached].to_s.length
        Curses.addstr("Mem:  \
#{gm.memory[:m_total]}#{mem_u} total, \
#{' '*m_used_p}#{gm.memory[:m_used]}#{mem_u} used, \
#{' '*m_free_p}#{gm.memory[:m_free]}#{mem_u} free, \
#{' '*m_buffers_p}#{gm.memory[:m_buffers]}#{mem_u} buffers\n")
        Curses.addstr("Swap: \
#{gm.memory[:s_total]}#{mem_u} total, \
#{' '*s_used_p}#{gm.memory[:s_used]}#{mem_u} used, \
#{' '*s_free_p}#{gm.memory[:s_free]}#{mem_u} free, \
#{' '*s_cached_p}#{gm.memory[:s_cached]}#{mem_u} cached\n")

        Curses.addstr("\nGrad launcher stats>\n")
        Curses.addstr("Input_Q: #{@launcher.input_q.size}, Run_Q: #{@launcher.run_q.size}\n")
        Curses.addstr("\nGrad target stats>\n")
        Curses.refresh
        sleep 2

#        Grad::Processor.print_graph(@launcher.results_q)
      end
    rescue SystemExit
      Curses.close_screen
      sleep 1
      @log.info 'Interrupted. Finishing run.'
    end

    until @launcher.results_q.empty?
      puts @launcher.results_q.pop
    end
  end

end
