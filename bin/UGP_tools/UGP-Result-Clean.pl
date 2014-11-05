#!/usr/bin/perl
use warnings;
use strict;
use IO::Dir;
use Getopt::Long;
use Carp;

my $usage = "

Synopsis:

	UGP-Result-Clean.pl --path /path/to/UGP_Pipeline_Results --lab Guthery
	UGP-Result-Clean.pl --p /path/to/UGP_Pipeline_Results -l Guthery

Description:

	Will take UGP_Pipeline_Results and organize/clean directory, inaddition to emailing researcher.

Required options:

	-p, --path:	Path to UGP_Pipeline_Results directory.
	-l, --lab:	Name of researcher to email completion notification to.
			Current:
				Camp, Albright, Coon, Deininger
				Feng, Guthery, Hunt, Kumanovics
				Manuck, Mason, Neklason, Scholand
				Tavtigian, Tristani, Voelkerding

Additional options:

	--help|h     : Prints this usage statement.
				
\n";

my ( $path, $lab, $help );
GetOptions(
    "path|p=s" => \$path,
    "lab|l=s"  => \$lab,
    "help|h"   => \$help,
);
unless ( $path and $lab ) { croak $usage }
croak $usage if $help;

my $DIR = IO::Dir->new($path)
  or croak "Path to UGP_Pipeline_Results path needed\n";

# move and make new dirs.
chdir $path;
system(
    "mkdir Variant_Calling Analysis_VCFs Alignments FastQC Alignment_QC Reports"
);

foreach my $file ( $DIR->read ) {
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
    if ( $file =~ /.*fastqc.*/ ) {
        system("mv $file FastQC");
        next;
    }
    if ( $file =~ /(^UGP.*|^chr.*)/ ) {
        system("mv $file Variant_Calling");
        next;
    }
    else {
        system("mv $file Alignment_QC");
        next;
    }
}

# only want polished bams
my @bams = `find $path -name "*.ba*"`;
foreach my $bam (@bams) {
    chomp $bam;
    next if ( $bam =~ /_sorted_Dedup_realign_recal.ba*/ );)
    `rm $bam`;
}

# rm interval files
my @list = `find $path -name "*.list*"`;
map { `rm $_` } @list;

# email lab when done.
my %emails = (
    Camp        => 'nicola.camp@hci.utah.edu',
    Albright    => 'lisa.albright@utah.edu',
    Coon        => 'hilary.coon@utah.edu',
    Deininger   => 'michael.deininger@hci.utah.edu',
    Feng        => 'bingjian.feng@hsc.utah.edu',
    Guthery     => 'stephen.guthery@hsc.utah.edu',
    Hunt        => 'steve.hunt@utah.edu',
    Kumanovics  => 'attila.kumanovics@path.utah.edu',
    Moore       => 'barry.utah@gmail.com',
    Rynearson   => 'shawn.rynearson@gmail.com',
    Manuck      => 'tracy.manuck@hsc.utah.edu',
    Mason       => 'clint.mason@hci.utah.edu',
    Neklason    => 'deb.neklason@hci.utah.edu',
    Scholand    => 'scholand@genetics.utah.edu',
    Tavtigian   => 'sean.tavtigian@hci.utah.edu',
    Tristani    => 'mfirouzi@cvrti.utah.edu',
    Voelkerding => 'voelkek@aruplab.com',
);

system(
"echo \"UGP: $path Analysis is complete and ready.\" | mailx -s \"Message from UGP-Gnomex\" $emails{$lab} $emails{Moore} $emails{Rynearson}"
);

