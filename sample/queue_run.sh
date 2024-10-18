#! /bin/bash

# usage sample for: https://github.com/nixnoxus/tools/tree/main/lib/queue_run.sh

set -u -e

. "${0%/*}"/../lib/queue_run.sh

QUEUE_TIME_FMT=
QUEUE_DURATION_FMT="%ss"

JOBS=(
    queue_0_job_0
    queue_0_job_1

    queue_3_wait_0_job_2

    queue_2_wait_0_job_3
    queue_2_wait_0_job_4
    
    queue_0_wait_0_job_5

    queue_1_wait_2_3_job_6
    queue_1_wait_2_3_job_7

    queue_1_wait_2_0_job_8
    queue_0_wait_0_job_9
    queue_0_wait_0_1_2_3_job_10
)

cb_job_queue_wait () { # <Q> <JOB>
    local q="$1" job="$2"
    case "$job" in
    queue_3_wait_0_job*)   echo 3 0 ;;
    queue_2_wait_0_job*)   echo 2 0 ;;
    queue_1_wait_2_3_job*) echo 1 2 3 ;;
    queue_0_wait_0_1_2_3_job*)   echo 0 0 1 2 3;;
    queue_0_wait_0_job*)   echo 0 0 ;;
    *)                     echo 0 0 $q ;;
    esac
}

cb_job_run () { # <Q> <JOB>
    local q="$1" job="$2"
    sleep $[1+q]
    #echo "output from $job in Q=$q"
    test "$job" = queue_1_wait_2_0_job_8 && kill -"$QUEUE_PHASE_OUT_SIG" "$QUEUE_PID"
    return $[q%3]
}

cb_job_post_run () { # <Q> <JOB> <RC>
    local q="$1" job="$2" rc="$3" pre="$(cb_rc_e "$3")"
    #pre="$(date +"$QUEUE_TIME_FMT")$(cb_indent "$q") $pre"
    case "$rc" in
    0) echo -e "${pre}I: job $job done\e[0m" ;;
    1) echo -e "${pre}W: job $job warns\e[0m" ;;
    *) echo -e "${pre}E: job $job failed\e[0m" ;;
    esac
    #test "$job" = queue_0_wait_0_job_5 && kill -"$QUEUE_PHASE_OUT_SIG" "$QUEUE_PID"
}

queue_run "${JOBS[@]}"
