#!/bin/sh
# File: log_searchable_ages.sh
# Desc: Build an average age of all EC and MTA logs on the logserver, and
#+      for ECs, the average latency in EC log indexing
# Code: by Shinto on 2009-11-04, last updated 2011-11-16


verbose=0
if [ "$1" = "-v" -o "$1" = "--verbose" ]; then
	verbose=1;
fi
if [ "$1" = "-d" -o "$1" = "--debug" ]; then
	verbose=1;
	debug=1;
fi

# Specify the minimum number of log files per server to consider in the average
minlogs='0'

# Specify the first 3 octets of sites/servers that should be ignored
ignore_sites='10.14.12 10.15.12 10.16.12 10.17.12 10.18.12'
#ignore_sites=''

##### Gather MTA log stats (mta.log.*) ##### 
total_ib_log=0
total_ob_log=0
total_q_log=0
servercount_ib=0
servercount_ob=0
servercount_q=0

[ $verbose = "1" ] && echo -e "Server\t\tLog File Age"

for mta in `cat /root/dist/mail`; do
	# Skip servers covered in $ignore_sites
	first3=`echo $mta |cut -d. -f1-3`
	if [ `echo "$ignore_sites" |grep -c "$first3"` = 1 ]; then
		[ $verbose = "1" ] && echo -e "$mta\t'$first3' is in \$ignore_sites.  Skipping."
		continue
	fi

	lastday=`ls -1d /raid/logs/$mta/2* 2>/dev/null |tail -1`;

	if [ -z "$lastday" ]; then
		[ $verbose = "1" ] && echo -e "$mta\tNo YYYYMMDD directories found.  Skipping."
		continue
	fi

	# Look for at least two logs with each MTA.  Servers in decom, or 
	#+ servers not yet taking traffic may artificially inflate the average
	numlogs=`ls -1 $lastday/mta.log* 2>/dev/null |wc -l`
	if [ "$numlogs" -lt "$minlogs" ]; then
		[ $verbose = "1" ] && echo -e "$mta\tToo few logs ($numlogs).  Skipping."
		continue
	fi


	last_log=`ls -1 $lastday/mta.log* 2>/dev/null |tail -1 |sed 's/.*mta.log.//;s/-..gz//;s/\(....\)\(..\)\(..\)-\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/'`

	# If no log exists in $lastday, then we must not have anything yet.
	#+ Set last_log to today's maximum midnight this morning)
	if [ -z "$last_log" ]; then
		last_log=`date +"%Y-%m-%d 00:00:00"`
	fi
	# Convert this timestamps to seconds
	sec_log=`date -d "$last_log" +%s`
	
	# Compare $sec_* to the current time to get a time delta
	now=`date +%s`
	let delta_log=$now-$sec_log
	
	# Update rolling averages depending on the server type (4rd octet)
	fourth=`echo $mta |cut -d. -f4`
	if [ $fourth -gt 160 ]; then
		let total_q_log+=delta_log
		let servercount_q++
	elif [ $fourth -gt 140 ]; then
		let total_ob_log+=delta_log
		let servercount_ob++
	else
		let total_ib_log+=delta_log
		let servercount_ib++
	fi
	[ $verbose = "1" ] && echo -e "$mta\t$last_log ($sec_log)"
done

# Calculate the average time deltas, convert to hours
avg_ib_log=`echo "scale=1;($total_ib_log/$servercount_ib)/3600" |bc 2>/dev/null`
avg_ob_log=`echo "scale=1;($total_ob_log/$servercount_ob)/3600" |bc 2>/dev/null`
avg_q_log=`echo "scale=1;($total_q_log/$servercount_q)/3600" |bc 2>/dev/null`


##### Gather Event Channel log stats (ec.log.*) ##### 
total_log=0
total_index=0
servercount=0

[ $verbose = "1" ] && echo -e "Server\t\tLog File Age\t\t\t\tIndex Log File Age"

for ec in `cat /root/dist/ec`; do
	# Skip servers covered in $ignore_sites
	first3=`echo $ec |cut -d. -f1-3`
	if [ `echo "$ignore_sites" |grep -c "$first3"` = 1 ]; then
		[ $verbose = "1" ] && echo -e "$mta\t'$first3' is in \$ignore_sites.  Skipping."
		continue
	fi
	lastday=`ls -1d /raid/logs/$ec/2* |tail -1`;
	last_log=`ls -1 $lastday/ec.log* |tail -1 |sed 's/.*ec.log.//;s/-..gz//;s/\(....\)\(..\)\(..\)-\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/'`
	last_ndx=`zcat $lastday/mailindex.txt.gz 2>/dev/null |tail -10 |grep -P '^ec.log.\\d\\d\\d\\d\\d\\d\\d\\d-\\d\\d\\d\\d\\d\\d' |tail -1 |cut -d' ' -f1 |sed 's/.*ec.log.//;s/-..gz//;s/\(....\)\(..\)\(..\)-\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/'`;
	# Skip further processing on this server on an error condition
	#+ ('unexpended end of file' is common)
	if [ -z "$lastday" -o -z "$last_log" -o -z "$last_ndx" ]; then
		[ $verbose = "1" ] && echo -e "$ec\tNo YYYYMMDD directories found.  Skipping."
		continue
	fi
	
	# Look for at least two logs with each EC.  Servers in decom, or 
	#+ servers not yet taking traffic may artificially inflate the average
	numlogs=`ls -1 $lastday/ec.log* 2>/dev/null |wc -l`
	if [ "$numlogs" -lt "$minlogs" ]; then
		[ $verbose = "1" ] && echo -e "$ec\tToo few logs ($numlogs).  Skipping."
		continue
	fi


	# Convert these timestamps to seconds
	sec_log=`date -d "$last_log" +%s`
	sec_ndx=`date -d "$last_ndx" +%s`
	
	# Compare $sec_* to the current time to get a time delta
	now=`date +%s`
	let delta_log=$now-$sec_log
	let delta_ndx=$now-$sec_ndx
	
	# Update rolling averages
	let total_log+=delta_log
	let total_ndx+=delta_ndx
	let servercount++
	
	[ $verbose = "1" ] && echo -e "$ec\t$last_log ($delta_log)\t$last_ndx ($delta_ndx)\ttotal_ndx=$total_ndx, servercount=$servercount"
done

# Calculate the average time deltas, convert to hours
avg_log=`echo "scale=2;($total_log/$servercount)/3600" |bc`
avg_ndx=`echo "scale=2;($total_ndx/$servercount)/3600" |bc`


# Dump my results to the screen, if I'm in verbose mode
if [ $verbose = "1" ]; then
	cat <<END_TEXT
Average age of latest inbound mta.log file: $avg_ib_log hours
Average age of latest outbound mta.log file: $avg_ob_log hours
Average age of latest bounce/unspool mta.log file: $avg_q_log hours

Average age of latest ec.log file: $avg_log hours
Average age of latest indexed ec.log file: $avg_ndx hours
END_TEXT
fi

[ "$debug" = "1" ] && exit

# Write this stuff to a stat file
cat <<END_TEXT > /tmp/log_searchable_ages.sh.stat
Average age of latest inbound mta.log file: $avg_ib_log hours
Average age of latest outbound mta.log file: $avg_ob_log hours
Average age of latest bounce/unspool mta.log file: $avg_q_log hours
Average age of latest ec.log file: $avg_log hours
Average age of latest indexed ec.log file: $avg_ndx hours
END_TEXT
