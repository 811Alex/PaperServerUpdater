#!/bin/bash

# CONST
PAPER_API='https://api.papermc.io/v2/projects/paper'
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
      -h, --help:                     Print this help message.
      -y, --assume-yes:               Don't ask for confirmation before update.
      -s, --short:                    To be used with -y, it makes it so the script doesn't print the changes, from the current to the latest build.
      -f, --force:                    Force update, even if on the latest version.
      -v, --force-version <version>:  Use specified Minecraft version, instead of the latest one. Supports wildcards, ex.: 1.14.* will select 1.14.4 (the latest one).
    "; exit;;
  esac
  shift
done
$assume_yes || print_changes=true

# VERSION NUMBERS
versions=$(curl -s "$PAPER_API" | jq '.versions')
if [ -z "$latest_version" ]; then
  latest_version=$(echo "$versions" | jq '.[-1]' | tr -d '"')  # get latest version
else
  if [[ "$latest_version" =~ \* ]]; then  # contains wildcard
    echo -en "\e[35mLooking up matching versions...\e[0m"
    latest_version=$(echo "$latest_version" | sed 's/\.\**$/(&)?/g; s/\./\\./g; s/\*/.**/g')  # make regex
    matching_versions=""
    isfirst=true
    for ver in $(echo "$versions" | jq '.[]' | tr -d '"'); do # scan versions
      if [[ $ver =~ $latest_version ]]; then  # check if the version matches
        $isfirst || echo -en "\e[35m,\e[0m"
        isfirst=false
        echo -en " \e[32m$ver\e[0m"
        matching_versions="$matching_versions$ver\n"
      fi
    done
    matching_versions=$(echo -e "$matching_versions" | head -n1)
    if [ -n "$matching_versions" ]; then
      latest_version="$matching_versions"
      echo -e "\n\e[35mSelected latest matching version: \e[36m$latest_version\e[0m"
    else
      echo -e "\n\e[31mCan't find a matching version!\e[0m"
      exit 2
    fi
  else
    if [ -z "$(echo "$versions" | jq "select(.[]==\"$latest_version\")")" ]; then
      echo -e "\e[31mCan't find the specified version!\e[0m"
      exit 2
    fi
  fi
fi
latest_major=$(echo "$latest_version" | rev | cut -d'.' -f2- | rev)                     # latest major version
latest_build=$(curl -s "$PAPER_API/versions/$latest_version" | jq '.builds[-1]')  # get latest build
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
    builds=$(curl -s "$PAPER_API/versions/$latest_version" | jq '.builds[]') # get build list
    build_num=$curr_build
    [ $curr_build -lt $latest_build ] && echo -e "\e[35mChanges:\e[0m"
    while [ $((++build_num)) -le $latest_build ]; do  # for every build number between current and latest builds
      build_url="$PAPER_API/versions/$latest_version/builds/$build_num" # get build url
      build_info=$(curl -s "$build_url" | jq '.changes') # get build info
      build_summary=$(echo "$build_info" | jq '.[].summary') # extract the change summaries
      change_num=0
      while read build_change; do # for each change
        build_change=${build_change:1:-1}
        if [ $change_num -eq 0 ]; then # print change message with proper formatting
          printf "$format_d1" $build_num "$build_change"
        else
          printf "$format_d1" '' "$build_change"
        fi
        if [[ $build_change =~ ^(\[Auto\]\ )?Updated\ Upstream ]]; then # if it starts with [Auto], it was an upstream update, so show the message too, which includes the upstream changes
          build_message=$(echo "$build_info" | jq ".[$change_num].message")
          build_message=$(echo -e "${build_message:1:-1}" | tail -n+6 | grep -v "^\s*$") # trim
          while read build_comment; do  # format each line of the comment
            if [[ $build_comment =~ ^[A-Z] ]]; then # is header
              printf "$format_d2" '' "$build_comment"
            else
              printf "$format_d3" '' "$build_comment"
            fi
          done <<< "$build_message"
        fi
        ((change_num++))
      done <<< "$build_summary"
    done
    if ! $assume_yes; then  # ask if we should proceed with the update
      if [ "$curr_ver" = "$latest_version" ]; then
        update_text="\e[36m$curr_build\e[35m->\e[36m$latest_build"
      else
        update_text="\e[36m$curr_ver\e[35m:\e[36m$curr_build\e[35m->\e[36m$latest_version\e[35m:\e[36m$latest_build"
      fi
      echo -en "\e[35mUpdate $update_text\e[35m? [Y/n/[<MC ver.>:]<build num.>]: \e[0m"
      read -r opt
      if [[ $opt =~ ^([0-9]+\.[0-9]+(\.[0-9]+)?:)?[0-9]+$ ]]; then
        echo -e "\e[35mLooking up build...\e[0m"
        build_found=false
        latest_build=$(echo "$opt" | cut -d':' -f2) # parse selected build & MC version
        if [ "$(echo "$opt" | cut -d':' -f1)" != "$latest_build" ]; then
          latest_version="$(echo "$opt" | cut -d':' -f1)"
          if [ -n "$(curl -s "$PAPER_API/versions/$latest_version" | jq ".builds | select(.[]==$latest_build)")" ]; then
            build_found=true  # build exists for this MC version
          fi
        else
          while read ver; do # find MC version for specified build
            if [ -n "$(curl -s "$PAPER_API/versions/$ver" | jq ".builds | select(.[]==$latest_build)")" ]; then
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
mv -f paper-*.jar "$OLD_VER_DIR/" # move old versions, to keep things clean

wget -q --show-progress -O "$filename" "$PAPER_API/versions/$latest_version/builds/$latest_build/downloads/paper-$latest_version-$latest_build.jar"
chmod +x "$filename"
ln -s -f "$filename" "paper"  # make symlink, with a static name, for use in scripts
echo -e "\e[90mYou can use the \"paper\" symlink to start Paper.\n\e[32mDone!\e[0m"
