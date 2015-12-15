#!/bin/bash
# File: deleteLogs.sh
# Desc: Deletes files/dirs for specified servers that are more then X days old
# Code: by Shinto, 2007-09-07 last update

list=$1
age=$2

# Where are all the log files stored?
prefix='/raid/logs'

if [[ ! -e $list || $age == "" ]]; then
	echo "Usage: `basename $0` [server list] [age to remove]"
	exit 1;
fi

# Remove the 1-day buffer from $age so that we're storing $age days,
#+ not deleting everything over $age.  Make sense?
let age--

for box in `cat $list`; do
	echo "Looking to expire files for $box..."
	# Delete any file older than $age days old
	echo " Checking files"
	find $prefix/$box -follow -type f -mtime +$age -exec rm -v {} \;
	find $prefix/$box -follow -type f -mtime +$age -print
	# See if there are any directories I can remove
	echo " Checking directories"
	find $prefix/$box -follow -type d -empty -exec rmdir -v {} \;
	find $prefix/$box -follow -type d -empty -print
done
