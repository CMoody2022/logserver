#!/bin/bash
# File: buildMailIndex.sh
# Desc: Builds an index of filename, MAIL FROM, and (perhaps multiple) RCPT TO
# Code: by Shinto, 2007-08-21 last update

# Root directory of all the ECs' log files
logroot='/raid/logs/10.*.2??'
# Name of the index file to create/update
index='mailindex.txt.gz'
sindex='sizeindex.txt.gz'

# Set this to 1 to create blank indexes that will be skipped in future
#+ iterations of this script, and set to 0 to make real indexes
make_blank_indexes=0

### Run continuously until the END of TIME
while [ 1 ]; do

did_some_work=0
### Walk all the directories in $logroot, look for missing index or new EC logs
# Each event channel
for ec in `ls -1d $logroot`; do
	echo "** $ec"
	# Each day
	for day in `ls -1d $ec/*`; do
		echo "* $day"
		if [[ $make_blank_indexes == 1 ]]; then
			lastlog=`ls -1 $day/ec.log* |tail -1`
			lastlog=`basename $lastlog`
			echo "Creating a blank index, $day/$index containing $lastlog"
			echo $lastlog | gzip -9 - > $day/$index
			continue
		fi
		# Do we have an existing non-empty index?
		if [ -s $day/$index ]; then
			# Update $lastlog with the latest file in the index
			lastlog=`zcat $day/$index |tail -1 |cut -d' ' -f1`
			# Get all the logs in this directory after $lastlog, excluding $lastlog
			ec_logs=`ls -1 $day/ec.log* 2>&1 |grep -A9999 $lastlog |grep -v $lastlog`
		else
			# Get all the EC logs in this directory
			ec_logs=`ls -1 $day/ec.log*`
		fi
		# Go through each log file after $lastlog
		for log in $ec_logs; do
			# Test the file first to make sure it's done downloading
			gzip -t $log >/dev/null 2>&1
			if [[ $? != "0" ]]; then
				continue;
			fi
			echo "Building an index for $log to $day/$index"
			cd $day
			log=`basename $log`
			/usr/local/bin/opsadmin/filterEC.pl $log |gzip -9 - >> $day/$index
			/usr/local/bin/opsadmin/filterECsizes.pl $log |gzip -9 - >> $day/$sizeindex
			did_some_work=1
		done
	done
done

# We don't need to continue walking the directories if we're just making blanks
if [[ $make_blank_indexes == 1 ]]; then
	exit
fi

if [[ $did_some_work == 0 ]]; then
	# Give the server a little breathing room before the next iteration
	#+ if I didn't process any new files this time around
	echo -n '.'
	sleep 10s
fi

done
