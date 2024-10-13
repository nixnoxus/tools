#! /bin/bash
CHARS=
CHARS="${CHARS}"'!"#$%&()*+,-./'
CHARS="${CHARS}0123456789"
CHARS="${CHARS}:;<=>?@"
CHARS="${CHARS}ABCDEFGHIJKLMNOPQRSTUVWXYZ"
CHARS="${CHARS}[]^_"
CHARS="${CHARS}abcdefghijklmnopqrstuvwxyz"
CHARS="${CHARS}{|}"

PW=
while [ ${#PW} -lt ${1:-8} ]
do  PW="$PW${CHARS:$[RANDOM%${#CHARS}]:1}"
done
echo "$PW"
