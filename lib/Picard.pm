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

    my $opts = $tape->options;

    my $fa_file = $tape->file_frags( $opts->{fasta} );
    ( my $output = $fa_file->{full} ) =~ s/(.*)\.(fasta|fa)/$1.dict/;

    my $cmd = sprintf( "java -jar %s CreateSequenceDictionary.jar R=%s O=%s\n",
        $opts->{Picard}, $opts->{fasta}, $output );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

#sub SortSam {
#    my $tape = shift;
#    $tape->pull;
#
#    my $opts = $tape->options;
#
#    my $bwa_files = $tape->file_retrieve('bwa_mem');
#
#    my @cmds;
#    foreach my $s ( @{$bwa_files} ) {
#        ( my $sort = $s ) =~ s/\.bam$/\_sorted.bam/;
#        $tape->file_store($sort);
#
#        my $cmd =
#          sprintf( "java -jar -XX:ParallelGCThreads=%s -Xmx%s "
#              . "-Djava.io.tmpdir=%s %s SortSam INPUT=%s "
#              . "OUTPUT=%s %s\n",
#            $opts->{java_picard_thread}, $opts->{java_xmx},
#            $opts->{tmp}, $opts->{Picard}, $s, $sort, $tape->equal_dash );
#        push @cmds, $cmd;
#    }
#    $tape->bundle( \@cmds );
#}
#
###-----------------------------------------------------------
#
#sub MergeSamFiles {
#    my $tape = shift;
#    $tape->pull;
#
#    my $opts = $tape->options;
#
#    # the original collected step from sorting.
#    my $sam_files = $tape->file_retrieve('SortSam');
#
#    # collect one or more files based on id of the set.
#    my %id_collect;
#    my %merged_version;
#    foreach my $sam ( @{$sam_files} ) {
#        my $file = $tape->file_frags($sam);
#
#        # change name and stack to store later.
#        my $search = qr/$file->{parts}[0]/;
#        ( my $merged = $file->{full} ) =~ s/($search)(.*)$/$1_merged.bam/;
#
#        # collect input and merge statement, also store merge file
#        my $input = "INPUT=" . $sam;
#        push @{ $id_collect{ $file->{parts}[0] } }, $input;
#
#        $merged_version{ $file->{parts}[0] } = $merged;
#    }
#
#    # check to see if we should run mergesam
#    my $id_total   = scalar keys %id_collect;
#    my @ids_files  = values %id_collect;
#    my $file_total = scalar map { @$_ } @ids_files;
#
#    # return if does not need to run
#    if ( $id_total == $file_total ) { return }
#
#    # add the merged file names to store if working with lanes
#    map { $tape->file_store($_) } values %merged_version;
#
#    my @cmds;
#    foreach my $id ( keys %id_collect ) {
#        my $input = join( " ", @{ $id_collect{$id} } );
#        my $output = "OUTPUT=" . $merged_version{$id};
#
#        my $cmd = sprintf(
#            "java -jar -Xmx%s -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
#              . "%s MergeSamFiles %s %s %s\n",
#            $opts->{java_xmx}, $opts->{java_picard_thread},
#            $opts->{tmp}, $opts->{Picard}, $tape->equal_dash, $input, $output );
#        push @cmds, $cmd;
#    }
#    $tape->bundle( \@cmds );
#}
#
##-----------------------------------------------------------

#sub MarkDuplicates {
#    my $tape = shift;
#    $tape->pull;
#
#    my $opts = $tape->options;
#
#    # see how many files were used.
#    my $sam_files    = $tape->file_retrieve('SortSam');
#    my $merged_files = $tape->file_retrieve('MergeSamFiles');
#
#    my $file_stack;
#    if   ($merged_files) { $file_stack = $merged_files }
#    else                 { $file_stack = $sam_files }
#
#    my @cmds;
#    foreach my $bam ( @{$file_stack} ) {
#        ( my $output = $bam ) =~ s/\.bam/_Dedup.bam/;
#        ( my $metric = $bam ) =~ s/\.bam/_Dedup.metrics/;
#
#        $tape->file_store($output);
#
#        my $cmd = sprintf(
#            "java -jar -Xmx%s -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
#              . "%s MarkDuplicates INPUT=%s OUTPUT=%s METRICS_FILE=%s %s\n",
#            $opts->{java_xmx}, $opts->{java_picard_thread},
#            $opts->{tmp}, $opts->{Picard},
#            $bam, $output, $metric, $tape->equal_dash );
#        push @cmds, $cmd;
#    }
#    $tape->bundle( \@cmds );
#}

##-----------------------------------------------------------

sub CollectMultipleMetrics {
    my $tape = shift;
    $tape->pull;

    my $opts  = $tape->options;
    my $recal = $tape->file_retrieve('PrintReads');

    my @cmds;
    foreach my $bam ( @{$recal} ) {
        ( my $w_file = $bam ) =~ s/\.bam$/\.metrics/;
        $tape->file_store($w_file);

        my $cmd = sprintf(
            "java -jar -Xmx%s -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
              . "%s CollectMultipleMetrics INPUT=%s %s REFERENCE_SEQUENCE=%s "
              . "OUTPUT=%s\n",
            $opts->{java_xmx}, $opts->{java_picard_thread}, $opts->{tmp},
            $opts->{Picard}, $bam, $tape->equal_dash, $opts->{fasta}, $w_file );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds );
}

##-----------------------------------------------------------
1;
