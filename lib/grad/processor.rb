module Grad; class Processor

  LOG10_X_MIN = -3.0  # 1 millisecond
  LOG10_X_MAX =  1.0  # 10 seconds 

  require 'terminfo'

  # For now just have a single function 
  # to read the stats in from a queue to an array
  # and do some simple processing
  #
  def self.print_mean(result_queue)
    
    # Iterate through the current queue and read stats into a temporary array

    stat_array = Array.new
    avg = 0

    until result_queue.empty?
      stat_array.push(result_queue.pop)
    end

    stat_array.each { |x| avg += x[:r_time] }
    stat_array.each { |x| x[:log10_r_time] = Math.log10(x[:r_time]) }

    if stat_array.length > 0
      avg = avg/stat_array.length
      puts "#{avg}, #{stat_array.length}"
    end
  end

  def self.print_graph(result_queue)

    stat_array = Array.new

    until result_queue.empty?
      stat_array.push(result_queue.pop)
    end

    lines, cols = TermInfo.screen_size

    bin_width = (LOG10_X_MAX - LOG10_X_MIN)/cols
 
    bins = Array.new(cols){0}

    stat_array.each { |x| bins[((Math.log10(x[:r_time])-LOG10_X_MIN)/bin_width).floor] += 1 }

    p bins
  end
 
end ; end
