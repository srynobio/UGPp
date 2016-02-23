package wham;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

has seqid_skip => (
    is      => 'rw',
    builder => 1,
);

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub _build_seqid_skip {
    my $self = shift;

    my @record;
    while ( my $data = <DATA> ) {
        chomp $data;
        push @record, $data;
    }
    my $ids = join( ",", @record );
    $self->seqid_skip($ids);
}

##-----------------------------------------------------------

sub wham_graphing {
    my $self = shift;
    $self->pull;

    my $config = $self->class_config;
    my $opts   = $self->tool_options('wham_graphing');
    my $files  = $self->file_retrieve('bwa_mem');

    my $skip_ids = $self->seqid_skip;

    my @cmds;
    foreach my $bam ( @{$files} ) {
        chomp $bam;

        next unless ( $bam =~ /bam$/ );

        my $file   = $self->file_frags($bam);
        my $output = $config->{output} . $file->{parts}[0] . "_WHAM.vcf";
        $self->file_store($output);

        my $threads;
        ( $opts->{x} ) ? ( $threads = $opts->{x} ) : ( $threads = 1 );

        my $cmd = sprintf( "%s/WHAM-GRAPHENING -a %s -k -x %s -f %s -e %s > %s",
            $config->{wham}, $config->{fasta}, $threads, $bam, $skip_ids, $output );
        push @cmds, $cmd;
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub wham_filter {
    my $self = shift;
    $self->pull;

    my $config = $self->class_config;
    my $opts   = $self->tool_options('wham_filter');
    my $files  = $self->file_retrieve('wham_graphing');

    ## just temp the first item to get info.
    my $parts = $self->file_frags( $files->[0] );

    my @cmds;
    foreach my $wham ( @{$files} ) {
        chomp $wham;

        ( my $output = $wham ) =~ s/_WHAM.vcf/_filtered.WHAM.vcf/;
        $self->file_store($output);

        my $cmd = sprintf( "cat %s | %s -filter -o %s",
            $wham, $self->software->{wham_utils}, $output );
        push @cmds, $cmd;
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub wham_sort {
    my $self = shift;
    $self->pull;

    my $config = $self->class_config;
    my $opts   = $self->tool_options('wham_sort');
    my $files  = $self->file_retrieve('wham_filter');

    my $output = $config->{output} . $config->{ugp_id} . "_WHAM.filtered.vcf";
    $self->file_store($output);

    #my $input = $files->[0];
    #( my $output = $input ) =~ s/_filtered.WHAM.vcf/_filtered_sorted.WHAM.vcf/;
    #$self->file_store($output);

    my $joined = join( " ", @{$files} );

    my $cmd = sprintf(
        "cat %s >> %swham.tmp && sort -T %s -k1,1 -k2,2n %swham.tmp -o %s && rm %swham.tmp",
        $joined,           $config->{output}, '/tmp',
        $config->{output}, $output,           $config->{output}
    );

    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

sub wham_merge_indiv {
    my $self = shift;
    $self->pull;

    my $config = $self->class_config;
    my $opts   = $self->tool_options('wham_merge_indiv');
    my $files  = $self->file_retrieve('wham_sort');

    ( my $output = $files->[0] ) =~ s/_WHAM.filtered.vcf/_mergeIndv.vcf/;

    my $cmd = sprintf( "%s/mergeIndvs -f %s -s %s > %s",
        $config->{wham}, $files->[0], $opts->{s}, $output );
    $self->file_store($output);
    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

sub wham_splitter {
    my $self = shift;
    $self->pull;

    unless ( $self->execute ) {
        $self->WARN( "Review of wham_splitter command not possible "
              . "only generated during run." );
        return;
    }

    my $files = $self->file_retrieve('wham_merge_indiv');

    # open to get content.
    open( my $FH, '<', $files->[0] );
    my @lines;
    while (<$FH>) {
        push @lines, $_;
    }
    close $FH;

    my @sections;
    push @sections, [ splice @lines, 0, 200 ] while @lines;

    ## get file parts
    my $frags = $self->file_frags( $files->[0] );

    ## test if temp file already exist.
    my $tmp_test = $frags->{path} . 'UGP_split_temp_*_WHAM.vcf';
    if ( glob $tmp_test ) {
        unlink glob "$tmp_test";
    }
    $self->WARN("wham_splitter creating files of 200 per-file.");

    my @cmds;
    my $id;
    for my $chunk (@sections) {
        $id++;
        my $output = $frags->{path} . 'UGP_split_temp_' . $id . '_WHAM.vcf';
        open( my $OUT, '>>', $output );
        $self->file_store($output);
        map { print $OUT $_ } @{$chunk};
    }
}

##-----------------------------------------------------------

sub wham_genotype {
    my $self = shift;
    $self->pull;

    unless ( $self->execute ) {
        $self->WARN( "Review of wham_genotype command not possible "
              . "only generated during run." );
        return;
    }

    my $config    = $self->class_config;
    my $opts      = $self->tool_options('wham_genotype');
    my $files     = $self->file_retrieve('wham_splitter');
    my $bam_files = $self->file_retrieve('bwa_mem');

    my $join_bams = join( ",", @{$bam_files} );
    my $skip_ids = $self->seqid_skip;

    my @cmds;
    for my $indiv ( @{$files} ) {
        chomp $indiv;

        ( my $output = $indiv ) =~ s/_WHAM.vcf/_genotyped_WHAM.vcf/;
        $self->file_store($output);

        my $threads;
        ( $opts->{x} ) ? ( $threads = $opts->{x} ) : ( $threads = 1 );

        my $cmd =
          sprintf( "%s/WHAM-GRAPHENING -a %s -x %s -f %s -e %s -b %s > %s",
            $config->{wham}, $config->{fasta}, $threads, $join_bams, $skip_ids,
            $indiv, $output );
        push @cmds, $cmd;
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub wham_genotype_cat {
    my $self = shift;
    $self->pull;

    unless ( $self->execute ) {
        $self->WARN( "Review of wham_genotype_cat command not possible "
              . "only generated during run." );
        return;
    }

    my $config = $self->class_config;
    my $opts   = $self->tool_options('wham_genotype_cat');
    my $files  = $self->file_retrieve('wham_genotype');

    ## get file info
    my $parts       = $self->file_frags( $files->[0] );
    my $header      = $parts->{path} . $config->{ugp_id} . "_header.txt";
    my $tmp_output  = $parts->{path} . $config->{ugp_id} . "_tmp.WHAM.vcf";
    my $sort_output = $parts->{path} . $config->{ugp_id} . "_sort.WHAM.vcf";
    my $output      = $parts->{path} . $config->{ugp_id} . "_Final.WHAM.vcf";
    $self->file_store($output);

    ## open and print header file.
    open( my $FH, '<', $files->[0] )
      or $self->ERROR("Needed WHAM files not found.");
    open( my $HEADER, '>>', $header )
      or $self->ERROR("Can not create needed header file.");

    while (<$FH>) {
        chomp $_;
        if ( $_ =~ /^#/ ) {
            print $HEADER "$_\n";
        }
    }
    close $FH;
    close $HEADER;

    open( my $OUT, '>>', $tmp_output );
    foreach my $gtype ( @{$files} ) {
        open( my $FH, '<', $gtype );

        while (<$FH>) {
            chomp $_;
            next if ( $_ =~ /^#/ );
            print $OUT "$_\n";
        }
        close $FH;
    }
    close $OUT;

    my $cmd = sprintf( "sort -k1,1 -k2,2n %s > %s && cat %s %s > %s && rm %s",
        $tmp_output, $sort_output, $header, $sort_output, $output, $header );
    $self->bundle( \$cmd );
}

##-----------------------------------------------------------
1;

__DATA__
GL000207.1
GL000226.1
GL000229.1
GL000231.1
GL000210.1
GL000239.1
GL000235.1
GL000201.1
GL000247.1
GL000245.1
GL000197.1
GL000203.1
GL000246.1
GL000249.1
GL000196.1
GL000248.1
GL000244.1
GL000238.1
GL000202.1
GL000234.1
GL000232.1
GL000206.1
GL000240.1
GL000236.1
GL000241.1
GL000243.1
GL000242.1
GL000230.1
GL000237.1
GL000233.1
GL000204.1
GL000198.1
GL000208.1
GL000191.1
GL000227.1
GL000228.1
GL000214.1
GL000221.1
GL000209.1
GL000218.1
GL000220.1
GL000213.1
GL000211.1
GL000199.1
GL000217.1
GL000216.1
GL000215.1
GL000205.1
GL000219.1
GL000224.1
GL000223.1
GL000195.1
GL000212.1
GL000222.1
GL000200.1
GL000193.1
GL000194.1
GL000225.1
GL000192.1
NC_007605
hs37d5
phix
