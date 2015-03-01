package SamTools;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub samtools_index {
    my $tape = shift;
    $tape->pull;

    my $config = $tape->options;

    my $cmd =
      sprintf( "%s/samtools faidx %s\n", $config->{SamTools}, $config->{fasta}, );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub idxstats {
    my $tape = shift;
    $tape->pull;

    my $config   = $tape->options;
    my $sorted = $tape->file_retrieve('bwa_mem');

    my @cmds;
    foreach my $bam ( @{$sorted} ) {
        ( my $idx_file = $bam ) =~ s/\.bam/\.stats/;
        $tape->file_store($idx_file);

        my $cmd = sprintf( "%s/samtools idxstats %s > %s\n",
            $config->{SamTools}, $bam, $idx_file );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds, 'off' );
}

##-----------------------------------------------------------

sub flagstat {
    my $tape = shift;
    $tape->pull;

    my $config  = $tape->options;
    my $files = $tape->file_retrieve('bwa_mem');

    my @cmds;
    foreach my $sort ( @{$files} ) {
        ( my $flag_file = $sort ) =~ s/\.bam/.flagstat/;

        my $cmd = sprintf( "%s/samtools flagstat %s > %s\n",
            $config->{SamTools}, $sort, $flag_file );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds );
}

##-----------------------------------------------------------
1;
