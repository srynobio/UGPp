package WHAM;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub wham_graphing {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('wham_graphing');
    my $files  = $self->file_retrieve('sambamba_bam_merge');

    my @cmds;
    foreach my $merged ( @{$files} ) {
        chomp $merged;

        my $file   = $self->file_frags($merged);
        my $output = "$file->{parts}[0]" . "_WHAM.vcf";
        $self->file_store($output);

        my $threads;
        ( $opts->{x} ) ? ( $threads = $opts->{x} ) : ( $threads = 1 );

        my $cmd = sprintf( "%s/WHAM-GRAPHENING -a %s -k -x %s -f %s > %s",
            $config->{WHAM}, $config->{fasta}, $threads, $merged, $output );
        push @cmds, [$cmd];
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub wham_merge_indiv {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('wham_merge_indiv');
    my $files  = $self->file_retrieve('wham_graphing');

    my $all_indiv = join( ',', @{$files} );
    my $output = $config->{ugp_id} . "_WHAM.vcf";

    my $cmd =
      sprintf( "%s/mergeIndv -f %s > %s", $config->{WHAM}, $all_indiv,
        $output );
    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

1;

