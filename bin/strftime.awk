#! /usr/bin/gawk -f

# usage: strftime.awk [FORMAT] <TIMESTAMP>

BEGIN {
    FMT = (ARGC -1 >= 2) ? ARGV[++ARGIND] : "%F %T";
    T   = (ARGC -1 >= 1) ? ARGV[++ARGIND] : 0;
    printf "%s\n", strftime(FMT, T);
}
