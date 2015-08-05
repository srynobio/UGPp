#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use autodie;
use File::Find;
use Getopt::Long;
use IO::Dir;
use Cwd;

my $usage = "

Synopsis:

    Review the tranfers:
    ./Transfer_Project.pl -id <individuals.txt> -bam_dir <BAM dir> -output_dir <interest_bams> -source WashU

    Only see what's been found:
    ./Transfer_Project.pl -id <individuals.txt> -bam_dir <BAM dir> -output_dir <interest_bams> -found

    Complete the transfer:
    ./Transfer_Project.pl -id <individuals.txt> -bam_dir <BAM dir> -output_dir <interest_bams> -run
    
    **samtools must be in your PATH. **
                    
Description:

    Script to find and move data out of CHPC tranfer space into desired location.

    ID lists to use:
    WashU:     Individual ID list 
    Nantomics: Barcode list.

Required options:

    -id         Individual id or barcode list
    -bam_dir    Directory where transfer BAMs are located.
    -source     Source of data.
                Currently only works for:
                    WashU
                    Nantomics

Additional options:

    -found      Just print list of found individuals
    -output_dir Directory to transfer BAMs into.  [Default: current/not moved]
    -run        Compete the move.

\n";

my %opts;
GetOptions( \%opts, "id=s", "bam_dir=s", "output_dir=s", "run", "found", "source=s");

# Required and data checks.
unless ( -d $opts{output_dir} ) { 
    say "output_dir $opts{output_dir} must be a valid directory.";
    die $usage;
}
unless ( $opts{id} and $opts{bam_dir} and $opts{source} ) {
    say "Required option not given";
    die $usage;
}
unless ($opts{source} =~ /(WashU|Nantomics)/ ) {
    say "Source: $opts{source} does not match WashU/Nantomics";
    die;
}

# check for samtools.
samcheck();

# defaults
$opts{bam_dir} //= '.';

# I/O
open( my $ID, "<$opts{id}" );
open( FOUND,  '>found.txt' );
my $BAM = IO::Dir->new( $opts{bam_dir} );

# Make lookup of individuls
my $indivs;
foreach my $peps (<$ID>) {
    chomp $peps;
    $indivs->{$peps} = '1';
}

my @matches;
@matches = WashU() if $opts{source} eq 'WashU';
@matches = Nant() if $opts{source} eq 'Nantomics';

# stop here if just reviewing what was found.
if ( $opts{found} ) {
    say "review found.txt file";
    die;
}

# Move or print out.
foreach my $find (@matches) {
    if ( $opts{run} ) {
        `mv $opts{bam_dir}$find $opts{output_dir}`;
    }
    else {
        say "review: mv $opts{bam_dir}$find $opts{output_dir}";
    }
}

close FOUND;

##--------------------------------------##

sub WashU {

    say "Selected WashU source, will use \@RG from BAM file";

    # Get RG and look for match.
    my @matches;
    foreach my $bam ( $BAM->read ) {
        chomp $bam;
        next if ( $bam eq '.' or $bam eq '..' );
        next unless ( $bam =~ /bam$/ );
        my $rg = `samtools view -H $opts{bam_dir}$bam|grep 'RG'`;
        chomp $rg;
        die "No \@RG found\n" unless $rg;

        my @info = split /\s/, $rg;
        my @lb   = split /-/,  $info[4];
        my $full_id = $lb[1] . '-' . $lb[2];
        if ( $indivs->{ $lb[1] } or $indivs->{$full_id} ) {
            print FOUND $lb[1], "\n";
            push @matches, $bam;
        }
    }
    return @matches;
}

##--------------------------------------##

sub Nant {

    say "Selected Nantomics as source. Search based on filename";

    my @matches;
    foreach my $bam ( $BAM->read ) {
        chomp $bam;
         next if ( $bam eq '.' or $bam eq '..' );
        next unless ( $bam =~ /bam$/ );
 
        my @nant = split/--/, $bam;
        if ( $indivs->{$nant[0]} ) {
            print FOUND $nant[0], "\n";
            push @matches, $bam;
        }
    }
    return @matches;
}

##--------------------------------------##

sub samcheck {
    my $samcall = `samtools 2>&1`;
    die "can not call samtools from commandline\n" unless $samcall;
}

##--------------------------------------##

