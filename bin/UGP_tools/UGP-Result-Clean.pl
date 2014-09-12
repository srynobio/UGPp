#!/usr/bin/perl
use warnings;
use strict;
use IO::Dir;
use Carp;

my $DIR = IO::Dir->new($ARGV[0]) or croak "Path to UGP_Pipeline_Results path needed\n";

# move and make new dirs.
chdir $ARGV[0];
system("mkdir Variant_Calling Analysis_VCFs Alignments FastQC Alignment_QC Reports");

foreach my $file ($DIR->read) {
	chomp $file;

	next unless ( -f $file );

	if ( $file =~ /(.*_metrics|.*.txt$|.*.pdf$)/ ) {
		system("mv $file Reports");
		next;
	}
	if ( $file =~ /.*Backgrounds.vc.*/ ) {
		system("mv $file Analysis_VCFs");
		next;
	}
	if ( $file =~ /(.*\.bam|.*\.bai)/ ) {
		system("mv $file Alignments");
		next;
	}
	if ( $file =~ /.*fastqc$/ ) {
		system("mv $file FastQC");
		next;
	}
	if ($file =~ /(^UGP.*|^chr.*)/ ) {
		system("mv $file Variant_Calling");
		next;
	}
	else {
		system("mv $file Alignment_QC");
		next;
	}
}

# only want polished bams
my @bams = `find $ARGV[0] -name "*.ba*"`;
foreach my $bam (@bams) {
	chomp $bam;
	next if ( $bam =~ /sorted_Dedup_realign_recal/ );
	`rm $bam`;
}

# rm interval files
my @list = `find $ARGV[0] -name "*.list*"`;
map { `rm $_` } @list;

system("echo \"UGP: $ARGV[0] Analysis is complete and ready.\" | mailx -s \"Message from Gnomex\" barry.utah\@gmail.com shawn.rynearson\@gmail.com");
