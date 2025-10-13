#!/bin/bash
red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`
reset=`tput sgr0`
USAGE="./check_backtrack.sh [-v \"<version>...\"] <log dir> <project>"
while getopts ":hv:" opt; do
  case ${opt} in
    v )
      versions="$OPTARG"
      ;;
    h )
      echo "$USAGE"
      exit 0
      ;;
    \? )
      echo "$USAGE"
      exit 0
      ;;
  esac
done
shift $((OPTIND -1))
if [ $# -lt 2 ]; then
  echo "$USAGE"
  exit 0
fi
log_dir="$1"
project="$2"
backtrack_file="$log_dir/${project}_backtrack.json"
sha_file="$log_dir/${project}_shas.csv"
srcs=($(cat "$log_dir/${project}_src.txt" | grep "^--include" | cut -d ' ' -f 2))
for i in "${!srcs[@]}"; do
  srcs[$i]="${srcs[$i]}/"
done
proj_dir="projects/$project"
curr_dir="$PWD"
num_bugs="$(grep "\"bug\"" "$backtrack_file" | wc -l)"
shas=( "" $(cat "$sha_file") )
if [ "$versions" == "" ]; then
  versions="$(seq 1 "$num_bugs")"
fi
for bug in $versions; do
  unset bug_lines all_lines
  declare -A bug_lines
  declare -A all_lines
  for ((version=$bug; version <= $num_bugs; version++)); do
    #echo "Trying bug $bug in version $version"
    backtrack="$(python3 backtrack.py "$backtrack_file" "$bug" "$version")"
    if [[ "$backtrack" =~ "Bug not found:"* ]]; then
      echo "${yellow}Bug $bug failed in version $version${reset}"
      break
    else
      cd "$proj_dir"
      cur_file_names=("${!bug_lines[@]}")
      for file in $backtrack; do
        filename="$(echo "$file" | cut -d ',' -f 1)"
        if [ "$bug" == "$version" ]; then
          # Get the full file
          tmp_err="$(mktemp)"
          full_file="$(git show "${shas[$bug]}^:${srcs[0]}$filename" 2> "$tmp_err")"
          if [[ "$(cat "$tmp_err")" =~ "fatal:"* ]]; then
            full_file="$(git show "${shas[$bug]}^:${srcs[1]}$filename")"
          fi
          rm "$tmp_err"
          # check for start diff
          if [ -f "diffs/start-$bug.diff" ]; then
            tmp_file="$(mktemp)"
            echo "$full_file" > "$tmp_file"
            # get the relevant diff
            perl_re='m{^diff.*\Q'"$filename"'\E}...m{^diff} and !m{^diff(?!.*\Q'"$filename"'\E)} and print'
            diff="$(perl -ne "$perl_re" "diffs/start-$bug.diff")"
            if [ -n "$diff" ]; then
              full_file="$(patch -s -N -o - -r - "$tmp_file" <(echo "$diff") 2> /dev/null)"
            fi
            rm "$tmp_file"
          fi
        else
          # check if file has been renamed
          if [[ "${cur_file_names[@]}" != *"$filename"* ]]; then
            # first, if only one file, link to that
            if [ "${#cur_file_names[@]}" -eq 1 ]; then
              ofilename="${cur_file_names[@]}"
            # else try to find the best fuzzy match
            else
              found=0
              fuzzy_val=0
              fuzzy_file=""
              for fn in "${cur_file_names[@]}"; do
                cur_fuzzy="$(java -cp "$curr_dir/backtrack" LCS "$filename" "$fn")"
                if [ "$cur_fuzzy" -ge 70 ] && [ "$cur_fuzzy" -ge "$fuzzy_val" ]; then
                  if [ "$cur_fuzzy" -eq "$fuzzy_val" ]; then
                    # if equal, check which string length is closer
                    cur="$(echo $((${#filename} - ${#fuzzy_file})) | sed 's/-//')"
                    new="$(echo $((${#filename} - ${#fn})) | sed 's/-//')"
                    if [ "$new" -lt "$cur" ]; then
                      fuzzy_val="$cur_fuzzy"
                      fuzzy_file="$fn"
                    fi
                  else
                    fuzzy_val="$cur_fuzzy"
                    fuzzy_file="$fn"
                  fi
                fi
              done
              if [ $fuzzy_val -gt 0 ]; then
                ofilename="$fuzzy_file"
              fi
            fi
            if [ "$ofilename" != "" ]; then
              # add the new filename as an alias to the previous one
              bug_lines["$filename"]="${bug_lines[$ofilename]}"
              all_lines["$filename"]="${all_lines[$ofilename]}"
              # remove old filename
              unset "bug_lines[$ofilename]"
              unset "all_lines[$ofilename]"
              echo "Detected file name change $ofilename -> $filename"
            fi
          fi
        fi
        # Get lines
        lines=($(echo "$file" | cut -d ',' -f 1 --complement --output-delimiter ' '))
        for line in "${lines[@]}"; do
          if [ "$bug" == "$version" ]; then
            bline="$(echo "$full_file" | sed "${line}q;d")"
            if [ "${all_lines[$filename]}" == "" ]; then
              bug_lines["$filename"]="$bline"
              all_lines["$filename"]="$line"
            else
              bug_lines["$filename"]+=$'\n'"$bline"
              all_lines["$filename"]+=$'\n'"$line"
            fi
          else
            tmp_err="$(mktemp)"
            vline="$(git show "${shas[$version]}^:${srcs[0]}$filename" 2> "$tmp_err" | sed "${line}q;d")"
            if [[ "$(cat "$tmp_err")" =~ "fatal:"* ]]; then
              rm "$tmp_err"
              vline="$(git show "${shas[$version]}^:${srcs[1]}$filename" 2> "$tmp_err" | sed "${line}q;d")"
              if [[ "$(cat "$tmp_err")" =~ "fatal:"* ]]; then
                echo "${red}ERROR: Version $version does not contain $filename for bug $bug${reset}"
                cd "$curr_dir"
                continue 3
              fi
            fi
            rm "$tmp_err"
            found=0
            fuzzy_val=0
            fuzzy_line=""
            fuzzy_line_no=""
            readarray -t blines <<< "${bug_lines[$filename]}"
            readarray -t alines <<< "${all_lines[$filename]}"
            for (( i=0; i<"${#blines[@]}"; i++ )); do
              bline="${blines[$i]}"
              if [ "$vline" == "$bline" ]; then
                found=1
                break
              else
                cur_fuzzy="$(java -cp "$curr_dir/backtrack" LCS "$vline" "$bline")"
                if [ "$cur_fuzzy" -ge 70 ] && [ "$cur_fuzzy" -gt "$fuzzy_val" ]; then
                  fuzzy_val="$cur_fuzzy"
                  fuzzy_line="$bline"
                  fuzzy_line_no="${alines[$i]}"
                fi
              fi
            done
            # Check if fuzzy found
            if [ $found -eq 0 ] && [ $fuzzy_val -gt 0 ]; then
                echo "${yellow}Fuzzy match for bug $bug line $filename $line ($fuzzy_val):${reset}"
                echo -e "Line:\t\t\"$vline\""
                echo -e "Bug line ($fuzzy_line_no):\t\"$fuzzy_line\""
            elif [ $found -eq 0 ]; then
              echo "${red}ERROR: Bug $bug in version $version has differing line $filename $line${reset}"
              echo -e "Line:\t\t\"$vline\""
              readarray -t blines <<< "${bug_lines[$filename]}"
              readarray -t alines <<< "${all_lines[$filename]}"
              for (( i=0; i<"${#alines[@]}"; i++ )); do
                echo -e "Bug line (${alines[$i]}):\t\"${blines[$i]}\""
              done
              cd "$curr_dir"
              continue 3
            fi
          fi
        done
      done
      if [ "$bug" == "$version" ]; then
        echo "Bug $bug Lines:"
        for filename in "${!bug_lines[@]}"; do
          echo "File $filename"
          readarray -t blines <<< "${bug_lines[$filename]}"
          readarray -t alines <<< "${all_lines[$filename]}"
          for (( i=0; i<"${#alines[@]}"; i++ )); do
            echo -e "${alines[$i]}:\t\"${blines[$i]}\""
          done
        done
        echo "-------------------- End --------------------"
      fi
      echo "${green}Bug $bug fine in version $version${reset}"
      cd "$curr_dir"
    fi
  done
done
