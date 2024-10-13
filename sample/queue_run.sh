#! /bin/bash

# usage sample for: https://github.com/nixnoxus/tools/lib/queue_run.sh

set -u -e

. "${0%/*}"/../lib/queue_run.sh

JOBS=(
    queue_0_job_0
    queue_0_job_1

    queue_3_wait_0_job_0

    queue_2_wait_0_job_0
    queue_2_wait_0_job_1
    
    queue_1_wait_2_3_job_0
)

cb_job_queue_wait () { # <Q> <JOB>
    local q="$1" job="$2"
    case "$job" in
    queue_3_wait_0_job*)   echo 3 0 ;;
    queue_2_wait_0_job*)   echo 2 0 ;;
    queue_1_wait_2_3_job*) echo 1 2 3 ;;
    *)                     echo 0 0 $q ;;
    esac
}

cb_job_run () { # <Q> <JOB>
    local q="$1" job="$2"
    sleep $[1+q]
    echo "output from $job in Q=$q"
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
}

queue_run "${JOBS[@]}"
