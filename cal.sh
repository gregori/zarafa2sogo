#!/bin/bash
set -e

TMPD=/tmp/cadaver
CADAVER=/usr/bin/cadaver
DIRLIST=$(mktemp)
FILELIST=$(mktemp)
RECVLIST=$(mktemp)

function cleanUp {
  rm -rf "$DIRLIST"
  rm -rf "$FILELIST"
  rm -rf "$RECVLIST"
  rm -rf "$TMPD"
}

# Just a fancy spin
function spin {
  MSG=$1
  PID=$2

  spin='-\|/'

  i=0
  while kill -0 $PID 2>/dev/null
  do
    i=$(( (i+1) %4 ))
    printf "\r%s ... %s" "$MSG" "${spin:$i:1}" >&2
    sleep .1
  done
}

function ProgressBar {
# Process data
    _str=${1}
    _progress=$(echo "(${2}*100/${3}*100)/100" | bc)
    _done=$(echo "(${_progress}*4)/10" | bc)
    _left=$(echo "40-$_done" | bc)
# Build progressbar string lengths
    _fill=$(printf "%${_done}s")
    _empty=$(printf "%${_left}s")

# 1.2 Build progressbar strings and print the ProgressBar line
# 1.2.1 Output example:
# 1.2.1.1 Progress : [########################################] 100%
    >&2 printf "\r$_str [${_fill// /#}${_empty// /-}] ${_progress}%%"
}

function prepareEnv {
  if [[ -e $TMPD ]]; then
    rm -rf $TMPD
  fi

  mkdir $TMPD && cd $TMPD

  touch $DIRLIST
  touch $FILELIST
  touch $RECVLIST
}

function getDirectory {
  # Zarafa keeps more than one collection as calendars. The default is the second one
#  local __dir=$($CADAVER $1 << EOC | awk 'NR==4' | awk '{print $2}'
  $CADAVER $1 << EOC | grep -v caldav | grep -v Connection | awk '{print $2}' > $DIRLIST
     ls
     exit
EOC
  

  echo "$__dir"

}

function listRemote {
  local __url=$1
 
  #fetch filelist:
  for dir in $(cat "$DIRLIST"); do
#    $CADAVER "$__url" << EOC | grep .ics | sed 's/.ics.*/.ics/' | sed 's/\ *//' | awk '{print $dir"/"$2}' >> "$FILELIST" &
    $CADAVER "$__url" << EOC | grep .ics | sed 's/.ics.*/.ics/' | sed 's/\ *//' | awk '{print $2}' | sed -e "s/^/$dir\//" >> "$FILELIST" & 
      ls $dir
      exit
EOC
  local pid=$!

  spin "Listing files" "$pid"
  done
}

function getFiles {
  local __url=$1

  local GETFILES=$(while read -r p; do echo "get $p"; done < "$FILELIST")
  $CADAVER "$__url" << EOA > $RECVLIST &
    $GETFILES 
    exit
EOA

  local pid=$!
  local END=$(wc -l < "$FILELIST")

  echo
  
  while kill -0 $pid 2>/dev/null
  do
    local N=$(grep Downloading "$RECVLIST" | wc -l)
    ProgressBar "Downloading files ..." "$N" "$END"
    sleep 1
  done

  NLOCAL=$(ls *.ics | wc -l)

  DIFF=$(echo "$END-$NLOCAL" | bc)

  if [[ $DIFF -gt 0 ]]; then
    echo
    echo "$DIFF files were not downloaded."
  fi
}

function sendFiles {
  local __url=$1
  local N=0
  local END=$(ls *.ics | wc -l)
  local ERR=0

  echo
  for file in *.ics; do
    # We need to set the content-type in order for sogo to accept tthe incoming ics file
    local CODE=i$(curl -n -s -H"Content-Type:$(file -bi "$file")" --upload-file "$file" "$__url" -o /dev/null -w "%{http_code}")
    if [[ $? -ne 0 ]]; then 
      ERR=$((ERR+1))
      echo "$file - $CODE" >&2
    fi
    N=$((N+1))
    ProgressBar "Sending files ..." "$N" "$END"
  done

  if [[ $ERR -gt 0 ]]; then
    echo
    echo "$ERR files could not be sent."
  fi
}

ZARAFA="http://pmj-mail01:8080/caldav/$1/"
SOGO="http://sogo.joinville.sc.gov.br/SOGo/dav/$1/Calendar/personal/"

prepareEnv
DIR=$(getDirectory "$ZARAFA")
ZARAFAURL="$ZARAFA$DIR"
listRemote "$ZARAFAURL" 
getFiles "$ZARAFAURL" 
sendFiles "$SOGO"

echo
echo "Done!"
