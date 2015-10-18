package BWA;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub bwa_index {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('bwa_index');

    my $cmd = sprintf( "%s/bwa -a %s index %s %s\n",
        $config->{BWA}, $opts->{a}, $config->{fasta} );
    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

sub bwa_mem {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('bwa_mem');
    my $files  = $self->file_retrieve('fastqc_run');

    my @seq_files;
    foreach my $file ( @{$files} ) {
        chomp $file;
        next unless ( $file =~ /(gz$|bz2$|fastq$|fq$)/ );
        push @seq_files, $file;
    }

    # must have matching pairs.
    if ( scalar @seq_files % 2 ) {
        $self->ERROR( "FQ files must be matching pairs. "
              . " And directory has only fastq files." );
    }

    my @cmds;
    my $id   = '1';
    my $pair = '1';
    while (@seq_files) {
        my $file1 = $self->file_frags( shift @seq_files );
        my $file2 = $self->file_frags( shift @seq_files );

        # collect tag and uniquify the files.
        my $tags     = $file1->{parts}[0];
        my $bam      = $file1->{parts}[0] . "_" . $pair++ . "_sorted_Dedup.bam";
        my $path_bam = $config->{output} . $bam;

        my $dis_bam =
          $file1->{parts}[0] . "_" . $pair++ . "_sorted_Dedup_discordant.bam";
        my $split_bam =
          $file1->{parts}[0] . "_" . $pair++ . "_sorted_Dedup_splitter.bam";

        # store the output files.
        $self->file_store($path_bam);

        my $uniq_id = $file1->{parts}[0] . "_" . $id;
        my $r_group =
          '\'@RG' . "\\tID:$uniq_id\\tSM:$tags\\tPL:ILLUMINA\\tLB:$tags\'";

        my $cmd = sprintf(
            "%s/bwa mem -t %s -R %s %s %s %s 2> bwa_mem_%s.log | "
              . "%s/samblaster --addMateTags --discordantFile %s --splitterFile %s | "
              . "%s/sambamba view --nthreads 1 -f bam -l 0 -S /dev/stdin | "
              . "%s/sambamba sort -m %sG --tmpdir=%s -o %s /dev/stdin",
            $config->{BWA},              $opts->{t},
            $r_group,                    $config->{fasta},
            $file1->{full},              $file2->{full},
            $id,                         $self->software->{Samblaster},
            $dis_bam,                    $split_bam,
            $self->software->{Sambamba}, $self->software->{Sambamba},
            $opts->{memory_limit},       $config->{tmp},
            $path_bam
        );
        push @cmds, [ $cmd, $file1->{full}, $file2->{full} ];

        $id++;
    }
    $self->bundle( \@cmds );
    return;
}

##-----------------------------------------------------------

1;
