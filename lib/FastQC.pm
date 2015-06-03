package FastQC;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub fastqc_run {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('fastqc_run');
    my $gz     = $self->file_retrieve;

    my @cmds;
    foreach my $file ( @{$gz} ) {
        chomp $file;
        next unless ( $file =~ /gz$/ );

        my $cmd = sprintf( "%s/fastqc --threads %s -o %s -f fastq %s",
            $config->{FastQC}, $opts->{threads}, $config->{output}, $file );
        push @cmds, [ $cmd, $file ];
    }
    $self->bundle( \@cmds );
    return;
}

##-----------------------------------------------------------

1;
