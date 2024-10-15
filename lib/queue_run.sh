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
    s="${s:+ after $(date -u -d "@$s" "+$QUEUE_DURATION_FMT")}"
    "${lock_cmd[@]}" echo -e "$(date "+$QUEUE_TIME_FMT") $msg$rc$s"
}

queue_job_run () { # <Q> <JOB>
    local q="$1" job="$2" s=$(date +%s) rc=0

    cb_job_run "$q" "$job" || rc=$?
    let s=$(date +%s)-s || :

    local msg="- $job finished"
    flock -x "$QUEUE_LOCK_FD"
    queue_log -n "$q" "$msg" "$rc" "$s"
    cb_job_post_run "$q" "$job" "$rc"
    flock -u "$QUEUE_LOCK_FD"
    return $rc
}

queue_run () { # <JOB>
    local jobs=("$@") j q=0 wq wj w_ary rc=0 s=$(date +%s)
    local j2q=() j2wj=() j2pid=() j2rc=()
    for j in ${!jobs[*]}
    do  read q w_ary < <(cb_job_queue_wait "$q" "${jobs[j]}")
        for wq in $w_ary
        do  for wj in ${!j2q[*]}
            do  test ${j2q[wj]} = $wq && j2wj[j]="${j2wj[j]-} $wj"
            done
        done
        j2q[j]="$q"
        j2wj[j]="${j2wj[j]-}"
        #echo "job $j ${jobs[$j]} queue ${j2q[j]} waits for job ${j2wj[j]}"
    done
    while [ ${#j2rc[*]} -lt ${#jobs[*]} ]
    do  for wj in ${!j2pid[*]}
        do  kill -0 ${j2pid[wj]} 2>/dev/null && continue || :
            test -z "${j2rc[wj]-}" || continue
            wait ${j2pid[wj]} && j2rc[wj]=0 || j2rc[wj]=$?
            test $rc -ge ${j2rc[wj]} || rc=${j2rc[wj]}
            #queue_log ${j2q[wj]} "\e[90m* ${job[wj]} finished with rc ${j2rc[wj]}\e[0m"
        done
        for j in ${!jobs[*]}
        do  test -z "${j2pid[j]-}" || continue # not running
            for wj in ${j2wj[j]-}
            do  test -n "${j2pid[wj]-}" -a -n "${j2rc[wj]-}" || break 2
            done
            queue_job_run "${j2q[j]}" "${jobs[j]}" &
            j2pid[j]=$!
            queue_log ${j2q[j]} "+ ${jobs[j]} started with pid ${j2pid[j]}"
        done
        wait -n || :
    done
    queue_log "" "${#jobs[*]} jobs finished" "$rc" "$[$(date +%s)-s]"
    return $rc
}
