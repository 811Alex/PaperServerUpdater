#!/bin/bash

# CONST
PAPER_API='https://api.papermc.io/v2/projects/paper'
PAPER_DIR="$(dirname "$(realpath "$0")")"               # run @ location of the script
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

# FUNCTIONS
tolower(){ awk '{print tolower($0)}' <<< "$@"; }
apiget(){ [ -n "$2" ] && (curl -s "$PAPER_API/$1" | jq ${@:3} "$2"; true) || (curl -s "$PAPER_API" | jq "$1"); }  # (jq commands) or (API path, jq commands, [jq flags])
abort(){ echo -e "\e[$( ([ -n "$2" ] && [ $2 -ne 0 ]) && echo '31' || echo '32')m$1\e[0m"; exit $2; }       # (message, [exit code])

# VERSION NUMBERS
versions=$(apiget '.versions')
if [ -z "$latest_version" ]; then
  latest_version=$(echo "$versions" | jq -r '.[-1]')                      # get latest version
else
  echo -en "\e[35mLooking up matching versions... \e[0m"
  version_pattern="^$(sed 's/\.\*$/(&)?/g; s/\./\\\\./g; s/\*/.*/g' <<< "$latest_version")$"  # make regex
  matching_versions=$(jq "[.[] | match(\"$version_pattern\").string]" <<< "$versions")
  echo -e "\e[36m$(jq -r 'join("\\e[35m, \\e[36m")' <<< "$matching_versions")\e[0m"
  $(jq 'isempty(.[])' <<< "$matching_versions") && abort "Can't find a matching version!" 2   # no matching versions
  latest_version="$(jq -r '.[-1]' <<< "$matching_versions")"
  echo -e "\e[35mSelected latest matching version: \e[32m$latest_version\e[0m"
fi
latest_ver_builds=$(apiget "versions/$latest_version/builds" '.builds')
latest_build=$(jq '.[-1].build' <<< "$latest_ver_builds")                 # get latest build
filename="paper-${latest_version}-${latest_build}.jar"

cd "$PAPER_DIR"
! $force_update && [ -e "$filename" ] && abort 'You already have the latest version of Paper!'  # the latest version already exists here

# PRINT CHANGES
if $print_changes && curr="$(ls -1 paper-* 2>/dev/null)"; then            # if we have downloaded previous builds
  curr="$(sort -V <<< "$curr" | tail -n1 | rev | cut -d'.' -f2- | rev)"
  curr_ver=$(cut -d'-' -f2 <<< "$curr")                                   # extract latest downloaded MC version
  curr_build=$(cut -d'-' -f3 <<< "$curr")                                 # extract latest downloaded build number
  if [[ $curr_build =~ ^[0-9]+$ ]] && [ -n "$(jq "select(.[]==\"$curr_ver\" and .[]==\"$latest_version\")" <<< "$versions")" ]; then # curr build is number & curr and latest ver. exist
    included_versions=$(jq -r ".[index(\"$curr_ver\"):index(\"$latest_version\")+1][]" <<< "$versions")
    included_ver_num=$(wc -l <<< "$included_versions")

    [ -n "$included_versions" ] &&
    while read loop_ver; do                                               # for each MC version from current to latest
      if [ $included_ver_num -gt 1 ]; then
        echo -e "\e[35mChanges for \e[1;35m$loop_ver\e[0;35m:\e[0m"
        latest_ver_builds="$(apiget "versions/$loop_ver/builds" '.builds')"
        if $(jq 'isempty(.[])' <<< "$latest_ver_builds"); then
          echo -e "\e[1;31mNone found!\e[0m"
          if [ "$loop_ver" == "$latest_version" ]; then
            latest_version=$(jq -r ".[index(\"$latest_version\")-1]" <<< "$versions")
            filename="paper-${latest_version}-${latest_build}.jar"
            ! $force_update && [ -e "$filename" ] && abort 'You already have the latest version of Paper!'  # the latest version already exists here
          fi
          continue
        fi
        latest_build=$(jq '.[-1].build' <<< "$latest_ver_builds")
      elif [ $curr_build -lt $latest_build ]; then
        echo -e "\e[35mChanges:\e[0m"
      fi
      latest_ver_builds="$(jq -c '.[]' <<< "$latest_ver_builds")"
      [ "$loop_ver" = "$curr_ver" ] && latest_ver_builds="$(jq -c "select(.build > $curr_build)" <<< "$latest_ver_builds")"

      indent=${#latest_build}
      format_summary="\e[1;36m%-${indent}s \e[1;32m%s\e[0m\n"
      format_upstream_header="%-$((indent + 2))s \e[1;34m%s\e[0m\n"
      format_upstream_message="%-$((indent + 4))s \e[1;33m%s\e[0m\n"
      format_nochange="\e[1;36m%-${indent}s \e[1;31m%s\e[0m\n"
      format_ciskip="\e[1;36m%-${indent}s \e[1;30m%s\e[0m\n"

      [ -n "$latest_ver_builds" ] &&
      while read -r loop_build; do          # for each build of this MC version, from current/first to latest
        changes="$(jq '.changes' <<< "$loop_build" | jq -sc '.[] | to_entries[] | {key} + .value')"  # get (enumerated) build info
        build_num=$(jq '.build' <<< "$loop_build")
        if [ -n "$changes" ]; then
          while read -r loop_change; do     # for each change in build
            change_build_num=$([ $(jq '.key' <<< "$loop_change") -eq 0 ] && echo "$build_num")       # only print num if first change
            change_summary="$(jq -r '.summary' <<< "$loop_change")"
            change_summary_format="$([[ "$(tolower "$change_summary")" =~ ^\[ci[-\ ]skip\] ]] && echo "$format_ciskip" || echo "$format_summary")" # color ci skips
            printf "$change_summary_format" "$change_build_num" "$change_summary"
            if [[ "$(tolower "$change_summary")" =~ ^(\[auto\]\ )?updated\ upstream ]]; then  # if it starts with [Auto], it was an upstream update, so show the message too, which includes the upstream changes
              while read msg_line; do                                                         # format each line of the message, skip unrelated/empty lines
                if [[ "$(tolower "$msg_line")" =~ changes:$'\r'?$ ]]; then                    # upstream name/header
                  printf "$format_upstream_header" '' "$msg_line"
                elif [[ "$(tolower "$msg_line")" =~ ^[a-f0-9]{8,}\  ]]; then                  # upstream commit message
                  printf "$format_upstream_message" '' "$msg_line"
                fi
              done <<< "$(jq -r '.message' <<< "$loop_change")"
            fi
          done <<< "$changes"
        else
          printf "$format_nochange" "$build_num" "No changes"
        fi
      done <<< "$latest_ver_builds"
    done <<< "$included_versions"

    if ! $assume_yes; then                            # ask if we should proceed with the update
      if [ "$curr_ver" = "$latest_version" ]; then
        update_text="\e[36m$curr_build\e[35m->\e[36m$latest_build"
      else
        update_text="\e[36m$curr_ver\e[35m:\e[36m$curr_build\e[35m->\e[36m$latest_version\e[35m:\e[36m$latest_build"
      fi
      echo -en "\e[35mUpdate $update_text\e[35m? [Y/n/[<MC ver.>:]<build num.>]: \e[0m"
      read -r opt
      if [[ "$opt" =~ ^([0-9]+\.[0-9]+(\.[0-9]+)?:)?[0-9]+$ ]]; then
        echo -e "\e[35mLooking up build...\e[0m"
        build_found=false
        latest_build=$(cut -d':' -f2 <<< "$opt")      # parse selected build & MC version
        if grep ':' <<< "$opt" >/dev/null; then
          latest_version="$(cut -d':' -f1 <<< "$opt")"
          [ -z "$(jq "select(.[]==\"$latest_version\")" <<< "$versions")" ] && abort 'Version not found!' 4         # no such MC version
          [ -n "$(apiget "versions/$latest_version" ".builds | select(.[]==$latest_build)")" ] && build_found=true  # build exists for this MC version
        else
          while read ver; do                          # find MC version for specified build
            if [ -n "$(apiget "versions/$ver" ".builds | select(.[]==$latest_build)")" ]; then
              latest_version="$ver"
              build_found=true
              break
            fi
          done <<< "$(jq -r ".[([index(\"$curr_ver\"),index(\"$latest_version\")]|min):index(\"$latest_version\")+1][]" <<< "$versions")"
        fi
        $build_found || abort 'Build not found!' 1
        echo -e "\e[1;32mFound \e[35m$latest_version\e[32m:\e[35m$latest_build\e[32m!\e[0m"
        filename="paper-${latest_version}-${latest_build}.jar"
      elif [ -n "$opt" ] && [ "$opt" != "y" ] && [ "$opt" != "Y" ]; then
        abort 'Canceled!'
      fi
    fi
  fi
fi

# DOWNLOAD UPDATE
echo -e "\e[35mUpdating Paper...\e[0m"
mkdir -p "$OLD_VER_DIR"
mv -f paper-*.jar "$OLD_VER_DIR/"   # move old versions, to keep things clean

dl_info="$(apiget "versions/$latest_version/builds/$latest_build" '.downloads.application//""')"
dl_filename="$(jq -r ".name//\"paper-${latest_version}-${latest_build}.jar\"" <<< "$dl_info")"
wget -q --show-progress -O "$filename" "$PAPER_API/versions/$latest_version/builds/$latest_build/downloads/$dl_filename"
chmod +x "$filename"
ln -s -f "$filename" "paper"        # make symlink, with a static name, for use in scripts
echo -e "\e[90mYou can use the \"paper\" symlink to start Paper.\n\e[32mDone!\e[0m"
