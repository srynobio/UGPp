package SamTools;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub samtools_index {
    my $self = shift;
    $self->pull;

    my $config = $self->options;

    my $cmd =
      sprintf( "%s/samtools faidx %s\n", $config->{SamTools},
        $config->{fasta} );
    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

sub idxstats {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $sorted = $self->file_retrieve('bwa_mem');

    my @cmds;
    foreach my $bam ( @{$sorted} ) {
        ( my $idx_file = $bam ) =~ s/\.bam/\.stats/;
        $self->file_store($idx_file);

        my $cmd = sprintf( "%s/samtools idxstats %s > %s",
            $config->{SamTools}, $bam, $idx_file );
        push @cmds, [$cmd];
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub flagstat {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $files  = $self->file_retrieve('bwa_mem');

    my @cmds;
    foreach my $sort ( @{$files} ) {
        ( my $flag_file = $sort ) =~ s/\.bam/.flagstat/;

        my $cmd = sprintf( "%s/samtools flagstat %s > %s",
            $config->{SamTools}, $sort, $flag_file );
        push @cmds, [$cmd];
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

1;
