require 'thread'
require 'net/http'

module Grad; class Launcher
  attr_accessor :log, :host, :port, :host_header
  attr_reader :input_q, :run_q, :results_q, :failed_q

  def initialize
    @input_q   = Queue.new
    @run_q     = Queue.new
    @results_q = Queue.new
    @failed_q  = Queue.new
    @time_offset = 0
  end

  def run_jobs
    while true
      sleep_sec = 0     
      if @input_q.empty?
        sleep 0.2
        next
      end
      job = @input_q.pop
      job_run_in = job[:t].to_i
      @log.debug "URL: #{job[:uri]}, Hit in (s): #{job_run_in}"
      sleep_sec = job_run_in - @time_offset if job_run_in > @time_offset
      sleep sleep_sec if sleep_sec > 0

      @run_q.push(1)
      Thread.new(job) do |job_t|
        hit_target(job_t[:uri], job_t[:resp], job_t[:host_header])
        @run_q.pop
      end
      @time_offset = job_run_in
    end
  end

  def hit_target(uri, ex_resp, host_header = nil)
    @log.debug "Target: http://#{@host}:#{@port}/#{uri}, headers: #{'Host: ' + host_header if host_header}"
    if @dummy
      return
    end
    begin
      @log.debug "UriHitter: #{Thread.current}"
      req = Net::HTTP::Get.new(uri)
      req['Host'] = host_header if host_header
      start_time = Time.new
      resp, data = Net::HTTP.start(@host, @port) {|http| http.request(req)} 
      elapsed_time = Time.now - start_time 
      @results_q.push({ :resp => resp.code, :ex_resp => ex_resp, :uri => uri, :r_time => elapsed_time, :s_time => start_time})
    rescue
      @log.error "Request failed: #{uri}"
      @failed_q.push({ :uri => uri, :host => @host, :host_header => host_header })
    end
  end

end; end

