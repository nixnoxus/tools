#! /bin/bash

error () {
    echo "$*" >&2
    exit 2
}
int2bits () { # <VAL> [SPC [BITS [DOT]]]
    local val="$1" spc="${2:-}" bit="${3:-32}" dot="${4:-8}"
    while [ $bit -gt 0 ]
    do    let bit=bit-1
    echo -n "$[($val&(2**$bit))>>$bit]"
    [ "$[32-bit]" = "$spc" ] && echo -n " " #|| {
    [ "$bit" -gt 0 -a "$dot" -gt 0 ] && [ "$[bit%dot]" -eq 0 ] && echo -n .
    #}
    done
    echo
}
int2ipaddr () { # <VAL>
    echo $[($1>>24)&255].$[($1>>16)&255].$[($1>>8)&255].$[$1&255]
}
ipaddr2int () { # <ipaddr>
    local oct
    oct=(${1//./ })
    echo $[${oct[0]}<<24|${oct[1]}<<16|${oct[2]}<<8|${oct[3]}]
}
_ipcalc_between () {
    local last_b="$1" b="$2"

    if [ "$b" -lt "$last_b" ]; then
        let "i=(i&$[16#ffffffff>>(b)<<(b)])+$[2**$last_b]"
    else
    echo
    while [ $last_b -lt $b ]
    do
        let "i=(i&$[16#ffffffff>>($last_b)<<($last_b)])+$[2**last_b]"
        while [ $[i&(2**last_b)] = 0 ]
            do    let last_b=last_b+1
            done
            [ $last_b = $b ] && break
        echo "remaining $(int2ipaddr $i) to $(int2ipaddr $[i+2**last_b-1]) /$[32-last_b]"
        done
    fi
}
ipcalc () { # <NET>
    local i= bits=32 m=$(ipaddr2int 255.255.255.255) fmt="%-9s %-20s %s %s\n"

    case "$1" in
    *.*.*.*/[0-9]|\
    *.*.*.*/[1-2][0-9]|\
    *.*.*.*/3[0-2])
        bits="${1##*/}"
        i=$(ipaddr2int "${1%/*}")
        m="$[16#ffffffff>>(32-bits)<<(32-bits)]"
        ;;
    *.*.*.*/*.*.*.*)
        m=$(ipaddr2int "${1##*/}")
        let i=32 bits=0
        while [ $i -gt 0 ]
        do  let i=i-1 'm&(2**i)' || break
            let bits=bits+1
        done
        let 'm&(2**(32-bits)-1)' && error "Illegal netmask $(int2ipaddr $m)"
        i=$(ipaddr2int "${1%/*}")
        ;;
    *.*.*.*-*.*.*.*)
        i=$(ipaddr2int "${1%-*}")
        m=$(ipaddr2int "${1##*-}")
        local x
        let x=32 bits=0
        while [ $x -gt 0 ]
        do  let x=x-1
            [ $[i&(2**x)] = $[m&(2**x)] ] || break
            let bits=bits+1
        done
        m="$[16#ffffffff>>(32-bits)<<(32-bits)]"
        #    echo $(int2ipaddr "$i")
        #    echo "$bits"
        #    echo $(int2ipaddr "$m")
        #    return
        ;;
    *.*.*.*)
        i=$(ipaddr2int "$1")
        ;;
    *)  error "usage: $0 ipcalc <IPv4-ADDRESS>[/NETMASK] [SPLIT-IP-COUNT].."
        ;;
    esac
    shift

    local r=$[2**(32-bits)] n=$[i&m] w="$[16#ffffffff^$m]" p=0
    [ "$bits" -lt 31 ] && p=1 # FIXME: is /31 valid ?

    printf "$fmt" "address"   $(int2ipaddr $i)          $(int2bits $i $bits)
    printf "$fmt" "netmask"  "$(int2ipaddr $m) = $bits" $(int2bits $m $bits)
    printf "$fmt" "wildcard"  $(int2ipaddr $w)          $(int2bits $w $bits)
    printf "$fmt" "network"   $(int2ipaddr $n)/$bits    $(int2bits $n $bits)
    printf "$fmt" "host min"  $(int2ipaddr $[n+p])      $(int2bits $[n+p] $bits)
    printf "$fmt" "host max"  $(int2ipaddr $[n+r-1-p])  $(int2bits $[n+r-1+p] $bits)
    printf "$fmt" "broadcast" $(int2ipaddr $[n+r-1])    $(int2bits $[n+r-1] $bits)
    printf "$fmt" "hosts"     $[r-p-p]

    local b last_b=
    [ $# -ge 1 ] && echo -e "\nsplit into:"
    while [ $# -ge 1 ]
    do  case "$1" in
        1|2)  b=$[$1-1] ;;
        [1-9]|[1-9]*[0-9])
            b=2
            while [ $[2**b-2] -lt $1 ]
            do    let b=b+1
            done
            ;;
        *)  error "Illegal num of hosts: $1" ;;
        esac
        [ $b -ge $[32-bits] ] && error "error: /$[32^b] is greater than /$bits"
        [ -n "$last_b" ] && _ipcalc_between "$last_b" "$b"
        echo
#        echo "ip range from $(int2ipaddr $i) to $(int2ipaddr $[i+2**b-1]) /$[32-b] ($b host bits: $[2**b] >= $1)"
        shift
        ipcalc $(int2ipaddr $i)/$[32-b]
        last_b="$b"
    done
    [ -n "$last_b" ] && _ipcalc_between "$last_b" $[32-bits]
}

ipcalc "$@"
