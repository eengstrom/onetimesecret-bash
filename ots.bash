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
# Author: Eric Engstrom (eric.engstrom(-AT-)g.m.a.i.l(-DOT-)c o m)
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

# ------------------------------------------------------------
# Internal only functions;
# NOT part of the API, and subject to change.

# turn debugging on
_ots_set_debug()  { _OTS_DEBUG='_ots_debug'; _OTS_FMT='debug'; }
# Simple debug, but write output propery quoted
_ots_debug() { test -n "$_OTS_DEBUG" && (printf "%q " "$@"; printf "\n") 1>&2; }

# join all but the first arg together, separated by the first arg
# e.g. $(join : foo bar baz) returns "foo:bar:baz"
#_ots_join() { local IFS; IFS="$1"; echo "${*:2}"; }
# another idea with multi-char separators:
# http://stackoverflow.com/questions/1527049/join-elements-of-an-array
_ots_join() { local d="$1"; shift; echo -n "$1"; shift; printf "%s" "${@/#/$d}"; }

# given a split value and an array of values, return index of split value
_ots_index() {
  local split="$1"; shift
  for ((i=1;i<=$#;++i)); do
    [[ "${@:$i:1}" == "$split" ]] && break
  done
  echo $i
}

# function to wrap curl usage
_ots_curl() { $_OTS_DEBUG curl -s "$@"; }

# Generate API URI / Metadata API URL (given metadata key)
_ots_api() { echo "${_OTS_URI}/${_OTS_URN}"; }
_ots_metaapi() { echo "$(_ots_api)/private/$1"; }

# Generate the auth arguments
_ots_auth() {
  test -n "$_OTS_UID" -a -n "$_OTS_KEY" \
    && echo "-u $_OTS_UID:$_OTS_KEY"
}

# Validate args; warn and return error if not valid.
_ots_validate_args() {
  local CHECK="$1"; shift
  # Should be more thorough, this is really just a number check.
  if [[ $# -lt 1 ]]; then
    echo "No $CHECK key given" 1>&2
    return 1
  fi
}

# output results, as formatted, json, yaml or raw.
_ots_output() {
  local FMT=${_OTS_FMT:-fmt}
  if [[ "${1,,}" == @(json|yaml|fmt|printf|raw|debug) ]]; then
    FMT="${1}"; shift
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

# ------------------------------------------------------------
# Exepcted entry-point functions - API and others

# Set/save authenticated user (email) / key / host
ots_set_host()   { _OTS_URI="$1"; }
ots_set_user()   { _OTS_UID="$1"; }
ots_set_key()    { _OTS_KEY="$1"; }
ots_set_format() { _OTS_FMT="$1"; }

# check on status of OTS server
ots_status() {
  _ots_curl $(_ots_auth) "$(_ots_api)/status" \
    | _ots_output '%s\n' '.status // .message // "Unknown Error"'
}

# Share a secret, which is assumed to come in on STDIN or from ARGS.
# Arguments *preceeding* optional "--" are assumed to be of the form:
#   PARAM=VALUE
# and further are assumed to be supported by the corresponding OTS API.
ots_share() { ots_url $(ots_metashare "$@"); }

# Share a secret, returning the metadata key for the new secret
ots_metashare() {
  # collect API form args
  local IDX=$(_ots_index -- "$@")
  local ARGS=$(_ots_join " -F " "" "${@:1:($IDX - 1)}")

  # Add any remaining args to the secret
  local -a SECRET=("${@:($IDX + 1)}")

  # but if the secret is empty, read from STDIN
  if [ ${#SECRET[@]} -eq 0 ]; then
    # read secret from stdin, with prompt if running interactively
    test -t 0 && echo 'Enter secret; terminate with Ctrl-D:'
    SECRET=$(cat - /dev/null)
  fi

  _ots_debug "secret:" "${SECRET[@]}"
  if [ -z "${SECRET}" ]; then
    echo No secret data given
  else
    echo "${SECRET[@]}" \
      | _ots_curl -X POST $(_ots_auth) ${ARGS} -F secret='<-' "$(_ots_api)/share" \
      | _ots_output "%s\n" '.metadata_key'
  fi
}

# Generate a random secret.
# Arguments *preceeding* optional "--" are assumed to be of the form:
#   PARAM=VALUE
# and further are assumed to be supported by the corresponding OTS API.
ots_generate() { ots_url $(ots_metagenerate "$@"); }

# Generate a secret, returning the metadata key for the new secret
ots_metagenerate() {
  # collect API form args
  local IDX=$(_ots_index -- "$@")
  local ARGS=$(_ots_join " -F " "" "${@:1:($IDX - 1)}")

  # note that we don't use anything after (optional) "--"
  _ots_curl -X POST $(_ots_auth) ${ARGS} "$(_ots_api)/generate" \
    | _ots_output "%s\n" '.metadata_key'
}

# Retrieve the secret; Secret key (or url) given as *LAST* argument.
# Arguments *preceeding* optional "--" are assumed to be of the form:
#   PARAM=VALUE
# and further are assumed to be supported by the corresponding OTS API.
ots_get() { ots_retrieve "$@"; }
ots_retrieve() {
  _ots_validate_args "URL or secret" "$@" || return 1

  # last argument assumed to be key (or url)
  local KEY;  KEY="${@: -1}"
  # grab just the key portion, if url looking thing found
  if [[ "$KEY" =~ "$_OTS_URI" ]]; then
    KEY=${KEY##*/}
  fi

  # remove last argument by resetting args to slice without last.
  set -- "${@:1:$(($#-1))}"

  # collect API form args
  local IDX=$(_ots_index -- "$@")
  local ARGS=$(_ots_join " -F " "" "${@:1:($IDX - 1)}")

  # note that we don't use anything after (optional) "--", except last arg (key/url)
  _ots_curl -X POST ${ARGS} $(_ots_api)/secret/$KEY \
    | _ots_output '%s\n' '.value // .message // "Unknown Error"'
}

# burn a secret, given the metadata key
ots_burn() {
  _ots_validate_args "metadata" "$@" || return 1

  # This call is odd, as it returns a hierarchical JSON response.
  _ots_curl -X POST $(_ots_auth) $(_ots_metaapi "$1")/burn \
    | _ots_output '%s\n' '.state.state // .message // "Unknown Error"'
}

# retrieve the metadata for a secret
ots_metadata() {
  _ots_validate_args "metadata" "$@" || return 1
  _ots_curl -X POST $(_ots_metaapi "$1") \
    | _ots_output '%s\n' '.message // .'
}

# retrieve recent metadata keys; requires auth tokens
ots_recent() {
  if [ -z "$(_ots_auth)" ]; then
    echo "Authentication Required" 1>&2
    return 1
  fi

  _ots_curl -X GET $(_ots_auth) $(_ots_api)/private/recent \
    | _ots_output '%s\n' 'if type=="array" then .[].metadata_key else .message end // "Unknown Error"'
}

# check on state of a secret, given the metadata key
ots_state() {
  _ots_validate_args "metadata" "$@" || return 1
  _ots_curl -X POST $(_ots_metaapi "$1") \
    | _ots_output '%s\n' '.state // .message // "unknown"'
}

# get the secret key for a secret, given the metadata key
ots_key() { ots_secret_key "$@"; }
ots_secret_key() {
  _ots_validate_args "metadata" "$@" || return 1
  _ots_curl -X POST $(_ots_metaapi "$1") \
    | _ots_output FMT "%s\n" '.secret_key'
    # Note forced output to format (FMT) via printf.
}

# Get the (user-friendly) secret url for a secret, given the metadata key
ots_url() { ots_secret_url "$@"; }
ots_secret_url() {
  _ots_validate_args "metadata" "$@" || return 1
  printf "$_OTS_URI/secret/%s\n" $(ots_key "$1")
}

# Get the (user-friendly) metadata url for a secret, given the metadata key
ots_metaurl() { ots_metadata_url "$@"; }
ots_metadata_url() {
  _ots_validate_args "metadata" "$@" || return 1
  printf "$_OTS_URI/private/%s\n" "$1"
}

# ------------------------------------------------------------
# main - parse args; execute action if not being sourced
_ots_main() {
  local ACTION="share"  # default is share
  local -a FORM=()
  local -a ARGS=()

  while [[ $# -ge 1 ]]; do
    case "$1" in
      # end args processing at '--'
      --)                  shift; break                             ;;
      # meta args
      -D|--debug)          _ots_set_debug                 ; shift   ;;
      -H|--help)           echo "need help/usage"         ; exit    ;;
      # Action
      share|metashare|generate|metagenerae|get|retrieve \
        |state|burn|metadata|key|url|metaurl \
        |status|recent)    ACTION="$1"                    ; shift   ;;
      # Connection parameter
      -h  |--host)         ots_set_host "$2"              ; shift 2 ;;
      -u  |--user)         ots_set_user "$2"              ; shift 2 ;;
      -k  |--key)          ots_set_key "$2"               ; shift 2 ;;
      # Output format
      -f  |--format)       ots_set_format "$2"            ; shift 2 ;;
      yaml|json|fmt|raw)   ots_set_format "$1"            ; shift   ;;
      # Secrets are collected in the ARGS and passed onwards
      -s=*|--secret=*)     ARGS+=("${1#*=}")              ; shift   ;;
      -s  |--secret)       ARGS+=("$2")                   ; shift 2 ;;
      secret=*)            ARGS+=("${1#*=}")              ; shift   ;;
      # API Form ARGS, really only used by share, generate, get
      -r=*|--recipient=*)  FORM+=("recipient=${1#*=}")    ; shift   ;;
      -r  |--recipient)    FORM+=("recipient=$2")         ; shift 2 ;;
      -p=*|--passphrase=*) FORM+=("passphrase=${1#*=}")   ; shift   ;;
      -p  |--passphrase)   FORM+=("passphrase=$2")        ; shift 2 ;;
      -t=*|--ttl=*)        FORM+=("ttl=${1#*=}")          ; shift   ;;
      -t  |--ttl)          FORM+=("ttl=$2")               ; shift 2 ;;
      *=*)                 FORM+=("$1")                   ; shift   ;;
      # anything else we just collect and pass onwards
      *)                   ARGS+=("$1")                   ; shift   ;;
    esac
  done

  # If this is being sourced by some other script, parse config options and return.
  # idea: http://stackoverflow.com/questions/2683279/how-to-detect-if-a-script-is-being-sourced
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return

  # Default action is 'share'; execute the action
  ots_${ACTION:-share} "${FORM[@]}" ${FORM:+"--"} "${ARGS[@]}" "$@"
}

#----------------------------------------
_ots_main "$@"

# eof
