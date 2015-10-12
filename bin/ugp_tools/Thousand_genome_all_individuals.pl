#!/usr/bin/env perl
# Thousand_genome_all_individuals.pl
use strict;
use warnings;
use feature 'say';
use autodie;
use Net::FTP;
use Parallel::ForkManager;
use File::Copy;
use Getopt::Long;

my $usage = << "EOU";

Synopsis:
        ./Thousand_genome_all_individuals.pl --run

Description:
        Script to find all the sequence read files found here:
        ftp://ftp-trace.ncbi.nih.gov/1000genomes/ftp/phase3/data/<individual>/sequence_read/*
        And download them to the current directory.

        Directories will be created per individual and corresponding file will be correctly
        placed.

        Example:
        ├── <individual>
        │   ├── <fastq_file_1.fastq.gz
        │   ├── <fastq_file_2.fastq.gz
        │   ├── ...

Additional options:
        --run, -r :     Add when you want to start the download process.
        --cpu, -c :     How many concurrent downloads to run at one time. <INT> [default 1]
        --indv, -i :    Number of individuals to download data for per run. <INT> [default 100]

EOU

my %c_opts = ();
GetOptions(
    \%c_opts,
    "run|r",
    "cpu|c=i",
    "indv|i=i"
);
unless ($c_opts{run}) {
        die $usage;
}

## make lookup of collected individuals.
my %prior;
if (-e 'Collected_individuals.txt') {
        open(my $IN, '<', 'Collected_individuals.txt');
        for my $indv (<$IN>) {
                chomp $indv;
                $prior{$indv}++;
        }
}
else {
        say "[WARN]: Collected_individuals.txt not found.";
        say "[WARN]: Downloading from the beginning.";
}

## default for individuals.
$c_opts{indv} //= 100;

$c_opts{cpu} //= 1;
my $pm = Parallel::ForkManager->new($c_opts{cpu});

my $ftp = Net::FTP->new( "ftp-trace.ncbi.nih.gov", )
or die "Can not connect to ftp site\n";

$ftp->login or die "Can not login to ftp site\n";

## top directory to cd into.
my $top_level = '1000genomes/ftp/phase3/data/';
$ftp->cwd($top_level);

## get list of individuals;
my @individuals = get_dirs_of($top_level);

my %cmd_stack;
my @collected_individuals;
my $collected = 0;
for my $indiv (@individuals) {
        chomp $indiv;

        next if ($prior{$indiv});
        if ($collected == $c_opts{indv}) {
                open(my $CLT, '>>', 'Collected_individuals.txt');
                map { say $CLT $_ } @collected_individuals;
                last;
        }

        my $ftpcmd =
                "wget ftp://ftp-trace.ncbi.nih.gov/1000genomes/" .
                "ftp/phase3/data/$indiv/sequence_read/* .";
        push @{$cmd_stack{$indiv}}, $ftpcmd;
        push @collected_individuals, $indiv;
        $collected++;
}

for my $cmd ( keys %cmd_stack) {
        chomp $cmd;

        $pm->start and next;
        mkdir $cmd unless ( -e $cmd );
        chdir $cmd;

        my $wget = $cmd_stack{$cmd}[0];
        eval { `$wget` };
        if ( $@ ) {
                say "WARN: $cmd & $wget had issues";
                next;
        }
        $pm->finish;
}
$pm->wait_all_children;

## ---------------------------------- ##

sub get_dirs_of {
        my $directory = shift;
        $ftp->cwd($directory);
        my @ls = $ftp->ls;
        return @ls;
}

## ---------------------------------- ##
