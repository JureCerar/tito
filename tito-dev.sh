#!/usr/bin/env bash

# Copyright (C) 2019-2020  Jure Cerar
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Script version and date
VERSION="0.2.4"
DATE="17 Jun 2020"

# Changelog:
# v0.2.4 -- 17 Jun 2020
# - Fixed checking for running "tito.xxx" screen shells.
#
# v0.2.3 -- 20 Feb 2020
# - Fixed bug where `nodeUsage` would return to low value.
#
# v0.2.2 -- 12 Feb 2020
# - Default `MAX_THREADS` is now nprocs on master node
# - Added check if commands can be sent via SSH
# - GNU screen is started on master node rather than slave.
#
# v0.2.1 and older
# - ???

# Variables
NODE_LIST="/usr/local/bin/slaves" # Default node list
ESC=$'\033'           # ACII escape
TCOL=$(tput cols)     # screen width

# Defaults
MAX_THREADS=$(nproc)  # Max number of thread(s) per node
NTHREADS=1            # Number of threads needed for job submission
VERBOSE=              # Verbose output
KILL=                 # Enable killswitch
LOGFILE=              # logfile
WAIT_TIME=120.0       # Wait time if no new node is found

# ---------------------------------------------------------------------------
# Add some colors to your life

# Set output color to red
function red() {
  echo "${ESC}[1;31m$@${ESC}[0m"
  return 0
}

# Set output color to blue
function blue() {
  echo "${ESC}[1;94m$@${ESC}[0m"
  return 0
}

# Set output to magenta
# NOTE: this is called magenta, because pink is [*bell*]
function magenta() {
  echo "${ESC}[1;95m$@${ESC}[0m"
  return 0
}

# Underline test
function uline() {
  echo "${ESC}[4m$@${ESC}[0m"
  return 0
}

# --------------------------------------------
# Utility and pretty print  functions

# Check if value us number
function isNumber() {
  local REGX='^[+-]?[0-9]+([.][0-9]+)?$'
  [[ $1 =~ $REGX ]] || return 1
  return 0
}

# Timestamp in format I like: "dd mmm yyyy hh:mm:ss"
function timestamp() {
  date +"%d %b %Y %H:%M:%S"
  return 0
}

# Print error to STDERR and exit
# Use: errorOut <string> ...
function errorOut() {
  echo $(red "ERROR:") $@ 1>&2
  exit 1
}

# Print warning to STDERR
# Use: warningOut <string> ...
function warningOut() {
  echo $(magenta "WARNING:") $@ 1>&2
  return 0
}

# Verbosity print
# Use: verboseOut <string> ...
function verboseOut() {
  [[ "$VERBOSE" -eq 1 ]] && echo $(red "::") $@ >&2
  return 0
}

# Print title card
# Use: titleOut <message>
function titleOut() {
  local SPC # Number of spaces required to fill screen
  let SPC=$TCOL-${#1}
  echo "${ESC}[7m${1}$(printf "%${SPC}s")${ESC}[0m"
  return 0
}

# Pretty print to stdout and logfile
# Use: submitOut <node> <sid> <command>
function submitOut() {
  local TAB="    "
  echo "$(timestamp) :: $(red "[$1]") $2 $TAB $3"
  [[ -z "$LOGFILE" ]] || echo "$(timestamp) :: [$1] $2 $TAB $3"  >> $LOGFILE
  return 0
}

# ---------------------------------------------------------------------------
# Function definitions

# SSH wrapper
function _ssh() {
  ssh -n -o 'PreferredAuthentications=publickey' $@
  return $?
}

# Current node iterator
# Use: nextNode
CURR_NODE=0
function nextNode() {
  let CURR_NODE++
  [[ $CURR_NODE -eq ${#NODES[@]} ]] && let CURR_NODE=0
  return 0
}

# Returns current node
# Use: currentNode
function currentNode() {
  echo ${NODES[$CURR_NODE]}
  return 0
}

# Check node list and delete non-responsive nodes from list.
# Use: checkNodes
function checkNodes() {
  local i NEW
  for i in "${!NODES[@]}"; do
    # Check if responsive and if command can be send via ssh.
    ping -c 1 -W 1 "${NODES[$i]}" &>/dev/null && _ssh ${NODES[$i]} "" &>/dev/null
    if [[ "$?" -eq 0 ]]; then
      NEW+=( ${NODES[$i]} )
    else
      verboseOut "Unresponsive node: ${NODES[$i]}"
    fi
  done
  NODES=( ${NEW[@]} )
  return 0
}

# Returns number of processes currently runing on node
# Use: nodeUsage <node>
function nodeUsage() {
  local RUNPROC AVGLOAD
  ping -c 1 -W 1 $1 &>/dev/null
  if [[ "$?" -eq 0 ]]; then
    # Currently running processes on node. If request is trigered out of OpenMP region it can give wrong result.
    RUNPROC=$( awk '{print $2-1}' <<< `_ssh $1 "grep 'procs_running' /proc/stat"` )
    # Load average on node. If the processes is not fully utilizing CPU it can give wrong result.
    AVGLOAD=$( awk '{printf "%d", $1+0.5 }' <<< `_ssh $1 "cat /proc/loadavg"` )
    # Just use the higher of the values and you should be fine.
    echo $RUNPROC $AVGLOAD | awk '{ if ($1>=$2) {print $1} else {print $2} }'
  else
    echo "-1"
  fi
  return 0
}

# Submit command to node and set screen shell ID
# Use: submitCommand <node> <shell> <command>
function submitCommand() {
  # NODE=$1, SHELL=$2, CMD=$3
  # Write a wrapper around command to be submitted via ssh protocol.
  local CMD="cd $(pwd); $3; exit"
  CMD="ssh -n -o 'PreferredAuthentications=publickey' $1 \"${CMD}\" "
  # Open new remote shell and run the command
  screen -S $2 -dm bash -c "${CMD}"
  submitOut $1 $2 "$3"
  return 0
}

# Kill ALL processes run by user on selected nodes
# Use: killswitch
function killswitch() {
  local NODE CMD="pkill -u $(whoami)"
  for NODE in ${NODES[@]}; do
    ping -c 1 -W 1 $NODE &>/dev/null
    if [[ "$?" -eq 0 ]]; then
      verboseOut "Killing jobs on node: $NODE"
      _ssh $NODE "$CMD" &>/dev/null &
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
# Start of script

# Get external options.
while [[ $# -gt 0 ]]; do
  case $1 in
  -h|--help)
    # Print help message and exit
    # echo "-----------------------------MAX LENGTH GUIDE-------------------------------"
    echo "USAGE:"
    echo " tito [-options] [nodes]"
    echo ""
    echo "DESCRIPTION:"
    echo " FKKT ti:to is a shell tool for submitting jobs to cluster networks."
    echo ""
    echo " A job can be a single command or a small script that you want to run. Jobs"
    echo " are submitted as single line of text. For each line of input, FKKT ti:to"
    echo " will submit command to a node on the cluster network with the line as "
    echo " argument. If no command is given, the line of input is executed."
    echo ""
    echo " FKKT ti:to makes sure that all jobs are efficiently submitted to cluster"
    echo " network by using all available node resources before occupying next node."
    echo " If no free node is currently available, job submission will be halted until"
    echo " a nodes becomes available. In order to minimize impact on the node's"
    echo " performance the availability is checked only every [time] seconds. Jobs are "
    echo " submitted to cluster nodes using GNU screen interactive shell, allowing user "
    echo " to reattach to given shell and check on the submitted job. Screen shell is"
    echo " automatically closed once the job is finished."
    echo ""
    echo " By default jobs will be submitted to ALL available cluster nodes. In order "
    echo " to limit resource usage, a list of considered nodes can be provided as an "
    echo " optional arguments on the script command line. All nodes are checked before"
    echo " submission stage and non-responsive nodes are automatically removed. However,"
    echo " an error will occur if none of selected nodes is responsive."
    echo ""
    echo " FKKT ti:to only distributes jobs across nodes - it does NOT check if the "
    echo " submitted jobs work correctly. The latter is the responsibility of the user!"
    echo ""
    echo " Please visit $(uline "https://github.com/JureCerar/tito") for more information."
    echo ""
    echo "OPTIONS:"
    echo " -h, --help       -- Print this message."
    echo " -v, --verbose    -- Verbose output."
    echo " -n, --nthreads   -- Num. of threads per job [1-${MAX_THREADS}]. (${NTHREADS})"
    echo " -t, --time       -- Wait time when searching for free node [sec]. (${WAIT_TIME})"
    echo " -l, --log        -- Write submitted jobs to logfile. (${LOGFILE})"
    echo " --kill           -- Kill ALL jobs run by user on SELECTED nodes. (user: $(whoami))"
    echo ""
    echo "ABOUT:"
    echo " Version: ${VERSION} -- ${DATE}"
    echo ""
    echo "Copyright (C) 2019-2020 Jure Cerar"
    echo " This is free software; see the source for copying conditions. There is NO"
    echo " warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE."
    echo ""
    exit 0
    shift ;;
  -v|--verbose)
    # Verbosity
    VERBOSE=1
    shift ;;
  -n|--nthreads)
    # Number of threads per job
    shift
    NTHREADS=$1
    isNumber $NTHREADS || errorOut "Bad value: $NTHREADS"
    shift ;;
  -t|--time)
    # Wait time between free node search
    shift
    WAIT_TIME=$1
    isNumber $WAIT_TIME || errorOut "Bad value: $WAIT_TIME"
    shift ;;
  -l|--log)
    # Set LOG file
    shift
    LOGFILE=$1
    shift ;;
  --kill|--genocide)
    # Kill all commands run by user on all nodes.
    # > "Zakaj se ukaz imenuje 'kill' in ne raje 'genocide'?" -- M. Simoncic
    KILL=1
    shift ;;
  *)
    # Default option is node name + Expand option
    NODES+=( `eval echo $1` )
    shift ;;
  esac
done

# --------------------------------------------
# Check if GNU screen is installed.
command -v screen >/dev/null || errorOut "GNU screen not found on machine."

# Sanity check for nthreads
[[ $MAX_THREADS-$NTHREADS -lt 0 ]] && errorOut "Num. of requested thread(s) is larger than MAX num. of threads."

# If no nodes are provided, load default node list.
if [[ -z "${NODES[@]}" ]]; then
  verboseOut "Loading default node list from: ${NODE_LIST}"
  NODES=( `cat "${NODE_LIST}" 2>/dev/null` ) || errorOut "Node list file does not exist: ${NODE_LIST}"
fi

# Check node list and remove uresponsive nodes.
verboseOut "Selected nodes: ${NODES[@]}"
verboseOut "Checking nodes ..."
checkNodes
[[ -z "${NODES[@]}" ]] && errorOut "No active nodes found on network!"

# --------------------------------------------
# Verbosity time
verboseOut "Num. of threads per job: ${NTHREADS} (${MAX_THREADS})"
verboseOut "Logfile: ${LOGFILE}"
verboseOut "Wait time: ${WAIT_TIME} sec"
verboseOut "Killswitch: ${KILL}"

# --------------------------------------------
# If kill command is submitted kill all processes.
if [[ "${KILL}" -eq 1 ]]; then
  warningOut "Killing ALL user processes on nodes: ${NODES[@]}"
  killswitch
  exit 0
fi

# --------------------------------------------
# Collect all commands from STDIN
while IFS= read -r STRING || [[ -n "$STRING" ]]; do
  COMMANDS+=( "${STRING}" )
done

# --------------------------------------------
# Start passing command to nodes

# Initialize CNT counter: Find last remote shells that is currently running and continue counting from there.
CNT=$( ls "/var/run/screen/S-$(whoami)" 2>/dev/null | grep -E 'tito.[0-9][0-9][0-9]' | cut -d'.' -f 3 | sort | tail -n 1 )
if [[ -z "${CNT}" ]]; then
  let CNT=0
else
  let CNT=$( sed 's/^0*//' <<< "$CNT" )+1 # Remove leading zeros
fi

# Current number of free threads on NODE
FREE_THREADS=0

# Add title card
titleOut "START TIME              NODE SHELL ID      COMMAND"
for CMD in "${COMMANDS[@]}"; do
  # Can we fit current job to this node?
  if [[ $FREE_THREADS-$NTHREADS -lt 0 ]]; then
    # No; So cycle through nodes until we find free node ...
    while : ; do
      # Cycle once through node list
      for i in ${!NODES[@]}; do
        # Next iterator
        NODE=$( currentNode )
        nextNode

        # Check usage on the NODE
        USED_THREADS=$( nodeUsage $NODE )
        if [[ $USED_THREADS -ne -1 ]] && [[ $USED_THREADS -le $MAX_THREADS-$NTHREADS ]]; then
          let FREE_THREADS=$MAX_THREADS-$USED_THREADS
          break 2 # Return to main loop
        fi

      done

      # If after one cycle no free node is found, repeat loop after WAIT_TIME seconds.
      verboseOut "No free NODE found on network, retrying after ${WAIT_TIME} sec ..."
      sleep $WAIT_TIME

    done
  fi

  # Generate shell ID
  SID=$( printf "tito.%0.3d" $CNT )
  let CNT++
  let CNT=$(( $CNT % 1000 )) # If someone is mad enough to submit >1000 jobs...

  # Submit COMMAND to NODE under SID
  submitCommand $NODE $SID "$CMD"

  # Update how many threads are free
  let FREE_THREADS-=$NTHREADS

done

# We are done
verboseOut "All tasks submitted successfully."
