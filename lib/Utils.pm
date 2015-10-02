package Utils;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub bam_cleanup {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('bam_cleanup');
    my $files  = $self->file_retrieve('sambamba_bam_merge');

    my @cmds;
    for my $bam ( @{$files} ) {
        chomp $bam;

        my $cmd = sprintf( "rm %s", $bam );
        push @cmds, [$cmd];
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

1;

