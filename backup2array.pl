#!/usr/bin/perl
# File: backup2array.pl
# Desc: Moves certain files older than X number of days off certain remote
#+      servers and onto the local volume
# Code: Original author unknown; now managed by Shinto, 2007-07-30 last update

use strict;

my $read_only=0;	# If set to 1, do not delete files off the remote server

my $error_log = '/tmp/backup2array.err';

sub Usage {
	my $message=@_[0];
	print $message . "\n" if ($message);
	print "Usage: $0 [server list] [age to pull] [file core]\n";
	print "    [server list]  file containing a list of server IPs, one per line\n";
	print "    [age to pull]  pulls & deletes all files older than this number of days\n";
	print "                   can also add an 'h' suffix to specify hours instead of days\n";
	print "    [file core]    filename core to pull (eg, 'ec.log' will download ec.log.*)\n";
	print "                   specify multiple files separated by commas\n";
	print "                   can also be 'all' to download all log files\n";
	print " Examples: backup2array.pl /root/dist/ec 5 ec.log\n";
	print "           backup2array.pl /root/dist/mail 2h mta.log,mod_queue.log,quar_release\n";
	exit(1);
}

# Output usage information if requested
&Usage if ($ARGV[0] =~ /-h/);

my $machine_pattern='.*';
if ($ARGV[0] eq '--domestic') {
	$machine_pattern='^10.\d.1\d\d.\d+';
	shift;
} elsif ($ARGV[0] eq '--foreign') {
	$machine_pattern='^10.\d\d.12.\d+';
	shift;
}

# I expect exactly three arguments. 
&Usage('Insufficient parameters.') if (scalar(@ARGV)!=3);

# What file contains the list of servers to back up?
my $machine_list_file=$ARGV[0];
unless (-r $machine_list_file) {
	&Usage("Unable to read $machine_list_file!");
}

# Number of days to pull from the ECs
my $days_to_pull = $ARGV[1];
$days_to_pull =~ s/d$//;	# Chop a 'd' off the end, of specified (days)
my $hours_to_pull;
if ($days_to_pull =~ /h$/) {	# Guess I'll be looking at hours instead of days
	$hours_to_pull = $days_to_pull;
	$hours_to_pull =~ s/h$//;
}
# Name of the files I'll be pulling (I'll add a wildcard to the end)
my $files_to_pull = $ARGV[2];

### Where we want to backup stuff to.
my $backup_root = "/apps/falcon//logs";

### Where we store some temporary files that need to be renamed
my $tmp_dir = "$backup_root/tmp/backup2array/";

### Where we log to during actions
my $logfile = "/var/log/backup2array.log";

###################
### SUBROUTINES ###
###################

sub get_date {
  my ($mday, $mon, $year) =  (localtime(time))[3..5];

  $year += 1900;
  $mon += 1;
  $mon = "0" . $mon if ($mon <= 9);
  $mday = "0" . $mday if ($mday <= 9);

  my $date = $year . $mon . $mday;
  return ($date);
}


#######################
### MAIN CODE BELOW ###
#######################
open LOGFILE, ">>$logfile";

my $start_time = `/bin/date`;
print LOGFILE "\nStarted: $start_time";


# See if this script (plus $machine_list_file) is currently running
my $ps = `ps auxwww |grep $0 |grep $machine_list_file |grep -v grep |wc -l`;
chomp $ps;
if ( $ps > 2 ) {
	print LOGFILE "Process '$0 $machine_list_file' already running\n";
	my $end_time = `/bin/date`;
	print LOGFILE "Ended  : $end_time\n";
	print LOGFILE "=========================================================================\n";
	close LOGFILE;

	die("Process '$0 $machine_list_file' already running");
}

my $findtime;	# Time parameter to pass to 'find'
if ($hours_to_pull) {
	my $minutes_to_pull = $hours_to_pull*60;	# Convert to minutes
	print LOGFILE "Pulling $files_to_pull* logs older than $hours_to_pull hours from $machine_list_file\n";
	$findtime = "-mmin +$minutes_to_pull";
} else {
	print LOGFILE "Pulling $files_to_pull* logs older than $days_to_pull days from $machine_list_file\n";
	$findtime = "-mtime +$days_to_pull";
}

my $today = get_date();

# make the directory where we are going to store some temp files.
system "mkdir -p $tmp_dir";

open LIST, $machine_list_file or die "Cannot open $machine_list_file for reading!";

while (defined(my $ip = <LIST>)) {
  chop $ip;
  next unless ($ip =~ /^\d/);	# Omit commented-out items

  next unless ($ip =~ /$machine_pattern/);

  print $ip . "\n";
  my $findcommand = "ssh -o ConnectTimeout=5 -qt $ip '/usr/bin/find /var/log/mxl/rotate/ -type f $findtime";
  if ($files_to_pull ne 'all') {
	if ($files_to_pull =~ /,/) {
		foreach my $filecore (split(/,/,$files_to_pull)) {
			$findcommand .= " -name \"$filecore*\"";
			# Chain in another find command if I'm not at the last $filecore
			if ($files_to_pull !~ /,$filecore$/) {
			       $findcommand .= "; /usr/bin/find /var/log/mxl/rotate/ -type f $findtime";
			}
		}
	} else {
		$findcommand .= " -name \"$files_to_pull*\"";
	}
  }
  $findcommand .= " |sort'";

#  print "Find command: $findcommand\n";
  my $filelist=`$findcommand`;
  # If SSH fails, record an error and move on.
  if ($?>0) {
  	my $timestamp = `date +"%Y-%m-%d %H:%M"`; chomp($timestamp);
  	open(ERR,'>>'.$error_log);
  	print ERR "[$timestamp] Unable to connect to $ip\n";
  	close(ERR);
  	next;
  }

  ### If we get "No such file" error then move on.
  next if $filelist =~ /No such file/;

  foreach my $file (split /\n/, $filelist) {
    if ($file =~ /\n$/ || $file =~ /\r$/) {
      chop $file;
    }
    $file =~ s:/var/log/mxl/rotate/::;

    print LOGFILE "Processing ($ip) $file\n";

    $file =~ m/201(\d\d\d\d\d)/;
    my $date = "201$1";

    if ($date eq "201") {  ### No valid date found in the filename;
      my $targetpath = "$backup_root/$ip/other";
      system "mkdir -p $targetpath";

      print LOGFILE "   Downloading File...\n";
      my $command = "scp -p $ip:/var/log/mxl/rotate/$file $tmp_dir";
      print LOGFILE ":: $command\n";
      my $rc = system $command;
      if ($rc == 0) {  ## sucessful copy
        my $new_name = $file;
        $new_name =~ s/gz/$today.gz/;

        print LOGFILE "   Renaming file...\n";
        $command = "mv -f $tmp_dir/$file $targetpath/$new_name";
        system $command;
        print LOGFILE ":: $command\n";

	unless ($read_only) {
          print LOGFILE "   Removing file from remote server...\n";
          $command = "ssh -qt $ip \"rm -f /var/log/mxl/rotate/$file\"";
          system $command;
          print LOGFILE ":: $command\n";
	}
      } else {
        print LOGFILE "Command '$command' Failed!\n";
      }
    } else {  ### Filename has a valid timestamp in it.
      my $targetpath = "$backup_root/$ip/$date";
      system "mkdir -p $targetpath";
      my $command; my $rc;

      my $download=1;
      # Make sure $file isn't already on this server with a non-zero size
      if (-e "$targetpath/$file") {
	# See if the file is intact
	`gzip -t $targetpath/$file 2>&1 >/dev/null`;
	if ($? == 0) {
		print LOGFILE "   $file already exists!  Not downloading.\n";
		$download=0;
		$rc=0;
	}
      }
      if ($download) {
        print LOGFILE "   Downloading File...\n";
        $command = "scp -p $ip:/var/log/mxl/rotate/$file $targetpath/";
        $rc = system $command;
        print LOGFILE ":: $command\n";
      }

      if ($rc == 0) {  ## sucessful copy
	unless ($read_only) {
          print LOGFILE "   Removing file from remote server...\n";
          $command = "ssh -qt $ip \"rm -f /var/log/mxl/rotate/$file\"";
          system $command;
          print LOGFILE ":: $command\n";
	}
      }
      else {
        print LOGFILE "Command '$command' Failed!\n";
      }
    }
    print LOGFILE "\n\n";
  }  ### end file list loop
} ### end machine ip list loop

### Remove the tmp directory that we made earlier
system "rmdir $tmp_dir";

close LIST;

my $end_time = `/bin/date`;
print LOGFILE "Ended  : $end_time\n";

print LOGFILE "=========================================================================\n";

close LOGFILE;
