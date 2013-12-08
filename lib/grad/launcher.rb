require 'thread'
require 'net/http'
require 'time'

module Grad; class Launcher
  attr_accessor :host_header, :resp_t, :mock, :skip, :pipe, :user, :pass, :proxy_addr, :proxy_port 
  attr_reader :input_q, :done_q, :fail_q, :drop_q, :jobs_max

  def initialize(host, port, log, max_req = nil)
    @input_q = Queue.new
    @done_q  = Queue.new
    @fail_q  = Queue.new
    @drop_q  = Queue.new
    @resp_t  = Queue.new

    @jobs_run  = ThreadGroup.new
    @neg_allow = 10

    @host = host
    @port = port
    @log  = log
    if max_req
      @jobs_max  = max_req
      @run_sleep = 1
    else
      @jobs_max = 500
      @run_sleep = 0.001
    end
  end

  # start main launcher thread
  #
  def start
    @main = Thread.new do
      @start_time = Time.new.to_i
      run_input while sleep @run_sleep
    end
    @jobs_run.add(@main)
  end

  # stop launcher
  #
  def stop
    @main.exit
  end

  # check if launcher is finished
  #
  def finished?
    @input_q.empty? && slots_used == 0
  end

  # process input queue
  #
  def run_input
    slots_free.times { run_job(@input_q.pop) } unless @input_q.empty?
  end

  # run a job
  #
  def run_job(job)
    return if job.nil?
    run_in = calc_run(job[:t])
    return if run_in.nil?
    Thread.new(job) do |j|
      @log.debug "#{j}: run in #{run_in}"
      sleep run_in if run_in > 0
      hit(j[:uri], j[:resp], j[:raw], j[:host_header])
    end
  end

  # 
  #
  def calc_run(t)
    if @skip
      0
    else
      run_t = ( @start_time + t ) - Time.now.to_i
      if run_t + @neg_allow > 0
        run_t
      else
        @log.error "#{job}: passed negative ttl, #{job[:t]} seconds behind, max allowed is #@neg_allow"
        @drop_q.push(job)
        nil
      end
    end
  end

  # amount of running jobs
  #
  def slots_used
    @jobs_run.list.size - 1 
  end

  # amount of free slots
  #
  def slots_free
    @jobs_max - slots_used
  end

  # hit a target
  #
  def hit(uri, ex_resp, raw, host_header = nil)
    @log.debug "url: http://#{@host}:#{@port}/#{uri}, headers: #{'Host: ' + host_header if host_header}"
    puts raw if @pipe
    unless @mock
      @log.debug "UriHitter: #{Thread.current}"
      req = Net::HTTP::Get.new(uri)
      req['Host'] = host_header if host_header
      req.basic_auth(@user, @pass) if @user and @pass
      start_time = Time.new
      if @proxy_addr and @proxy_port
        resp, data = Net::HTTP::Proxy(@proxy_addr, @proxy_port).start(@host, @port) {|http| http.request(req)}
      else
        resp, data = Net::HTTP.start(@host, @port) {|http| http.request(req)}
      end
      elapsed_time = Time.now - start_time
      @resp_t.push(elapsed_time)
      @done_q.push({ :resp => resp.code, :ex_resp => ex_resp, :uri => uri, :r_time => elapsed_time, :s_time => start_time})
    end
  rescue
    @log.error "Request failed: #{uri}"
    @fail_q.push({ :uri => uri, :host => @host, :host_header => host_header })
  end

end; end

