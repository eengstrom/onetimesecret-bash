#!/usr/bin/env bash
#
# bash command-line and API access to OneTimeSecret (https://onetimesecret.com)
# API Docs: https://onetimesecret.com/docs/api/secrets
#
# Requires:
# - bash 4.x -- for associative arrays
# - curl     -- for accessing the OTS API
# - jq       -- for parsing json and formatting output
#
# Author: Eric Engstrom (engstrom(-AT-)m t u(-DOT-)n e t)
# See README.md and LICENSE.
##

# Check bash version; exit if not sufficient
if ((${BASH_VERSINFO[0]} < 4)); then
  echo "ERROR: Bash version >= 4.0 required" 1>&2
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 1 || exit 1
fi

# Defaults
_OTS_URI="https://onetimesecret.com"
_OTS_URN="api/v1"
_OTS_FMT="fmt"     # "fmt|printf", "yaml", "json" or anything else == raw
_OTS_OUT="url"     # "url", "metadata[_key]" - what is output from share|generate

# ------------------------------------------------------------
# Internal only functions

# join all but the first arg together, separated by the first arg
# e.g. $(join : foo bar baz) returns "foo:bar:baz"
#_ots_join() { local IFS; IFS="$1"; shift; echo "$@"; }
# another idea with multi-char separators:
# http://stackoverflow.com/questions/1527049/join-elements-of-an-array
_ots_join() { local d="$1"; shift; echo -n "$1"; shift; printf "%s" "${@/#/$d}"; }

# Generate API URI, metadata API URL (given metadata key)
_ots_api() { echo "${_OTS_URI}/${_OTS_URN}"; }
_ots_metaapi() { echo "$(_ots_api)/private/$1"; }

# Generate the auth arguments
_ots_auth() {
  test -n "$_OTS_UID" -a -n "$_OTS_KEY" \
    && echo "-u $_OTS_UID:$_OTS_KEY"
}

# output results, as formatted, json, yaml or raw.
_ots_output() {
  local FMT=${_OTS_FMT}
  if [[ "${1,,}" == @(json|yaml|fmt|printf|raw) ]]; then
    FMT=${1}; shift
  fi

  case "${FMT,,}" in
    json)       jq "." - ;;
    yaml)       jq -r "to_entries|map(\"\(.key): \(.value)\")|.[]" - ;;
    # printf assumes $1 = printf format; remaining argumets are sent to jq
    fmt|printf) printf "${1}" "$(jq -r "${@:2}" -)" ;;
    # anything else is 'raw'
    raw|*)      cat - ;;
  esac
}

# parse JSON and put into '_ots_result' associative array
# idea from: http://stackoverflow.com/questions/26717277/converting-a-json-array-to-a-bash-array
#declare -A _ots_result
#_ots_parse_json() {
#  while IFS="=" read -r key value; do
#    _ots_result[$key]="$value"
#  done < <(jq -r "to_entries|map(\"\(.key)=\(.value)\")|.[]" -)
#
#  for key in "${!_ots_result[@]}"; do
#    echo "parse: $key = ${_ots_result[$key]}"
#  done
#}

# ------------------------------------------------------------
# Exepcted entry-point functions - API and others

# Set/save authenticated user (email) / key / host
ots_set_host()   { _OTS_URI="$1"; }
ots_set_user()   { _OTS_UID="$1"; }
ots_set_key()    { _OTS_KEY="$1"; }
ots_set_format() { _OTS_FMT="$1"; }

# check on status of OTS server
ots_status() {
  curl -s $(_ots_auth) "$(_ots_api)/status" \
    | _ots_output '%s\n' '.status // .message // "Unknown Error"'
}

# Share a secret, which is assumed to come in on STDIN.
# All arguments are assumed to be correct of the form
#   PARAM=VALUE
# and further are assumed to be supported by the 'share' API form.
ots_share() {
  local ARGS; ARGS=$(_ots_join " -F " "" "${@}")
  curl -s $(_ots_auth) $ARGS -F secret='<-' "$(_ots_api)/share" \
    | _ots_output "$_OTS_URI/secret/%s\n" '.secret_key'
}

# Generate a random secret.
# All arguments are assumed to be correct of the form
#   PARAM=VALUE
# and further are assumed to be supported by the 'generate' API form.
ots_generate() {
  local ARGS; ARGS=$(_ots_join " -F " "" "${@}")
  curl -s $(_ots_auth) ${ARGS:--d "''"} "$(_ots_api)/generate" \
    | _ots_output "$_OTS_URI/secret/%s\n" '.secret_key'
}

# Retrieve the secret data; Secret key given on the command line.
ots_get() { ots_retrieve "$@"; }
ots_retrieve() {
  local KEY;  KEY="${@: -1}"
  local ARGS; ARGS=$(_ots_join " -F " "" "${@:1:$(($#-1))}")
  curl -s ${ARGS:--d "''"} $(_ots_api)/secret/$KEY \
    | _ots_output '%s\n' '.value // .message // "Unknown Error"'
}

# retrieve the metadata for a secret
ots_metadata() {
  curl -s -d '' $(_ots_metaapi "$1") \
    | _ots_output '%s\n' '.'
}

# retrieve recent metadata keys; requires auth tokens
ots_recent() {
  if [ -z "$(_ots_auth)" ]; then
    echo "Recent metadata requires authentication information." 1>&2
    return
  fi

  #curl -s $(_ots_auth) -X GET -d '' $(_ots_api)/metadata/recent \
  curl -s $(_ots_auth) -X GET -d '' $(_ots_api)/private/recent \
    | _ots_output '%s\n' 'if type=="array" then .[].metadata_key else .message end // "Unknown Error"'
}

# burn a secret, given the metadata key
#ots_burn() {
# no burn api call - fake it how?
#}

# check on state of a secret, given the metadata key
ots_state() {
  curl -s -d '' $(_ots_metaapi "$1") \
    | _ots_output '%s\n' '.state // .message // "unknown"'
}

# get the secret key for a secret, given the metadata key
ots_key() { ots_secret_key "$@"; }
ots_secret_key() {
  curl -s -d '' $(_ots_metaapi "$1") \
    | _ots_output "%s\n" '.secret_key'
}

# Get the (user-friendly) secret url for a secret, given the metadata key
ots_url() { ots_secret_url "$@"; }
ots_secret_url() { printf "$_OTS_URI/secret/%s\n" $(ots_key "$@"); }

# Get the (user-friendly) metadata url for a secret, given the metadata key
ots_metaurl() { ots_metadata_url "$@"; }
ots_metadata_url() { printf "$_OTS_URI/private/%s\n" "$@"; }

# ------------------------------------------------------------
# Check if we are being sourced only for our functions

# if this is being sourced by some other script, return now.
# idea: http://stackoverflow.com/questions/2683279/how-to-detect-if-a-script-is-being-sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]] ; then
  # parse some arguments for configuration
  while [[ $# -ge 1 ]]; do
    case "$1" in
      -h  |--host)       ots_set_host "$2"               ; shift 2 ;;
      -u  |--user)       ots_set_user "$2"               ; shift 2 ;;
      -k  |--key)        ots_set_key "$2"                ; shift 2 ;;
      -f  |--format)     ots_set_format "$2"             ; shift 2 ;;
      *)                 echo "unknown option '$1'" 1>&2 ; shift   ;;
    esac
  done

  # but don't do anything else
  return
fi

# ------------------------------------------------------------
# Running standalone - parse args and do something useful

# Collect form args in an array to pass to the function
FORM=()
ARGS=()
while [[ $# -ge 1 ]]; do
  case "$1" in
    -D|--debug)          _OTS_DEBUG=echo                ; shift   ;;
    -H|--help)           echo "need help"               ; exit    ;;
    # Connection parameter
    -h  |--host)         ots_set_host "$2"              ; shift 2 ;;
    -u  |--user)         ots_set_user "$2"              ; shift 2 ;;
    -k  |--key)          ots_set_key "$2"               ; shift 2 ;;
    # Otuput format
    -f  |--format)       ots_set_format "$2"            ; shift 2 ;;
    yaml|json|fmt|raw)   ots_set_format "$1"            ; shift   ;;
    # Action
    status|share|generate|get|retrieve|metadata|recent|state|key|url|metaurl)
                         ACTION="$1"                    ; shift   ;;
    # Secrets are collected in the ARGS
    -s=*|--secret=*)     ARGS+=("${1#*=}")              ; shift   ;;
    -s  |--secret)       ARGS+=("$2")                   ; shift 2 ;;
    secret=*)            ARGS+=("${1#*=}")              ; shift   ;;
    # Form ARGS, mostly for share, generate, get
    -r=*|--recipient=*)  FORM+=("recipient=${1#*=}")    ; shift   ;;
    -r  |--recipient)    FORM+=("recipient=$2")         ; shift 2 ;;
    -p=*|--passphrase=*) FORM+=("passphrase=${1#*=}")   ; shift   ;;
    -p  |--passphrase)   FORM+=("passphrase=$2")        ; shift 2 ;;
    -t=*|--ttl=*)        FORM+=("ttl=${1#*=}")          ; shift   ;;
    -t  |--ttl)          FORM+=("ttl=$2")               ; shift 2 ;;
    *=*)                 FORM+=("$1")                   ; shift ;;
    # anything else is assumed to be an argument to the function about to be called
    *)                   ARGS+=("$1")                   ; shift ;;
  esac
done

# Default action is 'share'
ACTION=${ACTION:-share}

# Do the action.
if [[ "${ACTION}" == "share" ]]; then
  if [ ${#ARGS[@]} -gt 0 ] ; then
    # assume secret is the composition of the extra args provided
    SECRET="${ARGS[@]}"
  else
    # read secret from stdin, with prompt if running interactively
    test -t 0 && echo 'Enter secret; terminate with Ctrl-D:'
    SECRET=$(cat -)
  fi
  echo "${SECRET}" | ots_share "${FORM[@]}"
else
  ots_$ACTION "${FORM[@]}" "${ARGS[@]}"
fi

exit

# eof
