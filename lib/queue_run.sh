#! /bin/bash

# upstream url:
#  https://github.com/nixnoxus/tools/tree/main/lib/queue_run.sh
#
# for usage sample see:
#  https://github.com/nixnoxus/tools/tree/main/sample/queue_run.sh

test -n "$BASH_VERSION" || {
    echo "error: bash need" >&2
    exit 2
}

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
    do  let q++
        echo -n " "
    done
}

cb_job_run () { # <Q> <JOB>
    local q="$1" job="$2"
    sleep $[1+q]
    return $[q%3]
}

cb_job_post_run () { # <Q> <JOB> <RC>
    local q="$1" job="$2" rc="$3" pre="$(cb_rc_e "$3")"
    pre="$(date +"$QUEUE_TIME_FMT")$(cb_indent "$q") $pre"
    case "$rc" in
    0) echo -e "${pre}I: job $job done\e[0m" ;;
    1) echo -e "${pre}W: job $job warns\e[0m" ;;
    *) echo -e "${pre}E: job $job failed\e[0m" ;;
    esac
}

# global variables
QUEUE_LOCK_FILE="${QUEUE_LOCK_FILE:-${TMPDIR:-/tmp}/${0##*/}-queue-log.lck}"
QUEUE_DURATION_FMT="%H:%M:%S"
QUEUE_TIME_FMT="%Y-%m-%dT%H:%M:%S%z"
QUEUE_FS='|'
QUEUE_PID=
QUEUE_PHASE_OUT_SIG=SIGUSR1

cb_duration () { # <SECONDS>
    date -u -d "@$1" "+$QUEUE_DURATION_FMT"
}

exec {QUEUE_LOCK_FD}<>"$QUEUE_LOCK_FILE"

#
# queue functions
#

queue_log () { # [-n] <Q> <MESSAGE> [RC] [S]
    local lock_cmd=()
    test "$1" = -n && shift || lock_cmd=(flock "$QUEUE_LOCK_FILE")
    local q="$1" msg="$2" rc="${3-}" s="${4-}"
    msg="${q:+$(cb_indent "$q")[Q=$q]} $msg"
    rc="${rc:+ with rc $(cb_rc_e "$rc")$rc\e[0m}"
    s="${s:+ after $(cb_duration "$s")}"
    "${lock_cmd[@]}" echo -e "$(date "+$QUEUE_TIME_FMT") $msg$rc$s"
}

queue_job_run () { # <Q> <JOB>
    local q="$1" job="$2" s=$(date +%s) rc=0

    cb_job_run "$q" "$job" || rc=$?
    let s=$(date +%s)-s || :

    local msg="- $job finished"
    flock -x "$QUEUE_LOCK_FD"
    queue_log -n "$q" "$msg" "$rc" "$s"
    cb_job_post_run "$q" "$job" "$rc" || :
    flock -u "$QUEUE_LOCK_FD"
    return $rc
}

queue_run () { # <JOB>
    local jobs=("$@") j q=0 wq wj w_ary s=$(date +%s) l=0
    local j2q=() j2wj=()
    QUEUE_PID=$$

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
        test $l -ge ${#jobs[j]} || l=${#jobs[j]}
        #echo "$(cb_indent "${j2q[j]}")[job $j ${jobs[$j]} queue ${j2q[j]} waits for job ${j2wj[j]}"
    done

    # run jobs in queues
    local rc=0 j2pid=() j2rc=() j2run=() j2fin=() j2blk=()
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
            test -n "${j2blk[j]-}" || j2blk[j]=$(date +%s)
            test -n "${j2rc[wj]-}" || return 1
        done
    }
    trap phase_out "$QUEUE_PHASE_OUT_SIG"
    while [ ${#j2rc[*]} -lt ${#jobs[*]} ]
    do  for wj in ${!j2pid[*]}
        do  kill -0 ${j2pid[wj]} 2>/dev/null && continue || :
            test -z "${j2rc[wj]-}" || continue
            wait ${j2pid[wj]} && j2rc[wj]=0 || j2rc[wj]=$?
            j2fin[wj]=$(date +%s)
            test $rc -ge ${j2rc[wj]} || rc=${j2rc[wj]}
            #queue_log ${j2q[wj]} "\e[90m* ${jobs[wj]} finished with rc ${j2rc[wj]}\e[0m"
        done
        for j in ${!jobs[*]}
        do  can_run "$j" || continue
            queue_job_run "${j2q[j]}" "${jobs[j]}" &
            j2pid[j]=$!
            j2run[j]=$(date +%s)
            queue_log ${j2q[j]} "+ ${jobs[j]} started with pid ${j2pid[j]}"
        done
        wait -n || :
    done
    let s=$(date +%s)-s || :
    queue_log "" "${#jobs[*]} jobs finished" "$rc" "$s"
    trap - "$QUEUE_PHASE_OUT_SIG"

    # some statistics
    local f="%3s %3s %-${l}s %3s %${s}s %${s}s %${s}s"
    s="$(cb_duration "$s")" || :
    test ${#s} -gt 6 && s=${#s} || s=6
    printf "\e[90m${f// /$QUEUE_FS}${QUEUE_FS}%s\n" \
        "#j" "#q" "job" "rc" "rtime" "wtime" "btime" "blocked by #j"
    for j in ${!jobs[*]}
    do  test -n "${j2fin[j]-}" || continue
        printf "${f// /$QUEUE_FS}" "$j" "${j2q[j]}" \
            "${jobs[j]}" ${j2rc[j]} \
            "$(cb_duration $[${j2fin[j]}-${j2run[j]}])" \
            "$(cb_duration $[${j2run[j]}-${j2run[0]}])" \
            "$(cb_duration $[${j2run[j]}-${j2blk[j]-${j2run[j]}}])"
        printf "${QUEUE_FS}%s" "${j2wj[j]}"
        #for wj in ${j2wj[j]}
        #do  printf " %s" "${jobs[wj]}"
        #done
        printf "\n"
    done
    echo -en "\e[0m"
    return $rc
}
