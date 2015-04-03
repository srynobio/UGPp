#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use autodie;
use File::Path qw(make_path);
use Getopt::Long;

my ( $dir, $run );
GetOptions(
    "input_directory|dir=s" => \$dir,
    "run|r"                 => \$run,
);
die "input directory needed\n" unless $dir;
my $review = '1' unless $run;
$dir =~ s/\/$//;

say "Moving to $dir to create directory structure...";
chdir $dir;
make_path(
    'Intermediate_Files', 'Reports',    'VCF', 'VCF_QC',
    'Data/BAM',           'Data/Fastq', 'Data/Trimming',
) if $run;

##----------------------------------------##

say "Collecting BAM files...";
my @bams = `find $dir -name \"*_recal.ba*\"`;

chomp(@bams);
map { `mv $_ $dir/Data/BAM` } @bams     if $run;
map { say "mv $_ $dir/Data/BAM" } @bams if $review;

##----------------------------------------##

say "Collecting cApTUrE files...";
my @capture = `find $dir -name \"cApTUrE*\"`;
chomp(@capture);

map { `mv $_ $dir/VCF` } @capture     if $run;
map { say "mv $_ $dir/VCF" } @capture if $review;

##----------------------------------------##

say "Collecting Report files...";
my @pdf      = `find $dir -name \"*.pdf\"`;
my @metrics  = `find $dir -name \"*metrics\"`;
my @flagstat = `find $dir -name \"*.flagstat\"`;
my @r        = `find $dir -name \"*.R\"`;
my @fastqc   = `find $dir -name \"*fastqc*\"`;
my @stats    = `find $dir -name \"*.stats\"`;

chomp( @pdf, @metrics, @flagstat, @r, @fastqc, @stats );
my @reports = ( @pdf, @metrics, @flagstat, @r, @fastqc, @stats );
map { `mv $_ $dir/Reports` } @reports     if $run;
map { say "mv $_ $dir/Reports" } @reports if $review;

##----------------------------------------##

say "Moving intermediate files...";
my @inters = `find $dir -maxdepth 1 -type f -name \"*\"`;
chomp(@inters);
map { `mv $_ $dir/Intermediate_Files` } @inters     if $run;
map { say "mv $_ $dir/Intermediate_Files" } @inters if $review;

##----------------------------------------##

say "Cleaning up..." if $run;
my @clean = `find $dir -type l`;
map { `rm $_` } @clean if $run;

##----------------------------------------##

say "Done!!";
