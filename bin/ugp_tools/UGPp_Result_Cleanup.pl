#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use autodie;
use File::Path qw(make_path);
use Getopt::Long;

my $usage = "

Synopsis:

UGP_Result_Cleanup.pl -dir <path> --run

Description:

Will take UGPp output directory and organize files into proper collections.


Required options:

--input_directory, -dir Directory to clean up.

Additional options:

--run, -r   Run the clean up steps.  [DEFAULT: view data movement].

\n";

my ( $dir, $run );
GetOptions(
		"input_directory|dir=s" => \$dir,
		"run|r"                 => \$run,
	  );
die $usage unless $dir;
my $review = '1' unless $run;
$dir =~ s/\/$//;

say "Moving to $dir to create directory structure...";
chdir $dir;
make_path(
		'Intermediate_Files', 'Reports',
		'Reports/fastqc',     'Reports/stats',
		'Reports/flagstat',   'VCF',
		'VCF/GVCFs',          'VCF/Complete',
		'QC',                 'Data/PolishedBAMs',
		'Data/Primary_Data', 'VCF/WHAM'
	 ) if $run;

##----------------------------------------##

say "Collecting BAM files...";
my @bams = `find $dir -name \"*_recal.ba*\"`;
chomp(@bams);

map { `mv $_ $dir/Data/PolishedBAMs` } @bams     if $run;
map { say "mv $_ $dir/Data/PolishedBAMs" } @bams if $review;

##----------------------------------------##

say "Collecting final variant files...";
my @UGPp = `find $dir -name \"UGPp*\"`;
chomp( @UGPp );

map { `mv $_ $dir/VCF/Complete` } @UGPp     if $run;
map { say "mv $_ $dir/VCF/Complete" } @UGPp if $review;

##----------------------------------------##

say "Collecting gCat (gvcfs) files...";
my @gcat = `find $dir -name \"*gCat*\"`;
chomp(@gcat);

map { `mv $_ $dir/VCF/GVCFs` } @gcat     if $run;
map { say "mv $_ $dir/VCF/GVCFs" } @gcat if $review;

##----------------------------------------##

say "Collecting Report files...";
my @pdf      = `find $dir -name \"*.pdf\"`;
my @flagstat = `find $dir -name \"*.flagstat\"`;
my @r        = `find $dir -name \"*.R\"`;
my @fastqc   = `find $dir -type f -name \"*fastqc*\"`;
my @stats    = `find $dir -name \"*.stats\"`;
chomp( @pdf, @flagstat, @r, @fastqc, @stats );

# move fastqc
map { `mv $_ $dir/Reports/fastqc` } @fastqc     if $run;
map { say "mv $_ $dir/Reports/fastqc" } @fastqc if $review;

# move stats files.
map { `mv $_ $dir/Reports/stats` } @stats     if $run;
map { say "mv $_ $dir/Reports/stats" } @stats if $review;

# move flagstat files.
map { `mv $_ $dir/Reports/flagstat` } @flagstat     if $run;
map { say "mv $_ $dir/Reports/flagstat" } @flagstat if $review;

# keep the rest higher level.
my @reports = ( @pdf, @r );
map { `mv $_ $dir/Reports` } @reports     if $run;
map { say "mv $_ $dir/Reports" } @reports if $review;

##----------------------------------------##

say "Collecting Fastq files(*gz)...";
my @fq = `find $dir -maxdepth 1 -name "*.gz"`;
chomp(@fq);

map { say "mv $_ $dir/Data/Primary_Data" } @fq if $review;
map { `mv $_ $dir/Data/Primary_Data` } @fq     if $run;

##----------------------------------------##

say "Collecting WHAM files...";
my @wham = `find $dir -maxdepth 1 -name "*WHAM*"`;
chomp(@wham);

map { say "mv $_ $dir/VCF/WHAM" } @wham if $review;
map { `mv $_ $dir/VCF/WHAM` } @wham if $run;

##----------------------------------------##

say "Collecting intermediate files...";
my @inters = `find $dir -maxdepth 1 -type f -name \"*\"`;
chomp(@inters);

map { `mv $_ $dir/Intermediate_Files` } @inters     if $run;
map { say "mv $_ $dir/Intermediate_Files" } @inters if $review;

##----------------------------------------##

say "Cleaning up...";
my @clean    = `find $dir -type l`;
my @list     = `find $dir -name \"*list\"`;
my @interval = `find $dir -name \"*intervals\"`;
chomp( @clean, @list, @interval );

my @tidy = ( @clean, @list, @interval );

map { `rm $_` } @tidy     if $run;
map { say "rm $_" } @tidy if $review;

##----------------------------------------##

say "Done!!";
say "Please review then add --run to command line to complete" if $review;
say "Please review Intermediate_Files directory, then remove to save space";
