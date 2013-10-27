require 'curses'
module Grad; class Dashboard
  attr_accessor :host, :port, :host_header, :log_dst, :format, :log_src
  include Curses

  def initialize(watcher_obj)
    init_screen
    @watcher_obj = watcher_obj
  end

  def print_out
    setpos(0, 0)

    # print header
    addstr("=============== Grad Dashboard ===============\n")
    addstr("Target Host: \
#{@host}:#{@port}, \
Host header: #{@host_header}\n\
Input Log Source: \"#{@log_src}\"\n\
Input Log Format: \"#{@format}\"\n\
LogTo: #{@log_dst}\n\n")

    # print vehicle stats
    #
    addstr("\nGrad vehicle stats>\n")

    # print load average stats
    addstr("load average: \
#{@watcher_obj.loadavg[:min1]}, \
#{@watcher_obj.loadavg[:min5]}, \
#{@watcher_obj.loadavg[:min15]}\n")

    # print cpu stats
    addstr("Cpu(s): \
#{@watcher_obj.cpu[:us]}%us, \
#{@watcher_obj.cpu[:sy]}%sy, \
#{@watcher_obj.cpu[:ni]}%ni, \
#{@watcher_obj.cpu[:id]}%id, \
#{@watcher_obj.cpu[:wa]}%wa, \
#{@watcher_obj.cpu[:hi]}%hi, \
#{@watcher_obj.cpu[:si]}%si, \
#{@watcher_obj.cpu[:st]}%st\n")

    # print network stats
    addstr("Network: \
#{@watcher_obj.network[:tcp_conn]} tcp total, \
#{@watcher_obj.network[:tcp_conn_port]} tcp port #{@port} total\n")

    # print memory stats
    mem_u = @watcher_obj.memory[:units]
    if @watcher_obj.memory[:m_total] >= @watcher_obj.memory[:s_total] 
      l = @watcher_obj.memory[:m_total].to_s.length 
    else 
      l = @watcher_obj.memory[:s_total].to_s.length
    end
    m_used_p    = l - @watcher_obj.memory[:m_used].to_s.length
    m_free_p    = l - @watcher_obj.memory[:m_free].to_s.length
    m_buffers_p = l - @watcher_obj.memory[:m_buffers].to_s.length
    s_used_p    = l - @watcher_obj.memory[:s_used].to_s.length
    s_free_p    = l - @watcher_obj.memory[:s_free].to_s.length
    s_cached_p  = l - @watcher_obj.memory[:s_cached].to_s.length
    addstr("Mem:  \
#{@watcher_obj.memory[:m_total]}#{mem_u} total, \
#{' '*m_used_p}#{@watcher_obj.memory[:m_used]}#{mem_u} used, \
#{' '*m_free_p}#{@watcher_obj.memory[:m_free]}#{mem_u} free, \
#{' '*m_buffers_p}#{@watcher_obj.memory[:m_buffers]}#{mem_u} buffers\n")
    addstr("Swap: \
#{@watcher_obj.memory[:s_total]}#{mem_u} total, \
#{' '*s_used_p}#{@watcher_obj.memory[:s_used]}#{mem_u} used, \
#{' '*s_free_p}#{@watcher_obj.memory[:s_free]}#{mem_u} free, \
#{' '*s_cached_p}#{@watcher_obj.memory[:s_cached]}#{mem_u} cached\n")

    # print launcher stats
    #
    addstr("\nGrad launcher stats>\n")
    addstr("\
Input_Q: #{@watcher_obj.launcher.input_q.size},\n\
Run_Q: #{@watcher_obj.launcher.slots_used}\n\
Req_done: #{@watcher_obj.launcher.done_q.size}\n\
Req_fail: #{@watcher_obj.launcher.fail_q.size}\n\
Req_drop: #{@watcher_obj.launcher.drop_q.size}\n\
")

    # print target stats
    #
    addstr("\nGrad target stats>\n")
    addstr("\
Resp time (med): #{@watcher_obj.resp_time_mediana},\n\
")

    # refresh screen
    #
    refresh
  end

  def stop
    close_screen
  end
end; end
