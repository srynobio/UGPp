package fastqc;
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

    my $config = $self->class_config;
    my $opts   = $self->tool_options('fastqc_run');
    my $gz     = $self->file_retrieve;

    my @cmds;
    foreach my $file ( @{$gz} ) {
        chomp $file;
        next unless ( $file =~ /(fastq$|gz$|fq$)/ );
        $self->file_store($file);

        my $cmd = sprintf( "%s/fastqc --threads %s -o %s -f fastq %s",
            $config->{fastqc}, $opts->{threads}, $config->{output}, $file );
        push @cmds, $cmd;
    }
    $self->bundle( \@cmds );
    return;
}

##-----------------------------------------------------------

1;
