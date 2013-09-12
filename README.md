##grad

Grad is ruby based load testing tool that replays logs to generate an exact 
load behaviour patterns against target site as it is recorded in logs.

Replays logs in Apache/NCSA log format.

Name Grad is coming from:
"The BM-21 launch vehicle (Russian: БМ-21 "Град"), (Grad) a Soviet truck-mounted 122 mm multiple rocket launcher.
BM stands for boyevaya mashina, ‘combat vehicle’, and the nickname grad means ‘hail’"
(http://en.wikipedia.org/wiki/BM-21_Grad)


##Examples of usage:


######Will replay log file www.example.com.log against staging.example.com site
    grad -f www.example.com.log -F %combined staging.example.com

######Will do the same thing
    cat www.example.com.log | grad -F %combined staging.example.com

TIP: pipe can be handy with varnishncsa. Use --continual option with it.

######If you want to be more specific with logs format
    grad -f www.example.com.log -F "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\" %w" 

######Or if you want to replay against single server, port 8080
    grad -f www.example.com.log -H www.example.com server1:8080

######For all help run:
    grad --help

