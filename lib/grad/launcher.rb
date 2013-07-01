require 'thread'
require 'net/http'

module Grad; class Launcher
  attr_accessor :log, :host, :port, :header
  attr_reader :input_q, :run_q, :results_q

  def initialize
    @input_q   = Queue.new
    @run_q     = Queue.new
    @results_q = Queue.new
  end

  def run_job
    Thread.new(@input_q.pop) do |job|
      @log.debug "URL: #{job[:uri]}, Hit in (s): #{job[:t]}"
      @run_q.push('1')
      sleep job[:t]
      hit_target(job[:uri], job[:resp])
    end
  end

  def hit_target(uri, ex_resp)
    @log.debug "Hitting #{uri} at time #{Time.now}"
    if @dummy
      @run_q.pop
      return
    end
    begin
      @log.debug "UriHitter: #{Thread.current}" 
      http = Net::HTTP.new(@host, @port)
      start_time = Time.new
      resp, data = http.get(uri)
      elapsed_time = Time.now - start_time 
      @run_q.pop
      @results_q.push({ :resp => resp.code, :ex_resp => ex_resp, :uri => uri, :r_time => elapsed_time, :s_time => start_time})
    rescue
      @log.error "Request failed: #{hit_uri}"
      @run_q.pop
    end
  end

end; end

