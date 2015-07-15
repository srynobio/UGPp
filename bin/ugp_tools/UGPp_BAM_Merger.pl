#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use autodie;
use Parallel::ForkManager;
use Getopt::Long;
use File::Find;

my $usage = "

Synopsis:

    # Review run
    ./UGPp-BAM-Merger.pl -sambamba <sambamba path> -sambamba_threads <int> -cpu <int> -bam_directory <BAM file directory> 
    ./UGPp-BAM-Merger.pl -sb <sambamba path> -st <int> -c <int> -bd <BAM file directory> 

    # Run script on BAM files
    ./UGPp-BAM-Merger.pl -sambamba <sambamba path> -sambamba_threads <int> -cpu <int> -bam_directory <BAM file directory> -remove_old -run
    ./UGPp-BAM-Merger.pl -sb <sambamba path> -st <int> -c <int> -bd <BAM file directory> -rm -run

Description:

    Will merge all BAM file split by chromosome after UGPp run.
    Requires the UGPp format <individual>_sorted_Dedup_merged_realign_chr#_recal.bam
    Or UGPp format <individual>_sorted_Dedup_realign_chr#_recal.bam

    Optionally will allow removal of all split BAMs if desired with -remove_old flag.

Required options:

    -sambamba, -sb          Path to executable sambamba file.
    -bam_directory, -bd     Directory of split BAM files.

Additional options:

    -sambamba_threads, -st  Number of threads for each sambamba_merge job. [default 1]
    -cpu, -c                Number of cpu to split jobs across. i.e. workers. [default 1]
    -remove_old, -rm        Remove old split BAM files upon completion.
    -cluster                Command will build slurm script, BUT not submit them.
    -run                    After review add this command to execute jobs.
\n";

my ( $bamba, $cpu, $bams, $bamba_threads, $rm, $cluster, $run );
GetOptions(
    "sambamba|sb=s"         => \$bamba,
    "sambamba_threads|st=i" => \$bamba_threads,
    "cpu|c=i"               => \$cpu,
    "bam_directory|bd=s"    => \$bams,
    "remove_old|rm"         => \$rm,
    "cluster"               => \$cluster,
    "run"                   => \$run,
);

# checks and defaults and end of path.
die "sambamba path and bam_directory needed.\n$usage" unless ( $bamba and $bams);
$cpu           //= '1';
$bamba_threads //= '1';
unless ( $bams =~ /\/$/ ) {
    $bams =~ s|$|\/|g;
}
my $pm = Parallel::ForkManager->new($cpu);

# main variables.
my %bams;
my @command_list;
my @removables;

# check that sambamba is executable
bamba_check();

# locate the bams.
find(
    sub {
        no warnings;
        next unless ( $_ =~ /bam$/ );
        next unless ( $_ =~ /chr/ );

        $_ =~ s/chr(.*)/$1/;
        my @parts = split /_/, $_;

        if ( $parts[4] eq 'merged' ) {
            push @{ $bams{ $parts[0] }{ $parts[6] } }, $_;
        }
        else {
            push @{ $bams{ $parts[0] }{ $parts[5] } }, $_;
        }
    },
    $bams
);

# step check.
unless (keys %bams) {
    die "[ERROR] could not find BAM file in: $bams\n";
}

while ( my ( $k, $v ) = each %bams ) {
    my @chr = keys %{$v};

    # put bams in order.
    my @chrOrder;
    for ( 1 .. 22, 'X', 'Y', 'MT' ) {
        my $file = $v->{$_}[0];
        $file =~ s/realign_$_\_/realign_chr$_\_/;

        # push file with path.
        push @chrOrder, "$bams$file";
    }

    # use the first file to make output.
    ( my $outfile = $chrOrder[0] ) =~ s/_chr1_/_/g;

    # the main command creator.
    my $cmd = sprintf( "%s merge -t $bamba_threads %s %s",
        $bamba, $outfile, join( ' ', @chrOrder ) );
    push @command_list, $cmd;

    # make stack of removables.
    foreach my $chr_bam (@chrOrder) {
        push @removables, $chr_bam;
    }
}

# run on cluster or standared server.
my $id;
if ( $cluster ) {
    foreach my $cmd (@command_list) {

        my $clu_cmd = cluster_config($cmd);

        if ($run) {
            say "[WARN] Building sbatch jobs";
            my $output = 'sambamba_merge_' . $id++ . '.sbatch';
            open(my $OUT, ">$output");
            print $OUT $clu_cmd;
            close $OUT;
        }
        else {
            say "[WARN] review of sbatch cmd:\n";
            say $clu_cmd;
        }
    }
}
else {
    foreach my $cmd (@command_list) {
        $pm->start and next;
        if ($run) {
            system($cmd);
        }
        else {
            say "[WARN] Review of cmd: $cmd";
        }
        $pm->finish;
    }
    $pm->wait_all_children;
}

# removing old bams.
foreach my $junk (@removables) {
    if ( $cluster ) {
        say "[WARN] cluster option turns off BAM removal";
        say "[WARN] But file BAM-removables.txt created for later removal";
        my $txt = 'BAM-removables_' . int(rand(1000)) . '.txt';
        open(my $JUNK, ">$txt");
        map { say $JUNK $_ } @removables;
        die;
    }
    if ($rm and $run) {
        system("rm $junk");
    }
    elsif ($rm) {
        say "[WARN] a removables file: $junk";
    }
}

# Done!
say "[WARN] if commands look correct please re-run will the flag -run" unless $run;

## ------------------------------- ##

sub bamba_check {
    my $check = `$bamba 2>&1`;

    unless ( $check) {
        die "[ERROR] sambamba file: $bamba is unfound or not executable.\n";
    }
}

## ------------------------------- ##

sub cluster_config {
    my $cmd = shift;

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t 72:00:00
#SBATCH -N 1
#SBATCH -A ucgd-kp
#SBATCH -p ucgd-kp

# clean up before start
find /scratch/local/ -exec rm -rf {} \\; 
find /tmp -exec rm -rf {} \;

$cmd

find /scratch/local/ -exec rm -rf {} \\; 
find /tmp -exec rm -rf {} \;
EOM
    return $sbatch;

}

## ------------------------------- ##


