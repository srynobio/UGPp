#!/usr/bin/perl 
use warnings;
use strict;
use IO::File;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../../perl_libs/";
use Parallel::ForkManager;

my $usage = "

	USAGE:
		Thousand_genomes_exome_downloader.pl --cpu 5 --population CEU --output /CEU_fastq -sequnece_index 20130502.analysis.sequence.index
	 	
	DESCRIPTION:
		Script which will download all exome files from 10000Genome ftp site.

	REQUIRED OPTIONS:
		--cpu|c             : Total number of processers to work across.
		--population|p      : Population to download
		--sequence_index|si : NCBI sequence index file used to collect ftp paths.

	OPTIONS:
		--output|o          : Directory to place fastq reads into.  Default is population.

\n\n";

my ($cpu, $pop, $out, $si);
GetOptions(
	"cpu=i"          => \$cpu,
	"population|p=s" => \$pop,
	"output|o=s"     => \$out,
	"seq_index|si=s" => \$si,
);
die $usage unless ($pop and $si);

my $CPU = $cpu || '1';
my $OUT = $out || $pop;
my $pm  = Parallel::ForkManager->new($CPU);
mkdir ($OUT);

my $ftps = ftp_path();
foreach my $down ( @{$ftps} ) {
	chomp $down;
	my $ncbi = "ftp://ftp-trace.ncbi.nih.gov/1000genomes/ftp/";

	$pm->start and next;

	chdir($OUT);
	my $cmd = "wget $ncbi$down";
	`$cmd`;
	chdir("../");

	$pm->finish;
}
$pm->wait_all_children;

##-------------------------------------------------------------------------------------

sub ftp_path {
	my $FH = IO::File->new($si, 'r') or die "Can't open sequence.index file\n";

	my @ftp_paths;
	foreach my $index (<$FH>) {
		chomp $index;
		next if $index =~ /^FASTQ_FILE/;

		# only want exome data
		my @colm = split "\t", $index;
		next unless $colm[25] eq 'exome';
		next unless $colm[10] eq $pop;

		# only want pairs
		my @path = split "\/", $colm[0];
		next unless ($path[3] =~ /\_/);
		
		push @ftp_paths, $colm[0];
	}
	$FH->close;
	my @sort_ftps = sort @ftp_paths;
	return (\@sort_ftps);
}

##-------------------------------------------------------------------------------------
