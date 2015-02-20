package BWA;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub bwa_index {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my $cmd = sprintf( "%s/bwa index %s %s\n",
        $opts->{BWA}, $tape->dash, $opts->{fasta} );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub bwa_mem {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my @z_list;
    while ( my $file = $tape->next ) {
        chomp $file;
        next unless ( $file =~ /(gz|bz2)/ );
        push @z_list, $file;
    }

    # must have matching pairs.
    if ( scalar @z_list % 2 ) {
        $tape->ERROR("FQ files must be matching pairs");
    }

    my @cmds;
    my $id   = '1';
    my $pair = '1';
    while (@z_list) {
        my $file1 = $tape->file_frags( shift @z_list );
        my $file2 = $tape->file_frags( shift @z_list );

        # collect tag and uniquify the files.
        my $tags     = $file1->{parts}[0];
        my $bam      = $file1->{parts}[0] . "_" . $pair++ . ".bam";
        my $path_bam = $opts->{output} . $bam;

        # store the output files.
        $tape->file_store($path_bam);

        my $uniq_id = $file1->{parts}[0] . "_" . $id;
        my $r_group =
          '\'@RG' . "\\tID:$uniq_id\\tSM:$tags\\tPL:ILLUMINA\\tLB:$tags\'";

        my $cmd = sprintf(
            "%s/bwa mem %s -R %s %s %s %s | %s/samblaster | %s/samtools view -bSho %s -\n",
            $opts->{BWA}, $tape->dash, $r_group, $opts->{fasta},
            $file1->{full}, $file2->{full},
            $tape->software->{Samblaster}, $tape->software->{SamTools}, $path_bam );
        push @cmds, $cmd;
        $id++;
    }
    $tape->bundle( \@cmds );
}

=cut
sub bwa_mem {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my @z_list;
    while ( my $file = $tape->next ) {
        chomp $file;
        next unless ( $file =~ /(gz|bz2)/ );
        push @z_list, $file;
    }

    # must have matching pairs.
    if ( scalar @z_list % 2 ) {
        $tape->ERROR("FQ files must be matching pairs");
    }

    my @cmds;
    my $id   = '1';
    my $pair = '1';
    while (@z_list) {
        my $file1 = $tape->file_frags( shift @z_list );
        my $file2 = $tape->file_frags( shift @z_list );

        # collect tag and uniquify the files.
        my $tags     = $file1->{parts}[0];
        my $bam      = $file1->{parts}[0] . "_" . $pair++ . ".bam";
        my $path_bam = $opts->{output} . $bam;

        # store the output files.
        $tape->file_store($path_bam);

        my $uniq_id = $file1->{parts}[0] . "_" . $id;
        my $r_group =
          '\'@RG' . "\\tID:$uniq_id\\tSM:$tags\\tPL:ILLUMINA\\tLB:$tags\'";

        my $cmd = sprintf(
            "%s/bwa mem %s -R %s %s %s %s | %s/samtools view -bSho %s -\n",
            $opts->{BWA}, $tape->dash, $r_group, $opts->{fasta},
            $file1->{full}, $file2->{full},
            $tape->software->{SamTools}, $path_bam );
        push @cmds, $cmd;
        $id++;
    }
    $tape->bundle( \@cmds );
}
=cut

##-----------------------------------------------------------
1;
