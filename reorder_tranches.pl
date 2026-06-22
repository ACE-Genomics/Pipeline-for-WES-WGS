#!/usr/bin/perl
use strict;
use warnings;
my @tranches = (100.0, 99.95, 99.9, 99.5, 99.0, 97.0, 96.0, 95.0, 94.0, 93.5, 93.0, 92.0, 91.0, 90.0);
my $tables_dir;
while (@ARGV and $ARGV[0] =~ /^-/) { 
	$_ = shift; 
	last if /^--$/; 
	if (/^-d/) 
	{ $tables_dir = shift; chomp($tables_dir);} 
}

my $ofile = $tables_dir.'/wes_joint_alltranches.table';
open ODF, ">$ofile";
my $written = 0;
foreach my $tranche (@tranches) {
	(my $str_tranche = $tranche) =~ s/\.//;
	my $isfirst = 1;
	open IDF, "$tables_dir/wes_joint.$str_tranche.table";
	while (<IDF>) {
		chomp;
		if($isfirst) {
			print ODF "$_\tTRANCHE\n" unless $written;
			$isfirst = 0;
			$written = 1;
		}else{
			print ODF "$_\t$tranche\n";
		}
	}
	close IDF;
}
close ODF;

