#!/bin/bash
# Script to shift the defects4j line identification so that it aligns with the
# numbers in the actual diffs.
USAGE="USAGE: ./d4j_reidentify.sh [-v <version>] [-s <source path>] <project>"
src=""
while getopts ":hv:s:" opt; do
  case ${opt} in
    v )
      versions="$OPTARG"
      ;;
    s )
      src="$OPTARG"
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
if [ $# -lt 1 ]; then
  echo "Please provide a project"
  echo "$USAGE"
  exit 0
fi
project=$1
if [ "$versions" == "" ]; then
  versions="$(defects4j bids -p "$project")"
fi
set -o pipefail # necessary for checking return value of a pipe
for version in $versions; do
  echo "Version: $version"
  defects4j checkout -p "$project" -v "${version}b" -w "$project-${version}b" &> /dev/null
  defects4j checkout -p "$project" -v "${version}f" -w "$project-${version}f" &> /dev/null
  sha="$(grep "^$version," defects4j/$project.csv | cut -d ',' -f 2)"
  cd "$project-${version}f"
  filterdiff -p1 -i "$src*" "../projects/$project/diffs/$sha.diff" | patch -R -p1 &> /dev/null
  # if failed, try patching with 2 leading slashes as prefix stripped
  if [ $? -ne 0 ]; then
    filterdiff -p2 -i "$src*" "../projects/$project/diffs/$sha.diff" | patch -R -p1 &> /dev/null
    if [ $? -ne 0 ]; then
      echo "ERROR: Could not apply patch for version $version, skipping diff..."
      nopatch=1
    fi
  fi
  cd ../
  #mkdir "temp_diffs"
  if [ "$nopatch" != "1" ]; then
    diff -Nru "$project-${version}f/$src" "$project-${version}b/$src" \
      > "projects/$project/diffs/start-$version.diff"
  fi
  #cp "projects/$project/diffs/$sha.diff" "temp_diffs/$sha.diff"
  #echo "$sha" > temp_shas
  #echo "temp" >> temp_shas
  #echo "$project,2" > temp.csv
  #awk "/^[^#]*,/{flag=0}/^$version,/{flag=1}flag" "$project.csv" >> temp.csv
  #echo "2,temp" >> temp.csv
  #echo "#,temp" >> temp.csv
  #java -cp backtrack Backtrack lines temp_shas temp_diffs temp.csv "$src" > temp.json
  #python3 -c "import json;js=json.load(open('temp.json'));print(js[0]['2']['$version'])"
  #rm temp.json
  #rm temp_shas
  #rm temp.csv
  #rm -rf temp_diffs
  rm -rf "$project-${version}b"
  rm -rf "$project-${version}f"
done
