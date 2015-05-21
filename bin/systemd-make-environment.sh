#!/bin/bash
#
# +----------------------------------------------------------------------------+
# |                        systemd-make-environment.sh                         |
# +----------------------------------------------------------------------------+
#
# If this file seems a bit un-organized, you are reading it the wrong way (e.g.
# not in vim). Reload it in vim, type ":set modeline" (without the quotes), and
# ":e" (again without the quotes). This will set the proper stuff (see end of
# file). Do type ":help folds" to read up on vim folding technique.  Hint: use
# "zo" to open, "zc" to close individual folds.

set -o pipefail

# built-in configuration #{{{
CONF_DEPS="pcregrep wdiff"
CONF_DO_DEBUG=""
CONF_DO_PRINT_HELP=""
CONF_INPUT_FILE=""
CONF_OUTPUT_FILE=""
CONF_SCRIPT_NAME="$(basename $0)"
#}}}
# functions #{{{
# logging and output#{{{

# Say something on standard output.
#
log() {
  echo $@
}

log_stderr() {
  echo $@ >&2
}

log_warning() {
  log_stderr "Warning: $@"
}

log_error() {
  log_stderr "ERROR: $@"
}

log_debug() {
  [ -n "$CONF_DO_DEBUG" ] && {
    log_stderr "debug: " $@
  }
}
#}}}
# run, exec, die and friends #{{{
#
die() {
  echo "$* Aborting."
  exit 1
}
#}}}
# checkers and initializers #{{{
check_CONF_DEPS() {
  local errors=0

  # skip the check if so inclined
  [ -n "$CONF_DONT_CHECK_DEPS" ] && {
    log_warning "Skipping dependency check for external programs."
    return 0
  }
  
  # no deps?
  [ -z "$CONF_DEPS" ] && {
    log_warning "No dependencies to external programs defined. This is weird. Bug the developer of this script, if he is around."
    return 0
  }

  # do tha check
  local bin
  for bin in $CONF_DEPS; do
    which "$bin" 2>&1 > /dev/null || {
      log_error "External program '$bin' not found anywhere in PATH ($PATH)."
      errors=$(( $errors + 1 ))
    }
  done
  return $errors
}

check_CONF_INPUT_FILE() {
  [ -z "$CONF_INPUT_FILE" ] && {
    log_error "No input filename given."
    return 1
  }
  [ ! -f "$CONF_INPUT_FILE" ] && {
    log_error "Input filename '$CONF_INPUT_FILE' exists, but is not a file."
    return 1
  }
  return 0
}

check_CONF_OUTPUT_FILE() {
  [ -z "$CONF_OUTPUT_FILE" ] && {
    log_warning "No output filename given, using stdout."
    return 0
  }
  [ -f "$CONF_OUTPUT_FILE" -a ! -w "$CONF_OUTPUT_FILE" ] && {
    log_error "Output file '$CONF_OUTPUT_FILE' exists, and is not writable."
    return 1
  }
  local dir=$(dirname $CONF_OUTPUT_FILE)
  [ ! -w "$dir" ] && {
    log_error "Can't write to '$CONF_OUTPUT_FILE' parent directory '$dir'."
    return 1
  }
  return 0 
}
#}}}
# command-line parsing and help #{{{
#
# Parse the command line arguments and build a running configuration from them.
#
# Note that this function should be called like this: >parse_args "$@"< and
# *NOT* like this: >parse_args $@< (without the ><, of course). The second
# variant will work but it will cause havoc if the arguments contain spaces!
#
parse_args() {
  local short_args="h,i:,o:"
  local long_args="help,input-file:,output-file:"
  local g; g=$(getopt -n $CONF_SCRIPT_NAME -o $short_args -l $long_args -- "$@") || die "Could not parse arguments, aborting."
  log_debug "args: $args, getopt: $g"

  eval set -- "$g"
  while true; do
    local a; a="$1"

    # This is the end of arguments, set the stuff we didn't parse (the
    # non-option arguments, e.g. the stuff without the dashes (-))
    if [ "$a" = "--" ] ; then
      shift
      while [ $# -gt 1 ]; do
        CONF_UNPARSED="$CONF_UNPARSED $1"
        shift
      done
      return 0

    # This is the output file.
    elif [ "$a" = "-o" -o "$a" = "--output-file" ] ; then
      shift; CONF_OUTPUT_FILE="$1"

    # This is the input file.
    elif [ "$a" = "-i" -o "$a" = "--input-file" ] ; then
      shift; CONF_INPUT_FILE="$1"

    # Help.
    elif [ "$a" = "-h" -o "$a" = "--help" ] ; then
      CONF_DO_PRINT_HELP="true"

    # Dazed and confused...
    else
      die -e "I apparently know about the '$a' argument, but I don't know what to do with it.\nAborting. This is an error in the script. Bug the author, if he is around."
    fi

    shift
  done
  return 0
}

# Print the help stuff
# 
print_help() {
  cat <<HERE
$CONF_SCRIPT_NAME takes a bash(1) script, evaluates it, and writes out the
variables that the script set to an output file. This comes handy when writing 
systemd unit files.

Usage: $CONF_SCRIPT_NAME [option ...]

These options are MANDATORY:
  -i, --input-file  : the shell script that sets the environment variables,
                     current: "$CONF_INPUT_FILE"

These options are, well, optional:
  -o, --output-file : the file  shell script that sets the environment variables,
                     current: "$CONF_INPUT_FILE"

  General:
  -h, --help        : This text, current: "$CONF_DO_PRINT_HELP"
HERE
  return 0
}
#}}}
# stuff that does the work#{{{
#
get_variable_names() {
  set | pcregrep -o1 '^(\w+)=' 
}

#}}}#}}}
# init #{{{
#
check_CONF_DEPS || die

# parse comamnd line , check configuiration
parse_args $@
[ -n "$CONF_DO_PRINT_HELP" ] && {
  print_help
  exit 0
}
errors=0
check_CONF_INPUT_FILE; errors=$(( $errors + $? ));
check_CONF_OUTPUT_FILE; errors=$(( $errors + $? ))

# Stop if there are any errors in the configuration.
[ "$errors" -gt 0 ] && die "$errors error(s) found in the configuration."
unset errors

#}}}
# main#{{{

# Gather the input
var_names_before=""
var_names_before=$(get_variable_names); log_debug "var_names_before=\"$var_names_before\""
. "$CONF_INPUT_FILE"
var_names_after=$(get_variable_names); log_debug "var_names_after=\"$var_names_after\""
added_var_names=$(wdiff --no-common --no-deleted <(echo $var_names_before) <(echo $var_names_after) | pcregrep -o1 '^\s(.*)' | sed ':a;$!{N;ba};s/\n/ /g')

# Do the output
[ -e "$CONF_OUTPUT_FILE" ] && {
  echo "Output file '$CONF_OUTPUT_FILE' already exists, overwriting it."
  rm "$CONF_OUTPUT_FILE" || die "Could not remove already existing output file."
}
for var_name in $added_var_names; do
  if [ -z "$CONF_OUTPUT_FILE" ]; then
    echo "$var_name=\"${!var_name}\""
  else
    echo "$var_name=\"${!var_name}\""  >> "$CONF_OUTPUT_FILE"
  fi
done

#}}}

# vim: set tabstop=2 shiftwidth=2 expandtab colorcolumn=80 foldmethod=marker foldcolumn=3 foldlevel=0:
