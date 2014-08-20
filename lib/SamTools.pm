package SamTools;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub SamTools_index {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my $cmd = sprintf( "%s faidx %s\n", $opts->{SamTools}, $opts->{fasta}, );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub SamTools_idxstats {
    my $tape = shift;
    $tape->pull;

    my $opts   = $tape->options;
    my $sorted = $tape->file_retrieve('Picard_SortSam');

    my @cmds;
    foreach my $bam ( @{$sorted} ) {
        ( my $idx_file = $bam ) =~ s/\.bam/\.stats/;
        $tape->file_store($idx_file);

        my $cmd = sprintf( "%s idxstats %s > %s\n",
            $opts->{SamTools}, $bam, $idx_file );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds, 'off' );
}

##-----------------------------------------------------------

sub SamTools_flagstat {
    my $tape = shift;
    $tape->pull;

    my $opts  = $tape->options;
    my $files = $tape->file_retrieve("Picard_SortSam");

    my @cmds;
    foreach my $sort ( @{$files} ) {
        ( my $flag_file = $sort ) =~ s/\.bam/.flagstat/;

        my $cmd = sprintf( "%s flagstat %s > %s\n",
            $opts->{SamTools}, $sort, $flag_file );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds );
}

##-----------------------------------------------------------
1;
