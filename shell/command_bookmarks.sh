#!/bin/bash

BM_FILENAME=~/.command_bookmarks
VERSION_CODE=1.0.1

# show usage
usage() {
  cat <<__EOS__
$(basename $0) is a tool for command bookmarks

Usage: $(basename $0) [<action>] [<options>]

Actions:
  add <command>     Add command to bookmark
  ls                List bookmarks with their IDs
  edit              Edit bookmarks
  rm <ID>           Delete a bookmark of the specified ID looked up by "ls" action
  run <ID>          Run a command of the specified ID looked up by "ls" action

Options:
  --help     Print this
  --version  Show version
__EOS__
}

case "$1" in
  # "Add" option
  "add" )
    if [ -n "$2" ]; then
      echo "${@:2}" >> $BM_FILENAME
      echo "Added a new command bookmark."
    else
      echo "Please specify a command to be added."
      exit 1
    fi
    ;;

  # "List" option
  "ls" )
    line_num=1
    cat $BM_FILENAME | while read line
    do
      echo $line_num: $line
      line_num=$(($line_num + 1))
    done
    ;;

  # "Edit" option
  "edit" )
    "${EDITOR:-vi}" $BM_FILENAME
    ;;

  # "Remove" option
  "rm" )
    if [[ ! "$2" =~ ^[0-9]+$ ]]; then
      echo "Invalid command number specified."
      exit 1
    fi
    sed -i -e "${2},${2}d" $BM_FILENAME
    ;;

  # "Run" option
  "run" )
    if [[ ! "$2" =~ ^[0-9]+$ ]]; then
      echo "Invalid command number specified."
      exit 1
    fi
    run_command=`sed -n ${2}p $BM_FILENAME`
    if [[ -z "$run_command" ]]; then
      echo "Command not found."
      exit 1
    fi
    echo "$(basename $0): Running \`$run_command\`"
    eval $run_command
    ;;

  # "--help" option
  "--help" | "" )
    usage
    ;;

  # "--version" option
  "--version" )
    echo "$(basename $0) version $VERSION_CODE"
    ;;

  # other actions
  * )
    echo "Unknown action. Try $(basename $0) --help"
    exit 1
    ;;
esac
