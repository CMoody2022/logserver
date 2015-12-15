#!/usr/bin/perl
# File: filterEC.pl
# Desc: Extracts FROM and (multiple) RCPT addresses from a gzipped ec log
# Code: by Shinto, 2007-04-12

$log=$ARGV[0];
open(LOG,"zcat $log |");

while (<LOG>) {
	next unless (s/.*(<MAIL from=)/ $1/);
	s/<RCPTDISP[^>]*>//;
	s/<\/RCPTDISP>.*//;
	s/ num=[^>]*/\//g;
	s/<MAIL from=.//;
	s/<RCPT to=.//g;
	s/.\/>/ /g;
	s/<SKIP.*RCPT>//;
	print $log;
	print;
}

close(LOG);
