#! /bin/bash

# upstream url:
#  https://github.com/nixnoxus/tools/tree/main/lib/queue_run.sh
#
# for usage sample see:
#  https://github.com/nixnoxus/tools/tree/main/sample/queue_run.sh

QUEUE_VERSION=0.2

test -n "$BASH_VERSION" || {
    echo "error: bash need" >&2
    exit 2
}

#
# global variables
#
QUEUE_TMP_PREFIX="${QUEUE_TMP_PREFIX:-${TMPDIR:-/tmp}/${0##*/}-queue-log-$$}"
QUEUE_DURATION_FMT= #"%H:%M:%S"
QUEUE_DURATION_RED=60
QUEUE_TIME_FMT="%Y-%m-%dT%H:%M:%S%z"
QUEUE_FS='|'
QUEUE_PHASE_OUT_SIG=SIGUSR1
QUEUE_REPLAY_SPEED=30
QUEUE_STAT_BY="#q"  # {#j|#q|job|rc|rtime|stime|wtime}

case "${LANG-}" in
*.UTF-8)
    #QUEUE_PIPE_CHARS==" ┓┃┛"
    QUEUE_PIPE_CHARS=" ┌│└"
    ;;
*)
    QUEUE_PIPE_CHARS=" _|*"
    #QUEUE_PIPE_CHARS=" /|\\"
    #QUEUE_PIPE_CHARS=" ,|'"
    ;;
esac

QUEUE_PID=
QUEUE_START=

#
# sample callback functions
#

cb_job_queue_wait () { # <Q> <JOB>
    local q="$1" job="$2"
    case "$job" in
    *) echo 0 0 $q ;;
    esac
}

cb_rc_e () { # <RC>
    case "$rc" in
    0) echo -n "\e[32m" ;;
    1) echo -n "\e[33m" ;;
    ?*) echo -n "\e[31m" ;;
    esac
}

cb_indent () { # <Q>
    local q=0
    while [ $q -lt $1 ]
    do  let ++q
        echo -n " "
    done
}

cb_job_run () { # <Q> <JOB> [RC] [S]
    local q="$1" job="$2"
    sleep "$(calc "${4:-1}/$QUEUE_REPLAY_SPEED")"
    return ${3:-0}
}

cb_job_post_run () { # <Q> <JOB> <RC>
    return # FIXME: sample post run function
    local q="$1" job="$2" rc="$3" pre="$(cb_rc_e "$3")"
    pre="${QUEUE_TIME_FMT:+$(cb_datetime) }$(cb_indent "$q") $pre"
    case "$rc" in
    0) echo -e "${pre}I: job $job done\e[0m" ;;
    1) echo -e "${pre}W: job $job warns\e[0m" ;;
    *) echo -e "${pre}E: job $job failed\e[0m" ;;
    esac
}

if type -P gawk >/dev/null; then
    # with fractions of a second (via gawk)
    calc () { # <EXPR>
        gawk "BEGIN {printf \"%f\", $1}"
    }

    get_timestamp () {
        date +%s.%6N
    }
else
    # without fractions of a second
    calc () { # <EXPR>
        echo $[$1]
    }

    get_timestamp () {
        date +%s
    }
fi

get_timedelta () { # <TO> [FROM]
    calc "${2-$(get_timestamp)}"-"$1"
}

cb_duration () { # <SECONDS>
    if [ -n "$QUEUE_DURATION_FMT" ]; then
        date -u -d "@$(calc "$1*$QUEUE_REPLAY_SPEED")" "+$QUEUE_DURATION_FMT"
    else
        local s="$(calc "$1*$QUEUE_REPLAY_SPEED")"
        s="${s%.*}"
        test "$s" -ge 60 && echo "$[s/60]m$[s%60]s" || echo "${s}s"
    fi
}

cb_duration_c () { # <SECONDS>
    local s="$(calc "$1*$QUEUE_REPLAY_SPEED")" e=
    test "${s%.*}" -lt "${QUEUE_DURATION_RED:-60}" || e="\e[31m"
    echo -e "${e-}$(cb_duration "$1")${e:+\e[m}"
}

cb_datetime_relative () { # [TIMESTAMP]
    date -u -d @"$(calc "$(get_timedelta "$QUEUE_START" ${1+"$1"})*$QUEUE_REPLAY_SPEED")" "+$QUEUE_TIME_FMT"
}

cb_datetime_absolute () { # [TIMESTAMP]
    date ${1+-d "@$1"} "+$QUEUE_TIME_FMT"
}

exec {QUEUE_LOCK_FD}<>"$QUEUE_TMP_PREFIX.lock"
echo -n > "$QUEUE_TMP_PREFIX.pids"

trap 'rm -f "$QUEUE_TMP_PREFIX."{lock,pids}' EXIT
trap 'kill -TERM $$' SIGINT

#
# queue functions
#

queue_log () { # [-n] <Q> <MESSAGE> [RC] [S]
    local flock=true
    test "$1" = -n && shift || flock=flock

    local q="$1" msg="$2" rc="${3-}" s="${4-}" pipes=

    local qi j c
    test -n "${QUEUE_PIPE_CHARS-}" && for qi in $(seq 0 $q_max)
    do  c=0
        [ -n "$rc" -a  "$qi" = "$q" ] && c=3 || for j in ${!jobs[*]}
        do  test "${j2q[j]}" = "$qi" -a "${j2pid[j]-N}" != N -a -z "${j2rc[j]-}" || continue
            kill -0 "${j2pid[j]-}" 2>/dev/null || continue
            test "$qi" = "$q" && c=1 || c=2
        done
        pipes="$pipes${QUEUE_PIPE_CHARS:$c:1} "
    done

    msg="$pipes${q:+$(cb_indent "$q")[Q=$q]} $msg"
    rc="${rc:+ with rc $(cb_rc_e "$rc")$rc\e[m}"
    s="${s:+ after $(cb_duration_c "$s")}"
    "$flock" -x "$QUEUE_LOCK_FD"
    echo -e "${QUEUE_TIME_FMT:+$(cb_datetime) }$msg$rc$s\e[m"
    "$flock" -u "$QUEUE_LOCK_FD"
}

queue_job_run () { # <Q> <JOB> [RC] [S]
    local q="$1" job="$2" s="$(get_timestamp)" rc=0
    shift 2

    cb_job_run "$q" "$job" "$@" || rc=$?
    s="$(get_timedelta "$s")"

    flock -x "$QUEUE_LOCK_FD"
    if [ "$$" != "$BASHPID" -a -n "${QUEUE_PIPE_CHARS-}" ]; then
        read -a j2pid < "$QUEUE_TMP_PREFIX.pids" || :
    fi
    queue_log -n "$q" "- $job finished" "$rc" "$s"
    cb_job_post_run "$q" "$job" "$rc" || :
    flock -u "$QUEUE_LOCK_FD"
    return $rc
}

queue_run () { # <JOB>
    local jobs j=0 q=0 wq wj w_ary l=0 q_max=0
    local j2q=() j2wj=() j2s=() j2r=()
    QUEUE_PID=$$
    QUEUE_START="$(get_timestamp)"

    is_func () { # <FUNC>
        test "$(type -t "$1")" = function
    }

    get_index () { # <NAME> <ITEM>..
        local name="$1" i=0
        shift 1
        local ary=("$@")
        while [ $i -lt ${#ary[*]} ] && [ "${ary[i]}" != "$name" ]
        do  let ++i
        done
        if [ $i -lt ${#ary[*]} ]; then
            echo "$i"
        else
            echo "ERROR: column '$name' does not exists" >&2
            return 2
        fi
    }

    case "$1" in
    --replay) # <TABLE-FILE>
        is_func cb_datetime || {
            QUEUE_TIME_FMT='%H:%M:%S.%3N'
            cb_datetime() { cb_datetime_relative "$@"; }
        }
        parse_file () {
            local ary=() i _j _q _job _rc _s _wj
            IFS="$QUEUE_FS" read -a ary
            _j=$(get_index "#j" "${ary[@]}")
            _q=$(get_index "#q" "${ary[@]}")
            _job=$(get_index "job" "${ary[@]}")
            _rc=$(get_index "rc" "${ary[@]}")
            _s=$(get_index "rtime" "${ary[@]}")
            _wj=$(get_index "blk by #j" "${ary[@]}")
            while IFS="$QUEUE_FS" read -a ary
            do  let j="${ary[_j]-}" 1 2>/dev/null || continue
                let j2q[j]="${ary[_q]}" 1
                let j2r[j]="${ary[_rc]}" 1
                jobs[j]="${ary[_job]}"
                j2wj[j]="${ary[_wj]-}"
                let j2s[j]="${ary[_s]}" 1 2>/dev/null ||
                    j2s[j]=$(date -u -d "1970-01-01 ${ary[_s]}" +%s)
            done
        }
        local a='\(^\|'"$QUEUE_FS"'\)' b='\('"$QUEUE_FS"'\|$\)'
        parse_file < <(sed \
            's@ *'"$a"' *@\1@g
            ;s@'"$a"'blocked by #j'"$b"'@\1blk by #j\2@
            ;:1;s@'"$a"'\([0-9]\+\)h\([0-5]\?[0-9]\)m\([0-5]\?[0-9]\)s'"$b"'@\1\2:\3:\4\5@g;t1
            ;:2;s@'"$a"'\([0-9]\+\)m\([0-5]\?[0-9]\)s'"$b"'@\100:\2:\3\4@g;t2
            ;:3;s@'"$a"'\([0-9]\+\)s'"$b"'@\1\2\3@g;t3
            ' "$2")
        ;;
    *)
        QUEUE_REPLAY_SPEED=1
        is_func cb_datetime || cb_datetime() { cb_datetime_absolute "$@"; }
        jobs=("$@")
        # prepare queues
        for j in ${!jobs[*]}
        do  read q w_ary < <(cb_job_queue_wait "$q" "${jobs[j]}")
            for wq in $w_ary
            do  for wj in ${!j2q[*]}
                do  test ${j2q[wj]} = $wq && j2wj[j]="${j2wj[j]-} $wj"
                done
            done
            j2q[j]="$q"
            j2wj[j]="${j2wj[j]-}"
            #echo "$(cb_indent "${j2q[j]}")[job $j ${jobs[$j]} queue ${j2q[j]} waits for job ${j2wj[j]}"
        done
        ;;
    esac

    for j in ${!jobs[*]}
    do  test $l -ge ${#jobs[j]} || l=${#jobs[j]}
        test $q_max -ge ${j2q[j]} || q_max=${j2q[j]}
    done

    # run jobs in queues
    local rc=0 j2pid=() j2rc=() j2run=() j2fin=() j2bj=()

    phase_out () {
        local j
        for j in ${!jobs[*]}
        do  test -n "${j2pid[j]-}" && continue
            j2pid[j]=${j2rc[j]-N}
            j2rc[j]=${j2rc[j]-N}
        done
        queue_log "" "\e[90m* .. signal $QUEUE_PHASE_OUT_SIG recieved, phase out ..\e[0m"
    }

    can_run () { # <J>
        local j="$1" wj
        test -z "${j2pid[j]-}" && for wj in ${j2wj[j]-}
        do  test -n "${j2pid[wj]-}" || return 1
            test -n "${j2rc[wj]-}" || {
                j2bj[j]="$wj"
                return 1
            }
        done
    }

    update_pids () {
        local wj
        flock -x "$QUEUE_LOCK_FD"
        for wj in ${!jobs[*]}
        do  if [ -n "${j2pid[wj]-}" -a -z "${j2rc[wj]-}" ]; then
                echo -n "${j2pid[wj]} "
            else
                echo -n "N "
            fi
        done > "$QUEUE_TMP_PREFIX.pids"
        flock -u "$QUEUE_LOCK_FD"
    }

    trap phase_out "$QUEUE_PHASE_OUT_SIG"

    while [ ${#j2rc[*]} -lt ${#jobs[*]} ]
    do  for wj in ${!j2pid[*]}
        do  kill -0 ${j2pid[wj]} 2>/dev/null && continue || :
            test -z "${j2rc[wj]-}" || continue
            wait ${j2pid[wj]} && j2rc[wj]=0 || j2rc[wj]=$?
            j2fin[wj]="$(get_timestamp)"
            test $rc -ge ${j2rc[wj]} || rc=${j2rc[wj]}
            #queue_log ${j2q[wj]} "\e[90m* ${jobs[wj]} finished with rc ${j2rc[wj]}\e[0m"
        done
        for j in ${!jobs[*]}
        do  can_run "$j" || continue
            queue_job_run "${j2q[j]}" "${jobs[j]}" ${j2r[j]-} ${j2s[j]-} &
            j2pid[j]=$!
            j2run[j]="$(get_timestamp)"
            test -n "${QUEUE_PIPE_CHARS-}" && update_pids
            queue_log ${j2q[j]} "+ ${jobs[j]} started with pid ${j2pid[j]}"
        done
        j="$(get_timestamp)"
        wait -n || :
        j="$(get_timedelta "$j")"
        test "${j%.*}" = 0 || queue_log "" "\e[90m* wait finished" "" "$j"
    done
    s="$(get_timedelta "$QUEUE_START")"
    queue_log "" "${#jobs[*]} jobs finished" "$rc" "$s"
    trap - "$QUEUE_PHASE_OUT_SIG"

    test -n "${QUEUE_STAT_BY-}" || return $rc
    (echo -n 1>&3 ) 2>&- || exec 3>&1

    # some statistics
    local d="$(cb_duration "$s")" || :
    test ${#d} -gt 5 && d=${#d} || d=5
    local t="$(cb_datetime "${j2run[0]}")"
    test ${#t} -gt 5 && t=${#t} || t=5
    local head=() fmt=() j2w=()

    print_head () { # <FIELD>..
        head=("$@")
        local i fs=""
        for i in ${!head[*]}
        do  case "${head[i]}" in
            start)   fmt[i]="%-${t}s" ;;
            ?time)   fmt[i]="%${d}s" ;;
            *job)    fmt[i]="%-${l}s" ;;
            "#"*|rc) fmt[i]="%3s" ;;
            *)       fmt[i]="%s" ;;
            esac
            printf "$fs${fmt[i]}" "${head[i]}"
            fs="$QUEUE_FS"
        done
        printf "\n"
    }

    print_line () { # <J>
        local j="$1" i fs=
        for i in ${!head[*]}
        do  printf "$fs${fmt[i]}" "$(case "${head[i]}" in
            start)        cb_datetime "${j2run[j]}" ;;
            '#j')         echo "$j" ;;
            '#q')         echo "${j2q[j]}" ;;
            job)          echo "${jobs[j]}" ;;
            rc)           echo "${j2rc[j]}" ;;
            rtime)        cb_duration "$(calc "${j2fin[j]}-${j2run[j]}")" ;;
            stime)        cb_duration "$(calc "${j2run[j]}-${j2run[0]}")" ;;
            wtime)        cb_duration "${j2w[j]}" ;;
            'blk by job') echo "${j2bj[j]:+${jobs[${j2bj[j]}]}}" ;;
            'blk by #j')  echo "${j2wj[j]}" ;;
            esac)"
            fs="$QUEUE_FS"
        done
        printf "\n"
    }

    for q in $(seq 0 $q_max)
    do  local last_fin="${j2run[0]}"
        for j in ${!jobs[*]}
        do  test -n "${j2fin[j]-}" -a "${j2q[j]}" = "$q" || continue
            j2w[j]="$(calc "${j2run[j]}-$last_fin")"
            last_fin="${j2fin[j]}"
        done
    done

    echo -ne "\e[90m"
    print_head ${QUEUE_TIME_FMT:+start} "#j" "#q" "job" "rc" "stime" "rtime" "wtime" "blk by job" "blk by #j" >&3
    if [ "$QUEUE_STAT_BY" = "#q" ]; then
        for q in $(seq 0 $q_max)
        do  local rtime_sum=0 wtime_sum=0
            printf "\n"
            for j in ${!jobs[*]}
            do  test -n "${j2fin[j]-}" -a "${j2q[j]}" = "$q" || continue
                print_line "$j"
                wtime_sum="$(calc "$wtime_sum+${j2w[j]}")"
                rtime_sum="$(calc "$rtime_sum+${j2fin[j]}-${j2run[j]}")"
            done
            local i fs=
            for i in ${!head[*]}
            do  printf "$fs${fmt[i]}" "$(case "${head[i]}" in
                rtime) cb_duration "$rtime_sum" ;;
                wtime) cb_duration "$wtime_sum" ;;
                esac)"
                fs=" "
            done
            printf "\n"
        done
    else
        local n=$[1+$(get_index "$QUEUE_STAT_BY" "${head[@]}")]
        case "$QUEUE_STAT_BY" in
        ?time)
            QUEUE_DURATION_FMT="${QUEUE_DURATION_FMT:-%ss}"
            n="${n}n"
            ;;
        esac
        for j in ${!jobs[*]}
        do  test -z "${j2fin[j]-}" || print_line "$j"
        done | sort -t "$QUEUE_FS" -k$n
    fi >&3
    echo -ne "\e[0m"
    return $rc
}
