#!/usr/bin/perl
use warnings;
use strict;
use IO::File;
use Parallel::ForkManager;
use Getopt::Long;
use Data::Dumper;

my $usage = "

Synopsis:
        ./BackGrounder --run reducereads --in_dir /data --out_dir /data/reduced --population CEU --cpu 10
        ./BackGrounder --run full --in_dir /data --out_dir /data/reduced --population ALL --cpu 10

Description:
        Backgrounder is designed to do a couple of things.
        1 - Collect all 1000Genomes ftp bwa exome bams.
	2 - Collect all 1000Genomes ftp paired fastq files.
        2 - Run GATK ReducedReads on selected exomes file to allow quicker use with variant calling.

Required
        --in_dir|d      : Path to directory of input BAM files, for ReduceReads.
        --out_dir|d     : Path to directory to write all files to (1000Genomes and reduced BAMs). 
	--fasta|f       : Path to fasta file, needed for ReduceReads to run.
	--GATK|g        : Path to GATK directory.
        --run|r         : Specify type of run user want to perform.

                        	reducereads - Reduce the reads of a downloaded set of bam files.
                        	full        - Download via ftp and reduce bam file from NCBI.
				fastq       - Download original fastq files from 1000Genomes.

        --population|p  : 1000 Genomes population user would like to download and work with.
                          (http://www.1000genomes.org/about#ProjectSamples).
                          
Options:
        --cpu|c         : Number of CPUs used to split runs across.
                          Does not use cpu info from config file.
                          Default 1.

        --help|h        : Print this usage statement.

\n";

my ($run, $in_dir, $out_dir, @pop, $cpu, $help);
GetOptions(
	"run|r=s" => \$run,
	"in_dir|in=s" => \$in_dir,
	"out_dir|out=s" => \$out_dir,
	"population=s" => \@pop,
	"cpu|c=i"      => \$cpu,	
	"help|h"   => \$help,
);
die $usage if ( ! $run and ! @pop or $help );

# add some defaults.
$cpu     ||= '1';
$in_dir  ||= '.';
$out_dir ||= '.';

# make table of wanted populations
my %command_pop = map { $_ => 1 } @pop;

my $pm = Parallel::ForkManager->new($cpu);


thousand_wget();



sub thousand_wget {
	# ftp information for ncbi
	my $ftp = "ftp://anonymous\@ftp-trace.ncbi.nih.gov/1000genomes/ftp/";
	my $FH  = IO::File->new($ARGV[0], 'r') or die;

	my %thousand_files;
	foreach my $index (<$FH>) {
		chomp $index;
		my @colms = split("\t", $index);

		next unless ( $colms[-1] =~ /exome/ );
		next unless ( $command_pop{$colms[10]} or $command_pop{'ALL'});
		push @{$thousand_files{$colms[10]}}, $colms[0];
	}

	while ( my ($group, $file)  = each %thousand_files ) {
		
		# make dir and move in.
		unless ( -d $group ) { `mkdir $group` }
		chdir $group;

		foreach my $fastq ( @{$file} ) {
			chomp $fastq;

			$pm->start and next;
		
			my @parts = split("\/", $fastq);

			#next unless ($parts[3] =~ /\_/);
			unless (-d $parts[1]) { `mkdir $parts[1]` }

			chdir $parts[1];
			`wget $ftp$fastq 2> wget.report`;
			#`touch $parts[3]`;
			chdir "../";
			$pm->finish;
		}
		# move out.
		chdir "../";
		$pm->wait_all_children;
	}
}

__END__
sub reduceRunner {

	#make bam master file
	foreach my $file (@dirs) {
		`find $file -name \"*bam\" >> bam_file.list`;
	}
	( scalar @dirs => 1 )
		? warn "Bam files found\n"
		: die "Can't find bam files in given dir\n";

	# run RR
	my @bams = `cat bam_file.list` or die "could not read bam_file.list $!\n";
	foreach my $bam (@bams) {
		chomp $bam;

		next if ( $bam =~ /\.reduced\.bam$/ );
		( my $output = $bam ) =~ s/\.bam$/\.reduced\.bam/;
		if ( -e $output and -s $output > 100 ) { next }

		$pm->start and next;
		my $cmd = "java -jar -Xmx60g -XX:ParallelGCThreads=3 -Djava.io.tmpdir=$tmp  $gatk "
		#. "-T ReduceReads -R $fasta -I $bam -o $output &>> ReduceRunner.report";
		. "-T ReduceReads -R /dev/shm/srynearson/human_g1k_v37_decoy.fasta -I $bam -o $output &>> ReduceRunner.report";
		`$cmd`;
		$pm->finish;
	}
	$pm->wait_all_children;
	`rm bam_file.list`

}



sub samIndex {
        opendir(DIR, '.');
        foreach my $bam (readdir(DIR)) {
                chomp $bam;
                next unless ( $bam =~ /\.bam$/);
                $pm->start and next;
                `samtools index $bam`;
                $pm->finish;
        }
        $pm->wait_all_children;
}





