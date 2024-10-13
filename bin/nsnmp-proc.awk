#! /usr/bin/gawk -f
#
# nsnmp-proc.awk (based on nsnmp-proc version 17)

### misc functions ###
function abs(v) {
    return (v +0 < 0) ? 0-v : v;
}
function aryIndex(src, dst, c) {
    while (c > 0 && src != dst[c]) c --;
    return c;
}
function str_replace(pat, rep, str,  i) {
    while (i = index(str, pat))
        str = substr(str, 0, i-1) rep substr(str, i + length(pat));
    return str;
}
function str_repeat (str,n, ret) {
    while(n -- > 0) ret = ret str;
    return ret;
}
function toname(name, str,i) {
    str = name;
    gsub(/-/, "", str);
    gsub(/[ ()]/, "_", str);
    while (i = index(str, "_"))
        str = substr(str, 1, i-1) \
              toupper(substr(str, i+1, 1)) \
              substr(str, i+2);

    sub(/^.*\//, "", str);
    return str;
}
function setRecord(name,suffix,   r) {
    if (OPT["COMPACT"]) {
        for (r in SUFFIX) {
            if (SUFFIX[r] == toname(suffix) && r < RECS) {
                NAME[r] = "";
                REC = r;
                return;
            }
        }
    }
    REC = RECS ++;
    SUFFIX[REC] = toname(suffix);
    NAME[REC] = name;
    VARS[REC] = "";
    VALS[REC] = "";
}
function addRecordData(var,val,x , ary) {
    if (val == "") {
        if (CACHE[var"."SUFFIX[REC]] != "")
            val = CACHE[var"."SUFFIX[REC]];
        else if (CACHE[var] != "")
            val = CACHE[var];
    } else if (x != "") {
        val = sprintf("%." x "f", val);
    } else if (val == int(val))
        val = sprintf("%ld", val);

    if (OPT["RRD"]) {
        if (!match(var, /^([a-zA-Z0-9]+)(\([CG](|32|64)\))?$/, ary)) {
            printf "internal bug (rrd name) '%s'\n",var >> "/dev/stderr";
            exit(64);
        }
        if (VAR2RRD[ary[1]] != "")
            ary[1] = VAR2RRD[ary[1]];
        else
            for (x in VAR2RRD_SUB) {
                x = gensub(x, VAR2RRD_SUB[x], "g", ary[1]);
                if (x != ary[1]) {
                    ary[1] = x;
                    break;
                }
            }

        var = ary[1] ary[2];
        ary[0] = (!OPT["NO_SUFFIX"] && SUFFIX[REC] != "") \
            ? ary[1] "." SUFFIX[REC] : ary[1];

        if (length(ary[0]) > 19)
            gsub("Hardware", "Hw", ary[0]);

        if (length(ary[0]) > 19)
            printf "E: name to long '%s': %s\n" \
                , ary[0], length(ary[0]) >> "/dev/stderr";
    }

    VARS[REC] = ((VARS[REC] != "") ? VARS[REC]  ";" : "") var;
    VALS[REC] = ((VALS[REC] != "") ? VALS[REC]  ";" : "") val;
}
function close_FILE (e) {
    if (FILE == "") return 0;
    close(FILE);
    if (e >= 0) return 0;
    if (OPT["QUIET"] == 0)
            printf "WARNING: Can't read '%s': %s\n", FILE, ERRNO >> "/dev/stderr";
    WARNS ++;
    return e;
}

### agents ###
function loadavg (  ary,key,c) {
    FILE = OPT["PROC"] "/loadavg";
    if ((c = getline < (FILE)) > 0 &&
            split($0, ary, /[ /]/) == 6) {
        key[0] = split("laLoad1(G);laLoad2(G);laLoad3(G)" \
           ((1) ? ";procRunsX(G);procRunableX(G);procsX(C32)" : "") \
            , key, /;/);
        setRecord("load", "");
        for (c = 1; c <= key[0]; c++)
            addRecordData(key[c], ary[c]);
    }
    return c;
}
function stat (cpus, ints, ary,key,i,c,buffer,cputime) {
    setRecord("sys");
    FILE = OPT["PROC"] "/uptime";
    if ((c = getline < (FILE)) > 0) {
        addRecordData("sysUpTime(C)", gensub(/\./, "", "", $1)); # FIXME
        addRecordData("sysIdleTimeX(C)", gensub(/\./, "", "", $2)); # FIXME
    }
    close_FILE(c);

    buffer[0] = 0;
    # linux-2.4: User Nice System Idle (like SNMP)
    # linux-2.6: User Nice System Idle IOwait Irq SoftIrq
    cputime[0] = split("User:Nice:System:Idle:IOwait:Irq:SoftIrq", cputime, ":");
    FILE = OPT["PROC"] "/stat";
    while ((c = getline < (FILE)) > 0) {
        if (match($0, /^cpu +([0-9 ]+)/,ary)) {
            if (cputime[0] > (ary[0] = split(ary[1], ary, " ")))
                cputime[0] = ary[0];
            for (i = 1; i <= 4; i ++)
                addRecordData("ssCpuRaw" cputime[i] "(C)", ary[i]);
            for (i = 5; i <= cputime[0]; i ++)
                addRecordData("ssCpuRaw" cputime[i] "X(C)", ary[i]);
        } else if (match($0, /^cpu([0-9]+) +([0-9 ]+)/,ary)) {
            ary[0] = split(ary[1] " " ary[2], ary, " ");
            for (i = 0; i < cputime[0]; i ++)
                buffer[1+ary[1]*cputime[0]+i] = ary[2+i];
            buffer[0] ++;
        } else if (match($0, /^page ([0-9]+) ([0-9]+)/,ary)) { # not in 2.6
            for (i = split("In:Out", key, ":"); i > 0; i --)
                addRecordData("ssRawPage" key[3-i] "X(C)", ary[3-i]);
        } else if (match($0, /^swap ([0-9]+) ([0-9]+)/,ary)) { # not in 2.6
            for (i = split("In:Out", key, ":"); i > 0; i --)
                addRecordData("ssRawSwap" key[3-i] "(C)", ary[3-i]);
        } else if (match($0, /^intr ([0-9]+)(( [0-9]+)*)/,ary)) {
            addRecordData("ssRawInterrupts(C)", ary[1]);
            ary[0] = split(substr(ary[2], 2), ary, / /);
            for (i = 1; i <= ((ints != "") ? ints : ary[0]); i++)
                addRecordData("ssRawInterrupt" (i - 1) "X(C)" \
                             , (i <= ary[0]) ? ary[i] : "");
        } else if (match($0, /^ctxt ([0-9]+)/,ary)) {
            addRecordData("ssRawContexts(C)", ary[1]);
        } else if (match($0, /^processes ([0-9]+)/,ary)) {
            addRecordData("ssRawProcessesX(C)", ary[1]);
        #  procs_running are ignored (already readed from /proc/load)
        } else if (match($0, /^procs_blocked ([0-9]+)/,ary)) {
            addRecordData("procBlockedX(G)", ary[1]);
        } else if (match($0, /^disk_io: \(([0-9]+),([0-9]+)\):\([0-9]+,([0-9]+),([0-9]+),([0-9]+),([0-9]+)\)/, ary)) {
            i = "";
            if (lshift(ary[1], 8) + ary[2] == lshift( 3, 8) +  0) i = "hda";
            if (lshift(ary[1], 8) + ary[2] == lshift( 3, 8) + 64) i = "hdb";
            if (lshift(ary[1], 8) + ary[2] == lshift(22, 8) +  0) i = "hdc";
            if (lshift(ary[1], 8) + ary[2] == lshift(22, 8) + 64) i = "hdd";

            if (i != "") {
                CACHE["diskIOReads(C)."i]    = ary[3];
                CACHE["diskIOWrites(C)."i]   = ary[5];
                CACHE["diskIONRead(C)."i]    = sprintf("%ld", ary[4] * 512);
                CACHE["diskIONWritten(C)."i] = sprintf("%ld", ary[6] * 512);
            }
        }
    }
    close_FILE(c);

    for (i = 0; i < cputime[0]; i ++)
        for (c = 0; c < cpus; c ++)
            #addRecordData("ssCpuRaw" cputime[1+i] c ((i < 4) ? "(C)" : "X(C)"), buffer[1+i+c*cputime[0]]);
            addRecordData("ssCpuRaw" cputime[1+i] c "X(C)" \
                , buffer[1+i+c*cputime[0]]);
}
function meminfo (   ary,key,c,val,var) { # full SNMP compat: memory
    key[0] = split("SwapTotal;SwapFree;MemTotal;MemFree" \
        ";MemShared;Buffers;Cached", key, /;/);
    var[0] = split("memTotalSwap;memAvailSwap;memTotalReal;memAvailReal" \
        ";memShared;memBuffer;memCached", var, /;/);
    FILE = OPT["PROC"] "/meminfo";
    while ((c = getline < (FILE)) > 0) {
        # ignore  leading table in 2.4
        if (!match($0, /^(.+):[[:space:]]+([0-9]+) kB/, ary)) continue;
        for (c = key[0]; c > 0 && ary[1] != key[c]; c--);
        if (!c) var[c = ++var[0]] = "mem" toname(ary[1]) "X";
        val[c] = ary[2];
    }
    close_FILE(c);
    setRecord("mem");
    for (c = 1; c <= var[0]; c++) addRecordData(var[c] "(G)", val[c]);
}
function cpuinfo (cpus, c,cpu,k,key,var) {
    key[0] = split("processor;cpu MHz;bogomips", key, /;/);
    FILE = OPT["PROC"] "/cpuinfo";
    while ((c = getline < (FILE)) > 0)
        for (k = 1; k <= key[0]; k++)
            if (match($0, "^" key[k] "[[:space:]]+:[[:space:]]+([0-9]+(\\.[0-9]+)?)$", ary))
                if (k == 1)
                    setRecord("cpu", "cpu" ary[1]);
#                    cpu = ary[1]
                else
                    addRecordData(toname(key[k]) "X(G)", ary[1]);
#                    var[cpu * key[0] + k -1] = ary[1];
    close_FILE(c);
#    setRecord("cpu");
#    for (c = 0; c < ((cpus) ? cpus : (cpu + 1)); c ++)
#        for (k = 2; k <= key[0]; k ++)
#            addRecordData(toname(key[k]) c "X(G)", var[c * key[0] + k -1]);
}
function diskstats (dev, r,ary,c) {
    while ((c = getline < (FILE)) > 0) {
        sub(/^[[:space:]]+/, "", $0);
        ary[0] = split($0, ary, /[[:space:]]+/);
        if (dev != "" && dev != toname(ary[3])) continue;

        setRecord("disk", ary[3]);
        addRecordData("diskBlocksX(G)", "");

        # see: /usr/src/linux-2.6.14.3/Documentation/iostats.txt
        addRecordData("diskIOReads(C)",   ary[3+((ary[0] == 7) ? 1 : 1)]);
        addRecordData("diskIOWrites(C)",  ary[3+((ary[0] == 7) ? 3 : 5)]);
        addRecordData("diskIONRead(C)" \
            , sprintf("%ld", ary[3+((ary[0] == 7) ? 2 : 3)] * 512));
        addRecordData("diskIONWritten(C)" \
            , sprintf("%ld", ary[3+((ary[0] == 7) ? 4 : 7)] * 512));
        addRecordData("diskIORMergeX(C)", (ary[0] == 7) ? "" : ary[3+2]);
        addRecordData("diskIORUseX(C)", ""); # FIXME
        addRecordData("diskIOWMergeX(C)", (ary[0] == 7) ? "" : ary[3+6]);
        addRecordData("diskIOWUseX(C)", ""); # FIXME
    }
    return c;
}
function sensors (chip, c, h, i, key,k, dir, rec, ary) {
    rec = RECS;
    key[0] = split("temp,3,min,max;fan,0,min;in,3,min,max", key, /;/);
    key[0] = split("temp,3;fan,0;in,3", key, /;/); # FIXME !
    for (h = 0; h < 8; h ++) { # FIXME: max 8 ?
        dir = OPT["SYS"] "/class/hwmon/hwmon" h "/device/";
        if (f_readable(dir "name") <= 0) break; # FIXME: break or continue ?
        if (chip != "" && chip != $0 && chip != h) continue;
        setRecord("sensors", $0);
        for (k = 1; k <= key[0]; k++) {
            ary[0] = split(key[k], ary, /,/);
            for (i = 0; i < 8; i ++) {
                if (f_readable(dir ary[1] i "_input") <= 0) continue;
                addRecordData(ary[1] i "X(G)", $0 / (10 ** ary[2]), ary[2]);
                for (c = 3; c <= ary[0]; c ++)
                    if (f_readable(dir ary[1] i "_" ary[c]) > 0)
                        addRecordData(ary[1] i toname("_" ary[c]) "X(G)" \
                            , $0 / (10 ** ary[2]), ary[2]);
            }
        }
    }

    # FIXME: 'compute' lines are still ignored
    if (! RECS - rec || ! OPT["SENSORS-CONF"]) return;

    key[0] = split("X(G);MinX(G);MaxX(G)", key, ";");
    while((c = getline < (OPT["SENSORS-CONF"])) > 0) {
        for (i = rec; i < RECS; i++) {
            if ($0 !~ "^chip .*\"" SUFFIX[i] "-") continue
            VARS[i] = ";" VARS[i] ";";
            while((c = getline < (OPT["SENSORS-CONF"])) > 0) {
                if ($0 ~ /^[a-zA-Z]/) break;
                if (match($0, /^[[:space:]]+label[[:space:]]+([^[:space:]]+)[[:space:]]+"([^"]+)/, ary))
                    sub(/^\+/, "plus", ary[2]);
                    sub(/^\-/, "minus", ary[2]);
                    sub(/\./, "_", ary[2]);
                    for (k = 1; k <= key[0]; k++)
                        VARS[i] = str_replace(";" ary[1] key[k] ";", ";" toname(ary[2]) key[k] ";", VARS[i]);
            }
            gsub("(^;|;$)", "", VARS[i]);
        }
    }
}
function diskIO (dev,i,ary,idx,c) {
    if ((c = getline < (FILE)) <= 0) return c;
    for (i = split($0, ary, /[[:space:]]+/); i > 0; i --) idx[ary[i]] = i;

    getline < (FILE);
    while ((c = getline < (FILE)) > 0) {
        sub(/^[[:space:]]+/, "", $0);
        ary[0] = split($0, ary, /[[:space:]]+/);
        if (dev != "" && dev != toname(ary[idx["name"]])) continue;
        if (OPT["KVERSION"] >= 26) {
            CACHE["diskBlocksX(G)."toname(ary[idx["name"]])] = ary[idx["#blocks"]];
            continue;
        }
        setRecord("disk", ary[idx["name"]]);
        addRecordData("diskBlocksX(G)", ary[idx["#blocks"]]);

        if (ary[idx["rsect"]] != "")
            ary[idx["rsect"]] = sprintf("%ld", ary[idx["rsect"]] * 512);

        if (ary[idx["wsect"]] != "")
            ary[idx["wsect"]] = sprintf("%ld", ary[idx["wsect"]] * 512);

        addRecordData("diskIOReads(C)", ary[idx["rio"]]);
        addRecordData("diskIOWrites(C)", ary[idx["wio"]]);
        addRecordData("diskIONRead(C)", ary[idx["rsect"]]);
        addRecordData("diskIONWritten(C)" , ary[idx["wsect"]]);
        addRecordData("diskIORMergeX(C)", ary[idx["rmerge"]]);
        addRecordData("diskIORUseX(C)", ary[idx["ruse"]]);
        addRecordData("diskIOWMergeX(C)", ary[idx["wmerge"]]);
        addRecordData("diskIOWUseX(C)", ary[idx["wuse"]]);
#        printf "%li\n", ary[idx["rsect"]] * 512;
    }
    return c;
}
function drbd (minor, m,ary,k,key) {
    if ((m = getline < (FILE)) <= 0) return m;

    # see: http://www.linux-ha.org/DRBD/FAQ#head-988086376cbd00bdcc9c9d199317af5f7550c5c1
    key[0] = split("NetSendX(C);NetRecvX(C);DiskWritesX(C);DiskReadsX(C);ActLogUpdX(G);BitmapUpdX(G);LocalRefX(G);PendingX(G);UnAckX(G);ExpAppReqX(G)", key, /;/);

    while (getline < (FILE) > 0) {
        if (match($0, /^ *([0-9])+:/,ary)) {
            m = ary[1];
        } else if ((minor == "" || minor == m) && \
                match($0, /^ +ns:([0-9]+) nr:([0-9]+) dw:([0-9]+) dr:([0-9]+) al:([0-9]+) bm:([0-9]+) lo:([0-9]+) pe:([0-9]+) ua:([0-9]+) ap:([0-9]+)/, ary)) {
            setRecord("drbd", m);
            for (k = 1; k <= key[0]; k ++)
                addRecordData("drbd" key[k], ary[k]);
        }
    }
    return 0;
}
function ipTable (xproto,   ary,c,key,proto) { # full SNMP compat: ip, icmp
    while ((c = getline < (FILE)) > 0) {
        if (match($0, /^(Ip|Icmp|Tcp|Udp): (.+)$/, ary)) {
            proto = ary[1];
            key[0] = split(ary[2], key, / /);
            if (getline < (FILE) > 0 &&
                    match($0, "^" proto ": (.+)$", ary) &&
                    split(ary[1], ary, " ") == key[0] &&
                    (xproto == "" || xproto == tolower(proto)) ) {
                setRecord(tolower(proto));
                for (c = 1; c <= key[0]; c ++) {
                    addRecordData(tolower(proto) key[c] \
                        ((key[c] ~ /^(In|Out)/ || \
                          key[c] ~ /s$/) ? "(C)" : "") \
                        , ary[c]);
                }
            }
        }
    }
    return c;
}
function net_cache (pre, cpus, cpu, c, key, ary, i) { # FIXME: per CPU
    cpu = 0;
    while ((c = getline < (FILE)) > 0) {
        if ($0 ~ /^entries/) {
            key[0] = split($0, key, / +/);
        } else {
            setRecord(pre, "cpu" cpu ++);
            ary[0] = split($0, ary, / +/);
            for (i = 1; i <= key[0]; i++) {
                addRecordData(toname(key[i]) \
                    "X(" ((i == 1) ? "G" : "C") (length(ary[i]) * 8) ")" \
                    , strtonum("0x"ary[i]));
            }
        }
    }
    return c;
}
function prefix (pre,str,sur, ary,c,d) {
    ary[0] = split(str, ary, /[[:space:]]+/);
    str = "";
    for (c = 1; c <= ary[0]; c ++) {
        str = str ";" pre \
            toupper(substr(ary[c], 1, 1)) substr(ary[c], 2) sur;
    }
    return substr(str, 2);
}
function ifTable (iface,   c,ary,key,e) {
    c = -2;
    while ((e = getline < (FILE)) > 0) {
        if ($0 ~ /^Inter/ && c == -2) {
            c ++;
        } else if ($0 ~ /^ face \|/ && c == -1) {
            if (split($0, ary, /\|/) != 3) return;
            key[0] = split(prefix("In", ary[2]) \
                    ";" prefix("Out", ary[3]), key, ";");
            for (c = key[0]; c >= 1; c --)
                key[c] = "if" ((sub(/Bytes$/, "Octets", key[c]) \
                    || sub(/Errs$/, "Errors", key[c])) \
                    ? key[c] : key[c] "X")  "(C)";
        } else if (match($0, /^[ ]*(.+): *(.*)$/, ary) &&
               (iface == "" || iface == ary[1])) {
            c = ary[1];
            if (split(ary[2], ary, /[[:space:]]+/) != key[0]) {
                print "parse error" >> "/dev/stderr";
                exit 64;
            }
            setRecord("if", c);
            for (c = 1; c <= key[0]; c ++) addRecordData(key[c], ary[c]);
        }
    }
    if (iface != "" && c == 0 && OPT["COMPACT"]) {
        setRecord("if", iface);
        for (c = 1; c <= key[0]; c ++) addRecordData(key[c], 0);
    }
    return e;
}
#function split2hash (str, hash, regex ,ary,c,x) {
#    shift;
#  delete(q);
 # print q;
  #exit 0;
#   c = split(str, ary, regex);
 #  x = 0;
  # for (str in ary) {
#hash[ary[str]] = x++;
 #  }
#    return hash;
#}

### at the moment ###
function unix (   ary,idx,hash,i,t) {
    if ((i = getline < (FILE)) <= 0) return i;
    for (i = split($0, ary, /[[:space:]]+/); i > 0; i --) idx[ary[i]] = i;

    while (getline < (FILE) > 0) {
        sub(/^[[:space:]]+/, "", $0);
        ary[0] = split($0, ary, /[[:space:]]+/);
        hash[strtonum("0x" ary[idx["Type"]]) \
            ":" strtonum("0x" ary[idx["St"]]) + 1] ++;
    }
    # see /usr/include/bits.h
    ary[0] = split("Stream Dgram Raw Rdm SeqPacket . . . . Packet", ary, / /);
    # see /usr/include/linux/net.h
    idx[0] = split("Free Unconnected Connecting Connected Disconnecting" \
        , idx, / /);
    setRecord("unix");
    for (t = 1; t <= ary[0]; t ++)
        for (i = 1; i <= idx[0]; i ++)
            if (ary[t] != ".")
                addRecordData("unix" ary[t] idx[i] "X(G)", 0 + hash[t ":" i]);
    return 0;
}
function netstat (proto,  ary,hash,k,i,c,addr) {
    FILE = OPT["PROC"] "/net/" proto;

    addr = "(" str_repeat("[0-9A-F]", 8) "):" str_repeat("[0-9A-F]", 4);
    while ((c = getline < (FILE)) > 0) {
        if (match($0, "^ *[0-9]+: " addr " " addr " ([0-9A-F][0-9A-F]) ", ary)) {
            hash["conn:00:" ary[2]]++;          # count by host
            hash["conn:00"] ++;                 # count total
            if (proto == "tcp") {
                hash["conn:" ary[3]]++;             # count by state
                hash["conn:" ary[3] ":"  ary[2]]++; # count by state & host
            }
        }
    }
    if (close_FILE(c)) return;

    # see:  /usr/include/{linux,netinet}/tcp.h
    ary[0] = split((proto == "tcp") \
       ? " Established SynSent SynRecv FinWait1 FinWait2 TimeWait" \
        " Close CloseWait LastAck Listen Closeing " : " ", ary, / /);
    setRecord(proto "Conn");

    for (i = 0; i < ary[0] - 1; i++)
        addRecordData(proto "Conn" ary[i+1] "X(G)" \
            , 0 + hash[sprintf("conn:%02X", i)]);
    for (i = 0; i < ary[0] - 1; i++) {
        c = 0;
        for (k in hash)
            if (k ~ sprintf("conn:%02X:", i)) c ++;
        addRecordData(proto "ConnRHosts" ary[i+1] "X(G)", c);
    }
}
function iptConntrack (   ary,str,c,key,proto) {
    key[0] = split("tcp;udp;icmp;other", key, /;/);
    for(c in key) proto[key[c]] = 0;
    str = "[[:space:]]+[0-9]+ .+ +src=.+ dst=.+";
    while ((c = getline < (FILE)) > 0) {
        if (match($0, "^(tcp|udp|icmp)" str, ary)) {
            proto[ary[1]] ++;
        } else if (match($0, "^(.+)" str, ary)) {
            proto["other"] ++;
            if (DEBUG) print "N: count as 'other': " $0 >> "/dev/stderr";
        } else {
            print "E: [ipt] can't parse: " $0 >> "/dev/stderr";
        }
    }
    if (close_FILE(c)) return;
    setRecord("ipt", "");
    for (c = 1; c <= key[0]; c ++) {
        addRecordData(\
            "IpConntrack" toupper(substr(key[c], 1, 1)) substr(key[c], 2) \
             "X(G)", proto[key[c]]);
    }
}
function routeCache (iface,   ary,c,head,n,key,ifNames,e) {
    c = -1;
    ifNames = "";
    while ((e = getline < (FILE)) > 0) {
        if (c == -1) {
           gsub(/[[:space:]]+/, ";", $0);
            c = split($0, head, /;/);
#            print $0; #head[2];
#            print c;
            n = aryIndex("Use", head, c);
        } else {
            split($0, ary, /[[:space:]]+/);
            ary[n] ++;
            if (key["count",$1]) {
                if (key["Umin",$1] > ary[n]) key["Umin",$1] = ary[n];
                if (key["Umax",$1] < ary[n]) key["Umax",$1] = ary[n];
            } else {
                ifNames = ifNames " " ary[1];
                key["Umin",$1] = ary[n];
                key["Umax",$1] = ary[n];
            }
            key["Usum",$1] += ary[n];
            key["Usum2",$1] += ary[n] * ary[n];
            key["count",$1] ++;
        }
    }
#    printf "%s:%s:%s\n", iface, OPT["COMPACT"],key["count",iface];
    if (iface != "" && OPT["COMPACT"] && !(key["count",iface] += 0)) {
        ifNames = ifNames " " iface;
        for (n = split("count,Umin,Umax,Usum,Usum2", ary, ","); n > 1; n --)
            key[ary[n],iface] = 0;
    }
#    printf "D: ifNames='%s'\n", ifNames;
    for (n = split(substr(ifNames, 2), ifName, / /); n >= 1; n --)  {
#        printf "D: n=%s iface='%s' ifName='%s'\n", n, iface, ifName[n];
        if (iface != "" && iface != ifName[n]) continue;
        if (key["count",ifName[n]]) {
            key["Usum",ifName[n]]  /= key["count",ifName[n]];
            key["Usum2",ifName[n]] /= key["count",ifName[n]];
            key["Usum2",ifName[n]] = sqrt(key["Usum2",ifName[n]] \
               - key["Usum",ifName[n]] * key["Usum",ifName[n]]);
        }
        setRecord("route", ifName[n]);
        addRecordData("ifRouteEntriesX(G)", key["count",ifName[n]]);
        addRecordData("ifRouteUseSumX(G)", key["Usum",ifName[n]]);
        addRecordData("ifRouteUseMinX(G)", key["Umin",ifName[n]]);
        addRecordData("ifRouteUseMaxX(G)", key["Umax",ifName[n]]);
        addRecordData("ifRouteUseAvgX(G)", key["Usum",ifName[n]]);
        addRecordData("ifRouteUseMdevX(G)", key["Usum",ifName[n]]);
    }
    return e;
}

function f_readable (file, c) {
    if (file ~ /^\/dev\/std(out|err)/) return 0;
    c = getline < (file);
    close(file);
    return c;
}
### output functions ###
function out_csv (idx,file,  head,ary,i,c,var_a,val_a,var) {
    if (SUFFIX[idx] != "") {
        if (!sub(/#/, SUFFIX[idx],file) && !OPT["NO_SUFFIX"]) {
            gsub(/(\([CG]\))?;/, "." SUFFIX[idx] "&", VARS[idx]);
            sub(/(\([CG]\))?$/, "." SUFFIX[idx] "&", VARS[idx]);
        }
    }
    if (0 && match(file, /(.+)-([0-9]+)(\.csv)$/, ary)) { # FIXME: remove
        ary[0] = ary[1] "-" (++ary[2]) ary[3];
        while (f_readable(ary[0]) >= 0) {
            ary[0] = ary[1] "-" (++ary[2]) ary[3];
        }

        if (ary[2] > 1) file = ary[1] "-" (ary[2] -1) ary[3];

        getline head < (file);
        if (head != "timestamp;" VARS[idx]) {
            print "W: differ header " file " use " ary[0] >> "/dev/stderr";
            close(file);
            file = ary[0];
            print "timestamp;" VARS[idx] >> (file);
        }
    } else if (f_readable(file) > 0) {
        head = $0;
        if (head != "timestamp;" VARS[idx]) {
            if (0) {
                print "E: differ header " file ": " head >> "/dev/stderr";
                print "timestamp;" VARS[idx] >> (file);
            } else if  (match(head, /^timestamp;(.+)/,ary)) {
                ary[0] = split(ary[1], ary, ";");
                var_a[0] = split(VARS[idx], var_a, ";");
                val_a[0] = split(VALS[idx], val_a, ";");
                VALS[idx] = "";
                for (c = 1; c <= ary[0]; c ++) {
                    i = aryIndex(ary[c],var_a,var_a[0]);
                    VALS[idx] = VALS[idx] ((i) ? val_a[i] : "") ";";
                }
                sub(/;$/, "", VALS[idx]);
            }
        }
    } else {
        print "timestamp;" VARS[idx] >> (file);
    }
    print TIME ";" VALS[idx] >> (file);
    close(file);
    file = "";
}
function out_hum (idx,suffix, c,i,VARS_a,VALS_a,TYPES,ary) {
    c = split(VARS[idx] ,VARS_a, ";");
    split(VALS[idx], VALS_a, ";");
    TYPES["G"] = " (Gauge)";
    TYPES["C"] = " (Counter)";
    TYPES["C32"] = " (32 Bit Counter)";
    TYPES["C64"] = " (64 Bit Counter)";
    TYPES[""] = "";
    i = 0;
    suffix = (SUFFIX[idx] != "") ?  "." SUFFIX[idx] : "";
    if (!OPT["COMPACT"]) print ((OPT["OID"]) ? "# " : "")NAME[idx] suffix ":";
    if (OPT["NO_SUFFIX"]) suffix = "";

    while (++i <= c) {
        if (!match(VARS_a[i], /^([a-zA-Z0-9]+)(\([CG](|32|64)\))?$/, ary)) {
            printf "internal bug '%s'\n",VARS_a[i] >> "/dev/stderr";
            exit(64);
        }
        if (OPT["OID"])
            printf ", %-30s => \"%s.%d\"\n" \
                , ary[1] suffix , OPT["OID"], ++OPT["IID"];
        else if (OPT["SNMPD"])
            print VALS_a[i];
        else
                   printf " %-30s: %10s%s\n" \
                , ary[1] suffix, VALS_a[i], TYPES[ary[3]];
    }
}
function human(val, u) {
    if (abs(val +0) >= 10000)  {
        val += 0;
        u = 1;
        while (abs(val +0) >= 10000 && u++ <= UNITS[0]) val = int(val / 1000);
        return sprintf("% 3ld%1s", val, UNITS[u]);
    } else if (abs(val +0) < 10 && val ~ /\./)
        return sprintf("% 3.2lf ", val);
    else if (abs(val +0) < 100 && val ~ /\./)
        return sprintf("% 3.1lf ", val);
    else
        return sprintf("% 4ld ", val);
}
function cmp(a,b) {
    return (a < b) ? "<" : (a > b) ? ">" : " ";
}
BEGIN {

    T_START = systime();
            FILE = "/proc/uptime";
            if ((c = getline < (FILE)) > 0) {
                U_START = gensub(/\./, "", "", $1); # FIXME:
                close(FILE);
            }

    DEBUG = 0;
    WARNS = 0;

    VAR2RRD["ifInCompressedX"]      = "ifInCompX";
    VAR2RRD["ifOutCompressedX"]     = "ifOutCompX";
    VAR2RRD["icmpOutTimestampReps"] = "icmpOutTSReps";
    VAR2RRD["icmpInTimestampReps"]  = "icmpInTSReps";
    VAR2RRD["ifRouteEntriesX"]      = "ifRouteCountX";
    VAR2RRD["ifRouteUseMdevX"]      = "ifRouteUMdevX";
    VAR2RRD_SUB["^(tcpConnRHosts)(.+)"]          = "tRHC\\2";
    VAR2RRD_SUB["^(unix)(.+onn)ect(ing|ed)(.*)"] = "u\\2\\4";
    VAR2RRD_SUB["^(unix)(.+)"]                   = "u\\2";

    UNITS[0] = split(":K:M:G:T:P", UNITS, /:/); # FIXME: incomplete

    OPT["PROC"] = "/proc";
    OPT["SYS"]  = "/sys";
    OPT["KVERSION"] = 0;
    OPT["QUIET"]    = 0;
    OPT["TTY"]      = 1; # FIXME: autodetect in pure awk ?
    OPT["SENSORS-CONF"] = ""; #"/etc/sensors.conf";
    OPT["KEEP"]     = 10;

    for (a = 1; a < ARGC; a++) {
        if (ARGV[a] == "all") {
            ARGV[a] = "sys";
            ary[0] = split("load mem ip ipt if route disk netstat unix" \
               , ary, / /);
            for (i = 1; i <= ary[0]; i++)
                ARGV[ARGC++] = ary[i];
        }
    }
    if (ARGC == 1) {
        print "usage: nsnmp-csv [OPTION].. { <KEY>.. [/PATH/OUTPUT.CSV] }..";
        print "options:";
        print "     --bit         ";
        print "     --percent     ";
        print " -c, --compact     suppress contex";
        print "     --csv         CSV output";
        print "     --rrd         use alternate names (<= 19 chars)";
        print " -n, --no-suffix   suppress contex suffix";
        print " -o, --oid <OID>   print OIDs instead values (for Perl-Scripts)";
        print "     --snmpd       running as snmpd helper";
        print "     --proc <PATH> use directory <PATH> instead /proc";
        print "     --sys  <PATH> use directory <PATH> instead /sys";
        print "     --no-tty      ";
        print "     --keep <SECS> ";
        print " -r, --repeat      ";
        print " -q, --quiet       quiet (no warnings)";
        print " -t, --timeout <SECS> ";
        print "keys:";
        print " sys[.CPUs[.INTERRUPTs]] load mem cpu[.CPUs] ipt {ip|tcp|udp|icmp}";
        print " netstat[.{tcp|udp|raw}] unix";
        print " {arp|clip_arp|dn_neigh|ndisc|rt}_cache {ip|nf}_conntrack";
        print " {if|route}[.IFACE] disk[.DEV] drbd[.MINOR] sensors[.CHIP]";
        print "returns:";
        print " =  0 success";
        print " &  1 no data";
        print " &  2 some data not available";
        print " & 64 error";
    }

    OPT["TIMEOUT"] = 0;
    OPT["REPEAT"] = 1;
    LAST["0"] = 0;
    SUM["0"] = 0;
    MAX["0"] = 0;
    LAST_CHANGE["0"] = 0;

    steps[0] = split("1:5:15:60:300:900", steps, /:/);

    SEC_BUF["0"] = 1 + steps[steps[0]];
#   MIN_BUF["0"] = 0;

    last_msec = 0;
    loop = 0;

    ESC["RST"] = "\033[m";
    ESC["BLD"] = "\033[1m";
    ESC["INC"] = "\033[31m";
    ESC["DEC"] = "\033[32m";
    ESC["STY"] = "\033[33m";
    ESC["HOM"] = "\033[H";
    ESC["CLR"] = "\033[2J";
    ESC["BEL"] = "\007";

  while (OPT["REPEAT"] --) {
    RECS = 0;
    REC = -1;
    TIME = systime();

    for (a = 1; a < ARGC; a++) {
        e = 0;
        if (ARGV[a] ~ /^-(c|-compact)$/) {
            OPT["COMPACT"] = 1;
        } else if (match(ARGV[a], /^--(bit|csv|percent|rrd|snmpd)$/, ary)) {
            OPT[toupper(ary[1])] = 1;
        } else if (ARGV[a] ~ /^-(n|-no-suffix)$/) {
            OPT["NO_SUFFIX"] = 1;
        } else if (ARGV[a] ~ /^-(o|-oid)$/) {
            OPT["OID"] = ARGV[++a];
        } else if (match(ARGV[a], /^--(keep|proc|sys|sensors-conf)$/, ary)) {
            OPT[toupper(ary[1])] = ARGV[++a];
        } else if (ARGV[a] ~ /^-(q|-quiet)$/) {
            OPT["QUIET"] = 1;
        } else if (ARGV[a] ~ /^-(r|-repeat)$/) {
            OPT["REPEAT"] = 1;
        } else if (ARGV[a] ~ /^-(R|-repeat)$/) { # FIXME
            OPT["REPEAT"] = 2;
        } else if (ARGV[a] ~ /^-(t|-timeout)$/) {
            OPT["REPEAT"] = 2;
            OPT["TIMEOUT"] = ARGV[++a];
        } else if (ARGV[a] ~ /^-(-no-tty)$/) {
            OPT["TTY"] = 0;
            for (k in ESC) ESC[k] = "";
        } else if (ARGV[a] ~ /\/.+/) {
            for (REC = 0; REC < RECS; REC ++) {
#                print "save '" SUFFIX[REC] "' in " ARGV[a] >> "/dev/stderr";
                out_csv(REC, ARGV[a]);
            }
            REC = -1;
            RECS = 0;
        } else if (match(ARGV[a], /^sys(\.([0-9]*)(\.([0-9]*))?)?$/, ary)) {
            stat(ary[2],ary[4]);
        } else if (ARGV[a] ~ /^load$/) {
            e = loadavg();
        } else if (ARGV[a] ~ /^mem/) {
            meminfo();
        } else if (match(ARGV[a], /^cpu(\.([0-9]+))?$/, ary)) {
            cpuinfo(ary[2]);
        } else if (match(ARGV[a], /^sensors(\.([a-z0-9-]+))?$/, ary)) {
            sensors(ary[2]);
        } else if (ARGV[a] ~ /^ipt$/) {
            FILE = OPT["PROC"] "/net/ip_conntrack";
            iptConntrack();
        } else if (match(ARGV[a], /^(ip|tcp|udp|icmp)$/, ary)) {
            FILE = OPT["PROC"] "/net/snmp";
            e = ipTable((ary[1] == "ip") ? "" : ary[1]);
        } else if (match(ARGV[a], /^if(\.(.+))?$/, ary)) {
            FILE = OPT["PROC"] "/net/dev";
            e = ifTable(ary[2]);
        } else if (match(ARGV[a],  /^route(\.(.+))?$/, ary)) {
            FILE = OPT["PROC"] "/net/rt_cache";
            e = routeCache(ary[2]);
        } else if (match(ARGV[a],  /^disk(\.(.+))?$/, ary)) {
            if (OPT["KVERSION"] == 0) {
                FILE = OPT["PROC"] "/version";
                e = getline OPT["_PROC_VERSION"] < (FILE);
                #if (match(OPT["_PROC_VERSION"], /Linux version (2)\.([0-9])\./, ary))
                OPT["KVERSION"] = (OPT["_PROC_VERSION"] ~ /2\.6/) ? 26 :24;
                close_FILE(e);
#                OPT["KVERSION"] = 26;
            }
            FILE = OPT["PROC"] "/partitions";
            e = diskIO(ary[2]);
            if (OPT["KVERSION"] >= 26) { # FIXME
                close_FILE(e);
                FILE = OPT["PROC"] "/diskstats";
                e = diskstats(ary[2]);
            }
        } else if (match(ARGV[a],  /^unix/, ary)) {
            FILE = OPT["PROC"] "/net/unix";
            e = unix();
        } else if (match(ARGV[a],  /^netstat(\.(.+))?/, ary)) {
            if (ary[2]) {
                netstat(ary[2]);
            } else {
                netstat("tcp");
                netstat("udp");
                netstat("raw");
            }
        } else if (match(ARGV[a],  /^drbd(\.([0-9]+))?/, ary)) {
            FILE = OPT["PROC"] "/drbd";
            e = drbd(ary[2]);
        } else if (match(ARGV[a],  /^((arp|clip_arp|dn_neigh|ndisc|rt)_cache)/, ary) \
               ||  match(ARGV[a],  /^((ip|nf)_conntrack)/, ary)) {
            FILE = OPT["PROC"] "/net/stat/" ary[1];
            e = net_cache(toname(ary[1]));
        } else {
            print "unsupported argument: " ARGV[a] >> "/dev/stderr";
            exit(64)
        }
        close_FILE(e);
#        delete ARGV[a];
    }
    if (OPT["KEEP"] != int(OPT["KEEP"])) {
        print "option --keep needs an integer: " OPT["KEEP"] >> "/dev/stderr";
        exit(64);
    }

    if (OPT["REPEAT"]) {
        printf ESC["HOM"] ESC["CLR"] ESC["BLD"];
        t = systime();
        printf "%-25s  ", strftime("%F %T %z", TIME);
        for (s = 1; s <= steps[0]; s++)
            if (int(steps[s] / 60) * 60 == steps[s])
                printf "  %5dm", -int(steps[s] / 60);
            else
                printf "  %5ds", -steps[s];
        printf ESC["RST"] " %s\n", TIME - T_START - loop;
    }
wr=0;
wa=0;

    if (OPT["PERCENT"])
        for (r = 0; r < RECS; r ++)  {
            if (NAME[r] != "sys") continue;
            ary[0] = split(VALS[r], ary, /;/);
            top[0] = split(VARS[r], top, /;/);
            percentsum["ssCpuRaw"] = 0;
            for (a = 1; a <= ary[0]; a ++)
                if (top[a] ~ /^ssCpuRaw/) percentsum["ssCpuRaw"] += ary[a];
#            printf "%s;\n", sum;
            VARS[r] = VARS[r] ";ssCpuRawTotal(C)";
            VALS[r] = VALS[r] ";" percentsum["ssCpuRaw"] ;
        }
#exit 0;
    for (r = 0; r < RECS; r ++)  {
        if (OPT["REPEAT"]) {
            ary[0] = split(VALS[r], ary, /;/);
            top[0] = split(VARS[r], top, /;/);
            for (a = 1; a <= ary[0]; a ++) {
                f = (OPT["BIT"] && gsub(/Oct(et)?/, "Bit", top[a])) ? 8 : 1;
                SEC_BUF[r"x"a"x"(loop%SEC_BUF[0])] = ary[a];
                is_counter = (top[a] ~ /\((C|C32|C64)\)/) ? 1 : 0;
                is_float   = (ary[a] ~ /\./) ? 1 : 0;

                if (0 && OPT["PERCENT"] && NAME[r] == "sys" && top[a] ~ /^ssCpuRaw/) {
#printf " %s %s \n", ary[a],percentsum["ssCpuRaw"];
                    ary[a] = (ary[a] * 100) / percentsum["ssCpuRaw"] ;
#                     is_counter = 0;
                }
                if (0 && SUFFIX[r] == "it8716") { # hack
                    wr = r;
                    if (top[a] == "temp3X(G)") wa = a;
                }
              for (s = 1; s <= steps[0]; s++) {
                # <REC> <VAR> <PTR>
                key = r"x"a"x"((loop+steps[steps[0]]-steps[s])%steps[steps[0]]);
                if (is_counter) {
                    now[s] = (LAST[key] == "") ? 0 : ary[a] - LAST[key];
                    if (now[s] < 0) now[s] += 0xffffffff;
                    now[s] = int(now[s] * f / steps[s]);
                } else { # FIXME: asume GAUGE, to average
                    SUM[r"x"a"x"s] += ary[a];
                    if ((loop+1) > steps[s]) {
                        if (steps[s] < SEC_BUF[0])
                            SUM[r"x"a"x"s] -= SEC_BUF[r"x"a"x"(SEC_BUF[0]+loop-steps[s])%SEC_BUF[0]];
                        now[s] = SUM[r"x"a"x"s] * f / steps[s];
                    } else
                        now[s] = SUM[r"x"a"x"s] * f / (loop+1);
                    if (is_float && now[s] == int(now[s])) # keep float point
                        now[s] = sprintf("%.1f", now[s]);
                }
              }
                if (is_counter) {
                    if (now[1] +0) LAST_CHANGE[r"x"a] = t;
                    LAST[r"x"a"x"(loop % steps[steps[0]])] = ary[a];
                } else {
                    if (now[1] +0 != LAST[r"x"a"x"((loop -1) % steps[steps[0]])])
                        LAST_CHANGE[r"x"a] = t;
                    LAST[r"x"a"x"(loop % steps[steps[0]])] = now[1] +0;
                }
                if (MAX[r"x"a] +0< now[1] +0) MAX[r"x"a] = now[1];

                if (OPT["KEEP"] && OPT["KEEP"] <= t - LAST_CHANGE[r"x"a])
                    continue;

                if (LAST_CHANGE[r"x"a] == t) printf ESC["BLD"];
                printf "%-29s" \
                    , ((SUFFIX[r] != "") ? SUFFIX[r] "."  : "") "" top[a];

                for (s = 1; s <= steps[0]; s++) {
                    if (loop +1 < steps[s] || (is_counter && !loop))
                        printf ESC["RST"] "%6s%s", "- ", (s < steps[0]) ? "  " : "";
                    else if (s == steps[0])
                            printf ESC["RST"] "%6s", human(now[s]);
                    else if (loop +1 < steps[s+1] || now[s] +0 == now[s+1] +0)
                        printf ESC["STY"] "%6s  ", human(now[s]);
                    else if (now[s] +0 < now[s+1] +0)
                        printf ESC["DEC"] "%6s <", human(now[s]);
                    else
                        printf ESC["INC"] "%6s >", human(now[s]);
                }

                printf ESC["RST"];
                s = (OPT["TTY"] && OPT["KEEP"]) \
                    ? 5 * (t - LAST_CHANGE[r"x"a]) / OPT["KEEP"] : 0;
                if (s)
                    printf "%s", str_repeat(".", s);
                else
                    printf "%5s", substr(human(MAX[r"x"a]),2);
                printf "\n";
            }
        } else {
            (!OPT["CSV"]) ? out_hum(r) : out_csv(r, "/dev/stdout");
        }
    }
    ENVIRON["LANG"] = "C";
    loop ++;
    if (OPT["REPEAT"]) {
        if(OPT["TIMEOUT"] && T_START + OPT["TIMEOUT"] <= systime())
            break;

        if (OPT["REPEAT"] == 1) {
            if (!system("read -t 1")) exit ;
        } else {
          if (0) {  # hack --
            ary[0] = split(VALS[wr], ary, /;/);
            top[0] = split(VARS[wr], top, /;/);
            printf  "# %s:%s %s %s\n", wr,wa, SUFFIX[wr], top[wa];
            for (i=0; i < 60; i++) { # SEC_BUF[0]; i++) {
                if (i == loop % SEC_BUF[0])
                    printf " (%s)", SEC_BUF[wr"x"wa"x"i];
                else if (i == (SEC_BUF[0] +loop -5) % SEC_BUF[0] && loop >= 5)
                    printf " {%s}", SEC_BUF[wr"x"wa"x"i];
                else if (((loop -i) % SEC_BUF[0]) < 5 && loop -i >0)
                    printf " [%s]", SEC_BUF[wr"x"wa"x"i];
                else
                    printf "  %s ", SEC_BUF[wr"x"wa"x"i];
            }
            for (i = 1; i <= 3; i++)
                printf "|%s -> %s\n" \
                    , SUM[wr"x"wa"x"i], SUM[wr"x"wa"x"i] / steps[i];
#            printf "|%s\n", OPT["REPEAT"];
          } # -- hack
            while (1) {
                if (system("sleep .20")) exit;

                FILE = "/proc/uptime";
                if ((c = getline < (FILE)) > 0) {
                    msec = gensub(/\./, "", "", $1); # FIXME:
                    close(FILE);
#                    printf "# %ld %ld\n", last_msec+20, msec;
                    # sleep canceld ?
                    if (last_msec && last_msec +20 > msec) exit 14;
                }
                last_msec = msec;
                if (loop * 100 < msec - U_START) break;
                if (OPT["TTY"]) printf ".";
            }
        }
    }
  }
    if (OPT["TTY"] && OPT["TIMEOUT"]) printf "%s", ESC["BEL"];
    exit or((RECS) ? 0 : 1, (WARNS) ? 2 : 0);
}
