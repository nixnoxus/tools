#! /usr/bin/gawk -f

# usage: str2time.awk <DATETIME-STRING>

BEGIN {
    now = systime();
    STR = (ARGC -1 >= 1) ? ARGV[++ARGIND] : strftime("%F %T", now);
    if (match(STR, /^([0-9][0-9][0-9][0-9])-([0-9][0-9])-([0-9][0-9])/, ary))
        time_s = ary[1] " " ary[2] " " ary[3];
    else
        time_s = strftime("%Y %m %d", now);

    if (match(STR, /([0-9][0-9]):([0-9][0-9]):([0-9][0-9])$/, ary))
        time_s = time_s " " ary[1] " " ary[2] " " ary[3];
    else if (match(STR, /([0-9][0-9]):([0-9][0-9])$/, ary))
        time_s = time_s " " ary[1] " " ary[2] " 00";
    else
        time_s = time_s " 00 00 00";

    printf "%s\n", mktime(time_s);
}
