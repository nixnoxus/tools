#! /bin/bash

# upstream url:
#  https://github.com/nixnoxus/tools/lib/queue_run.sh
#
# for usage sample see:
#  https://github.com/nixnoxus/tools/sample/queue_run.sh

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

# global varialbes
QUEUE_LOCK_FILE="${QUEUE_LOCK_FILE:-${TMPDIR:-/tmp}/${0##*/}-queue-log.lck}"
QUEUE_DURATION_FMT="%H:%M:%S"
QUEUE_TIME_FMT="%Y-%m-%dT%H:%M:%S%z"
QUEUE_PIDS=()

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

queue_wait () { # [Q]..
    local q rc=0
    # wait for jobs in specified queues
    for q in "$@"
    do  test -n "${QUEUE_PIDS[q]-}" || continue
        queue_log $q "\e[90m* waiting pids ${QUEUE_PIDS[q]# }\e[0m"
        wait ${QUEUE_PIDS[q]} || rc=$?
        QUEUE_PIDS[q]=""
    done
    # reap jobs in other queues
    for q in $(echo "${!QUEUE_PIDS[@]}" | tr ' ' '\n' | tac)
    do  test -n "${QUEUE_PIDS[q]-}" || continue
        kill -0 ${QUEUE_PIDS[q]} 2>/dev/null && continue
        queue_log $q "\e[90m* finished pids ${QUEUE_PIDS[q]# }\e[0m"
        wait ${QUEUE_PIDS[q]} || rc=$?
        QUEUE_PIDS[q]=""
    done
    return $rc
}

queue_run () { # <JOB>
    local job w q=0 job pid rc=0 s=$(date +%s)
    rc_max () { # <A> <B>
        test $1 -ge $2 && return $1 || return $2
    }
    for job in "$@"
    do  read q w < <(cb_job_queue_wait "$q" "$job")
        queue_wait $w || rc_max $? $rc || rc=$?
        queue_job_run "$q" "$job" &
        pid=$!
        QUEUE_PIDS[q]="${QUEUE_PIDS[q]-} $pid"
        queue_log $q "+ started $job pid $pid"
    done
    for q in $(echo "${!QUEUE_PIDS[@]}" | tr ' ' '\n' | tac)
    do  queue_wait $q || rc_max $? $rc || rc=$?
    done
    queue_log "" "${#@} jobs finished" "$rc" $[$(date +%s)-s]
    return $rc
}
