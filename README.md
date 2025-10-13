# Bug location identification backtracking tool
This directory contains all the necessary components needed to track
("backtrack") locations of faulty elements to previous versions
through git histories. This is mostly done by the `backtrack.jar` JAR file,
however there are also some helper scripts included to setup the project
backtracking.
# Requirements
1. `Bash`
2. [`patchutils`](https://directory.fsf.org/wiki/Patchutils)
# Usage
## Input
To use this backtracking tool, you must have the commit hashes of the bug fixing
commits for each bug. You may optionally use manually identified line numbers
for the buggy locations, otherwise the lines of the bug fixing commits will be
used. The options for each input type are given below.
### Automatic identification by commits
To automatically use the line numbers of the changes present in the bug fixing
commits, simply produce a file of the form:
```
<commit hash #1>
<commit hash #2>
.
.
.
```
where each `<commit hash>` is the commit hash for the bug fixing commit. The
commits in the file MUST be ordered from latest to oldest.
### Manually identified lines
To use manually identified line numbers, each project should have a separate CSV
file of the form:
```
<project name>,<number of bugs>
<bug number>,<commit hash>
#,<file path>,<line number>:<line number>:...
#,<file path>,<line number>:<line number>:...
.
.
.
```
For instance, if the project name is dummy, and there are 3 identified faults,
the first is from commit `aec4a1` and is on line 2 of the file
`dummy/com/git/One.java`, the second is from commit `b8c516` and is on line 5
and 6 of the file `dummy/com/git/Two.java`, and the third from commit `47e5b6` and
is on line 4 of the file `dummy/com/git/Three_one.java`, and line 6 of the file
`dummy/com/git/Three_two.java`. The CSV file would be:
```
dummy,3
1,aec4a1
#,dummy/com/git/One.java:2
2,b8c516
#,dummy/com/git/Two.java:5:6
3,47e5b6
#,dummy/com/git/Three_one.java:4
#,dummy/com/git/Three_two.java:6

```
### Defects4J
The manually identified line numbers of the `Defects4J` projects, available in
the `defects4j-bugs.json` file from [Defects4J
Dissection](https://github.com/program-repair/defects4j-dissection) may be used.
To use these, extract the information from the `defects4j-bugs.json` file by
using the `compile_bugs.py` script as follows:
```
python3 compile_bugs.py
```
executed in the directory where the `defects4j-bugs.json` file is.
Once this is complete, CSV files of the form `<project>.csv` will be available
containing the line numbers for each project version.
## Create diffs
In order to run the backtracking, a full list of (*backwards*) git diffs must be available. To
achieve this, the script `gen_diffs.sh` is provided. To use this script, clone
the project repository into `projects` and navigate to the projects base
directory. Then use the `gen_diffs.sh` script by typing:
```
../../gen_diffs.sh <initial SHA> <final SHA>
```
where `<inital SHA>` points to the most recent commit to include, and `<final SHA>`
points to the oldest commit to include.

## Defects4j diff fix
The Defects4J versions included in the Defects4J repository are unfortunately
not exactly the same as the base versions from the original projects. In order
to deal with this phenomenon, a diff between the actual base version and the
supplied Defects4J version needs to be created and inserted into the diff
history so that the backtracking algorithm can correctly backtrack the bugs into
earlier versions. This can be done automatically by running the
`d4j-reidentify.sh` script using the following format:
```
./d4j_reidentify.sh [-v <version>] [-s <source directory>] <project>
```
If no version is given, the script will be run over all of the project's bugs.
The source directory can be left out, which will just generate the diffs over
the full project structure (slightly more inefficient and harder to read).

This will place `start-<version>.diff` diff files for each version in the diff
directory for each project located in `projects`.
## Run the backtracking
In order to run the backtracking, the `backtrack.jar` file has been provided
(with sources in the `backtrack` directory. To see the running instructions,
type:
```
java -jar backtrack.jar
```
The backtracking algorithm needs three things to run:
1. The SHA file `all_shas` produced by the `gen_diffs.sh` script
2. The `diffs` directory of all diffs to include also produced as above
3. The bug location identification in either format from [the above](#input)
You may also give the following optional arguments:
1. `--file-type`: The file type to consider (`.py`, `.java`, etc.)
2. `--include`: Specify a directory who's contents will be tracked
3. `--exclude`: Specify a directory who's contents will NOT be tracked
# Description of backtracking algorithm
The actual backtracking algorithm works by constructing a list of lines for the
bug fix that need to be backtracked to previous versions. It then considers each
backwards diff in the git history and applies the diffs to the lines for the
bug fix. For this process, if lines above the bug fixes tracked line is changed,
then the tracked line's line number is changed in accordance with the shift
incurred. If a tracked line in the bug fix is directly modified or deleted, then
that line is removed from tracking as it can no longer be assumed to be buggy.

If all of the lines in a tracked bug fix are removed, the bug fix no longer
contains any viable locations, and thus the backtracking fails for that diff. If
this does not occur, the bug fix will be backtracked until the oldest commit
specified, and at each stage in the git history the updated bug fix lines are printed
out.
