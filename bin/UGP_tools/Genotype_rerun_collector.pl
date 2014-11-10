#!/usr/bin/perl
use warnings;
use strict;
use autodie;
use Getopt::Long;

my $usage = "
Synopsis:
	./Genotype_rerun_collector.pl -ad A17,A23,A56 -cd Rerun_set

Description:
	Take comma sperated list of /Repository/AnalysisData/2014 directories and searches for 
	*final_mergeGvcf files, then cp them to a collection directory for easy scp to analysis machine.

Required options:
	--analysis_directories, -ad	comma seperated list of directories.
	--collection_directory, --cd	Name for bucket directory.

Additional options:
	--help, -h	Prints this usage statement.
\n";

my ($ad, $cd, $help);
GetOptions(
	"analysis_directries|ad=s@" => \$ad,
	"collection_directory|cd=s" =>\$cd,
	"help|h"		    =>\$help,
);
die $usage unless ($ad and $cd);
die $usage if $help;

mkdir $cd unless -e $cd;
my @paths = map { split /\,/, $_ } @{$ad};

foreach my $dir ( @paths ) {
	chomp $dir,
	print "finding *final_mergeGvcf* in $dir\n";
	`find /Repository/AnalysisData/2014/$dir/ -name "*final_mergeGvcf*">> tmp.list`;
}

print "copying files to $cd\n";
open( my $TMP, '<', 'tmp.list');

while ( my $file = <$TMP> ) {
	chomp $file;
	`cp $file $cd`;
}
close $TMP;
`rm tmp.list`;
print "Finished!\n";
