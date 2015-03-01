package Picard;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub CreateSequenceDictionary {
    my $tape = shift;
    $tape->pull;

    my $config = $tape->options;

    my $fa_file = $tape->file_frags( $config->{fasta} );
    ( my $output = $fa_file->{full} ) =~ s/(.*)\.(fasta|fa)/$1.dict/;

    my $cmd = sprintf( "java -jar %s CreateSequenceDictionary.jar R=%s O=%s\n",
        $config->{Picard}, $config->{fasta}, $output );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub CollectMultipleMetrics {
    my $tape = shift;
    $tape->pull;

    my $config  = $tape->options;
	my $opts = $tape->tool_options('CollectMultipleMetrics');
    my $recal = $tape->file_retrieve('PrintReads');

    my @cmds;
    foreach my $bam ( @{$recal} ) {
        ( my $w_file = $bam ) =~ s/\.bam$/\.metrics/;
        $tape->file_store($w_file);

        my $cmd = sprintf(
		"java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
		. "%s CollectMultipleMetrics INPUT=%s VALIDATION_STRINGENCY=%s PROGRAM=%s REFERENCE_SEQUENCE=%s "
		. "OUTPUT=%s\n",
		$opts->{xmx}, $opts->{gc_threads},
		$config->{tmp}, $config->{Picard}, $bam, 
		$opts->{VALIDATION_STRINGENCY}, $opts->{PROGRAM}, 
		$config->{fasta}, $w_file
        );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds );
}

##-----------------------------------------------------------
1;
