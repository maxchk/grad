##grad

Grad is ruby based load testing tool that replays logs to generate an exact 
load behaviour patterns against target site as it is recorded in logs.

Replays logs in Apache/NCSA log format.

Name Grad is coming from:
"The BM-21 launch vehicle (Russian: БМ-21 "Град"), (Grad) a Soviet truck-mounted 122 mm multiple rocket launcher.
BM stands for boyevaya mashina, ‘combat vehicle’, and the nickname grad means ‘hail’"
(http://en.wikipedia.org/wiki/BM-21_Grad)


##Examples of usage:


######Replay log file www.example.com.log against staging.example.com site
    cat www.example.com.log | grad -F %combined staging.example.com

TIP: can also be used varnishncsa or similar tool

######If you want to be more specific with logs format
    cat www.example.com.log | grad -F "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\" %w" staging.example.com

######Or if you want to replay against single server, port 8080, setting host header to 'www.example.com'
    cat www.example.com.log | grad -H www.example.com server1:8080

######If you want to skip deplays between log entries and replay logs as fast as possible
     cat www.example.com.log | grad -s staging.example.com

TIP: you may want to use --skip with --limit option

######For all help run:
    grad --help

