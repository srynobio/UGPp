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

sub stats {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $sorted = $self->file_retrieve('bwa_mem');

    my @cmds;
    foreach my $bam ( @{$sorted} ) {
        ( my $stat_file = $bam ) =~ s/\.bam/\.stats/;
        $self->file_store($stat_file);

        my $cmd = sprintf( "%s/samtools stats %s > %s",
            $config->{SamTools}, $bam, $stat_file );
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
