package Picard;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub CreateSequenceDictionary {
    my $self = shift;
    $self->pull;

    my $config = $self->options;

    my $fa_file = $self->file_frags( $config->{fasta} );
    ( my $output = $fa_file->{full} ) =~ s/(.*)\.(fasta|fa)/$1.dict/;

    my $cmd = sprintf( "java -jar %s CreateSequenceDictionary.jar R=%s O=%s\n",
        $config->{Picard}, $config->{fasta}, $output );
    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

sub CollectMultipleMetrics {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('CollectMultipleMetrics');
    my $recal  = $self->file_retrieve('PrintReads');

    my @cmds;
    foreach my $bam ( @{$recal} ) {
        ( my $w_file = $bam ) =~ s/\.bam$/\.metrics/;
        $self->file_store($w_file);

        my $cmd = sprintf(
            "java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
              . "%s CollectMultipleMetrics INPUT=%s VALIDATION_STRINGENCY=%s PROGRAM=%s REFERENCE_SEQUENCE=%s "
              . "OUTPUT=%s\n",
            $opts->{xmx},     $self->{NCORES},
            $config->{tmp},   $config->{Picard},
            $bam,             $opts->{VALIDATION_STRINGENCY},
            $opts->{PROGRAM}, $config->{fasta},
            $w_file
        );
        push @cmds, $cmd;
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------
1;
