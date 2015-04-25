package Sambamba;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub sambamba_merge {
    my $self = shift;
    $self->pull;

    my $config    = $self->options;
    my $opts      = $self->tool_options('sambamba_merge');
    my $sam_files = $self->file_retrieve('bwa_mem');

    # collect one or more files based on id of the set.
    my %id_collect;
    my %merged_version;
    foreach my $sam ( @{$sam_files} ) {
        my $file = $self->file_frags($sam);

        # change name and stack to store later.
        ( my $merged = $file->{full} ) =~ s/\.bam/_merged.bam/;

        # collect input and merge statement, also store merge file
        push @{ $id_collect{ $file->{parts}[0] } }, $sam;

        $merged_version{ $file->{parts}[0] } = $merged;
    }

    # check to see if we should run merge
    my $id_total   = scalar keys %id_collect;
    my @ids_files  = values %id_collect;
    my $file_total = scalar map { @$_ } @ids_files;

    # return if does not need to run
    if ( $id_total eq $file_total ) { return }

    # add the merged file names to store if working with lanes
    map { $self->file_store($_) } values %merged_version;

    my @cmds;
    foreach my $id ( keys %id_collect ) {
        my $input = join( " ", @{ $id_collect{$id} } );
        my $output = $merged_version{$id};

        # large joint calls from different timepoints
        # and different number of lanes, etc
        if ( scalar @{ $id_collect{$id} } < 2 and $self->execute) {
            system("ln -s $input $output");
            system("ln -s $input\.bai $output\.bai");
            next;
        }

        my $cmd = sprintf( "%s/sambamba merge --nthreads %s %s %s",
            $config->{Sambamba}, $opts->{nthreads}, $output, $input );
        push @cmds, [ $cmd, @{ $id_collect{$id} } ];
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

1;
