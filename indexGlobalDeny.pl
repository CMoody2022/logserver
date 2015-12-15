#!/usr/bin/perl
# File: indexGlobalDeny.pl
# Desc: Creates rolling persistent caches of IPs added to each event channel's
#+      global-deny-list.xml file
# Code: by Shinto, 2009-09-03 last update

use strict;
use Time::Local;
use DB_File;

# Check to see if I already have an instance of this script running
my $pid=`pgrep indexGlobalDeny`; chomp($pid);
if ($pid =~ /\n/) {	# If there is more than one $pid, it'll have a '\n'
	print "This script is already running.\n";
	exit(1);
}

# Which /root/dist list contains all the IPs running mxl_threat_analyzer?
my $distlist='/root/dist/ec.allsites';	
# Where to store my cache (base filename, EC IP will be appended to it)
my $cache='/home/www/html/ts/data/access_lists/indexGlobalDeny.cache';
# The full path to global-deny-list.xml on the ECs
my $global_deny='/mxl/var/update/default/global-deny-list.xml';
# Specify the retention time (seconds) for the cache, anything older is expired.
my $retention=24*60*60;	# 24 hours

my $debug=0;
if ($ARGV[0] =~ /-d/ || $ARGV[0] =~ /-v/) {
	$debug=1;
	$|=1;	# Flush writes to the screen
}

# Get the blacklist duration from the threat_analyzer config so that I can
#+ determine when each IP was blacklisted
my $duration=`/mxl/bin/get_config_entry -f /mxl/etc/mod_threat_analyzer.xml -S "config/threats/harvest?blacklist_duration" 2>/dev/null`;
chomp($duration);

if ($duration !~ /^\d/) {
	print "Error reading blacklist_duration, expected a number but got '$duration'\n";
	exit(1);
}

my %memcache=();

# Pull the latest global-deny-list data from each EC
open(SERVERS,'<' . $distlist) || die "Unable to open $distlist: $!\n";
while (<SERVERS>) {
        chomp;
        my $server = $_;
        # Ignore lines that don't start with a number (blanks, comments, etc.)
	next unless ($server =~ /^\d/);
	# Load up the existing cache into memory
	%memcache=();
	my $now=time();
	print "Loading existing cache for $server into memory..." if ($debug);
	tie(%memcache, "DB_File", "$cache.$server", O_RDWR()|O_CREAT(), 0640, $DB_HASH);
	foreach my $key (keys(%memcache)) {
		my ($ec,$ip,$start,$end)=split(/\t/,$key);
		# Delete expired entries, or entries that are blank
		if ($end < $now-$retention || length($ip) == 0) {
			delete($memcache{$key});
		}
	}
	close(CACHE);
	print "done, ".scalar(keys(%memcache))." records cached\n" if ($debug);

	&fetchDenyList($server);

	# Flush (save) @memcache to disk
	print "Saving cache..." if ($debug);
	untie(%memcache);
	print "done\n" if ($debug);

}
close SERVERS;


# This proc will pull the list from the specified server and process it,
#+ looking for new stuff to add to the memory cache @memcache
sub fetchDenyList($) {
	my $ec=$_[0];
	print "Loading data from $ec..." if ($debug);
	my $list=`ssh -o ConnectTimeout=5 $ec "cat $global_deny"`; chomp($list);
	$list =~ s/\/><\/deny_ip_records.*$//;	# Strip out stuff at the end
	$list =~ s/^<access.*records><//;	# Strip out stuff at the front
	print "done\n" if ($debug);
	print " Processing deny list: " if ($debug);
	foreach my $entry (split/\/></,$list) {
		# Each $entry will look like this:
		#+ deny_ip ip='98.21.158.198' until='20080505 17:12:02'
		$entry =~ /deny_ip ip='(.*)' until='(.*)'/;
		my $ip=$1; my $end_ts=$2;
		next unless (length($ip)>0);
		# Convert $end to a UNIX timestamp
		$end_ts =~ /(....)(..)(..) (..):(..):(..)/;
		my ($Y,$M,$D,$h,$m,$s)=($1,$2,$3,$4,$5,$6);
		if ($M == 0) {
			print "\n\$M is 0!  How did that happen from $end_ts ($Y-$M-$D $h:$m:$s)\n";
		}
		$M--;
		my $end=timelocal($s,$m,$h,$D,$M,$Y);
		# Determine the start time
		my $start=$end-$duration;

		# Put this entry in the %memcache hash.  Since it's a hash,
		#+ there won't be any duplicate data.
		$memcache{"$ec\t$ip\t$start\t$end"}=1;
#		print '.' if ($debug);
	}
	print "done\n" if ($debug);
}
