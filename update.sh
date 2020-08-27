#!/bin/bash

# CONST
PAPER_URL='https://papermc.io'
PAPER_API="$PAPER_URL/api/v1/paper"
JENKINS_JOBS="$PAPER_URL/ci/job"
PAPER_DIR="$(dirname "$(realpath "$0")")"   # run @ location of the script
OLD_VER_DIR="$PAPER_DIR/old_paper_versions"

# ARGS
assume_yes=false
print_changes=true
force_update=false
while [ -n "$1" ]; do
  case "$1" in
    -y|--yes|--assume-yes|yes|auto) assume_yes=true;;
    -s|--short|short)               print_changes=false;;
    -f|--force|force)               force_update=true;;
    -v|--force-version|ver)         latest_version="$2"; shift;;
    -h|--help|help)                 echo "
      -h, --help:         Print this help message.
      -y, --assume-yes:   Don't ask for confirmation before update.
      -s, --short:        To be used with -y, it makes it so the script doesn't print the changes, from the current to the latest build.
    "; exit;;
  esac
  shift
done
$assume_yes || print_changes=true

# VERSION NUMBERS
versions=$(curl -s "$PAPER_API" | jq '.versions')
[ -z "$latest_version" ] && latest_version=$(echo "$versions" | jq '.[0]' | tr -d '"')  # get latest version
latest_major=$(echo "$latest_version" | rev | cut -d'.' -f2- | rev)                     # latest major version
latest_build=$(curl -s "$PAPER_API/$latest_version" | jq '.builds.latest' | tr -d '"')  # get latest build
filename="paper-${latest_version}-${latest_build}.jar"

cd "$PAPER_DIR"
if ! $force_update && [ -e "$filename" ]; then # the latest version already exists here
  echo -e "\e[32mYou already have the latest version of Paper!\e[0m"
  exit
fi

# PRINT CHANGES
if $print_changes && curr=$(ls -lX paper-* 2>/dev/null); then # if we have downloaded previous builds
  curr=$(echo "$curr" | tail -n1 | rev | cut -d' ' -f1 | cut -d'.' -f2- | rev)
  curr_ver=$(echo "$curr" | cut -d'-' -f2) # extract latest downloaded MC version
  curr_build=$(echo "$curr" | cut -d'-' -f3) # extract latest downloaded build number
  if [[ $curr_build =~ ^[0-9]+$ ]]; then  # is number
    indent=${#latest_build}
    format_d1="\e[1;36m%-${indent}s \e[1;32m%s\e[m\n"
    format_d2="%-$((${indent} + 2))s \e[1;34m%s\e[m\n"
    format_d3="%-$((${indent} + 4))s \e[1;33m%s\e[m\n"
    builds=$(curl -s "$JENKINS_JOBS/Paper-$latest_major/api/json" | jq '.builds[]') # get build list from Jenkins
    build_num=$curr_build
    [ $curr_build -lt $latest_build ] && echo -e "\e[35mChanges:\e[0m"
    while [ $((++build_num)) -le $latest_build ]; do  # for every build number between current and latest builds
      build_url=$(echo "$builds" | jq "select(.number==$build_num) | .url") # get build url from Jenkins
      if [ -n "$build_url" ]; then
        build_info=$(curl -s "${build_url:1:-1}api/json?tree=id,changeSet\[items\[msg,comment\]\]" | jq '.changeSet') # get build info from Jenkins
        build_changes=$(echo "$build_info" | jq '.items[].msg') # extract the change messages
        change_num=0
        while read build_change; do # for each change
          build_change=${build_change:1:-1}
          if [ $change_num -eq 0 ]; then # print change message with proper formatting
            printf "$format_d1" $build_num "$build_change"
          else
            printf "$format_d1" '' "$build_change"
          fi
          if [[ $build_change =~ ^\[Auto\] ]]; then # if it starts with [Auto], it was an upstream update, so show the comment too, which includes the upstream changes
            build_comments=$(echo "$build_info" | jq ".items[$change_num].comment")
            build_comments=$(echo -e "${build_comments:1:-1}" | tail -n+6 | grep -v "^\s*$") # trim
            while read build_comment; do  # format each line of the comment
              if [[ $build_comment =~ ^[A-Z] ]]; then # is header
                printf "$format_d2" '' "$build_comment"
              else
                printf "$format_d3" '' "$build_comment"
              fi
            done <<< "$build_comments"
          fi
          ((change_num++))
        done <<< "$build_changes"
      fi
    done
    if ! $assume_yes; then  # ask if we should proceed with the update
      echo -en "\e[35mUpdate \e[36m$curr_ver\e[35m:\e[36m$curr_build\e[35m->\e[36m$latest_version\e[35m:\e[36m$latest_build\e[35m? [Y/n/[<Minecraft version>:]<build number>]: \e[0m"
      read -r opt
      if [[ $opt =~ ^[0-9]+$ ]]; then
        echo -e "\e[35mLooking up build...\e[0m"
        build_found=false
        latest_build=$(echo "$opt" | cut -d':' -f2) # parse selected build & MC version
        if [ "$(echo "$opt" | cut -d':' -f1)" != "$latest_build" ]; then
          latest_version="$(echo "$opt" | cut -d':' -f1)"
          if [ -n "$(curl -s "$PAPER_API/$latest_version" | jq ".builds.all | select(.[]==\"$opt\")")" ]; then
            build_found=true  # build exists for this MC version
            break
          fi
        else
          while read ver; do # find MC version for specified build
            if [ -n "$(curl -s "$PAPER_API/$ver" | jq ".builds.all | select(.[]==\"$opt\")")" ]; then
              latest_version="$ver"
              build_found=true
              break
            fi
          done <<< "$(echo "$versions" | jq '.[]' | tr -d '"')"
        fi
        if $build_found; then
          filename="paper-${latest_version}-${latest_build}.jar"
        else
          echo -e '\e[31mBuild not found!\e[0m'
          exit 1;
        fi
      elif [ -n "$opt" ] && [ "$opt" != "y" ] && [ "$opt" != "Y" ]; then
        echo -e '\e[31mCanceled!\e[0m'
        exit 0
      fi
    fi
  fi
fi

# DOWNLOAD UPDATE
echo -e "\e[35mUpdating Paper...\e[0m"
mkdir -p "$OLD_VER_DIR"
mv paper-*.jar "$OLD_VER_DIR/" 2>/dev/null  # move old versions, to keep things clean

wget -q --show-progress -O "$filename" "$PAPER_API/$latest_version/$latest_build/download"
chmod +x "$filename"
ln -s -f "$filename" "paper"  # make symlink, with a static name, for use in scripts
echo -e "\e[90mYou can use the \"paper\" symlink to start Paper.\n\e[32mDone!\e[0m"
