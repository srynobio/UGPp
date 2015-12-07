package WHAM;
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

    my $config = $self->options;
    my $opts   = $self->tool_options('wham_graphing');
    my $files  = $self->file_retrieve('sambamba_bam_merge');

    my @cmds;
    foreach my $merged ( @{$files} ) {
        chomp $merged;

        my $file   = $self->file_frags($merged);
        my $output = $file->{path} . $file->{parts}[0] . "_WHAM.vcf";
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

sub wham_filter {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('wham_filter');
    my $files  = $self->file_retrieve('wham_graphing');

    ## just temp the first item to get info.
    my $parts = $self->file_frags( $files->[0] );

    my $join_file = join( " ", @{$files} );
    my $output = $parts->{path} . $config->{ugp_id} . "_filtered.WHAM.vcf";
    $self->file_store($output);

    my $cmd = sprintf( "cat %s | %s -filter -o %s",
        $join_file, $self->software->{wham_utils}, $output );
    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

sub wham_sort {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('wham_sort');
    my $files  = $self->file_retrieve('wham_filter');

    my $input = $files->[0];
    ( my $output = $input ) =~ s/_filtered.WHAM.vcf/_filtered_sorted.WHAM.vcf/;
    $self->file_store($output);

    my $cmd = sprintf(
        "%s -sort -i %s -o %s",
        $self->software->{wham_utils},
        $input, $output
    );
    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

sub wham_merge_indiv {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('wham_merge_indiv');
    my $files  = $self->file_retrieve('wham_sort');

    ( my $output = $files->[0] ) =~ s/_filtered_sorted.WHAM.vcf/_mergeIndv.vcf/;

    my $cmd = sprintf( "%s/mergeIndvs -f %s -s %s > %s",
        $config->{WHAM}, $files->[0], $opts->{s}, $output );
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

    $self->WARN("wham_splitter creating files of 200 lines long.");

    my @cmds;
    for my $chunk (@sections) {
        my $output =
          $frags->{path} . 'UGP_split_temp_' . int( rand(1000) ) . '_WHAM.vcf';
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

    my $config    = $self->options;
    my $opts      = $self->tool_options('wham_genotype');
    my $files     = $self->file_retrieve('wham_splitter');
    my $bam_files = $self->file_retrieve('sambamba_bam_merge');

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
            $config->{WHAM}, $config->{fasta}, $threads, $join_bams, $skip_ids,
            $indiv, $output );
        push @cmds, [$cmd];
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

    my $config = $self->options;
    my $opts   = $self->tool_options('wham_genotype_cat');
    my $files  = $self->file_retrieve('wham_genotype');

    # open to get header.
    open( my $FH, '<', $files->[0] );
    my @lines;
    while (<$FH>) {
        chomp $_;
        if ( $_ =~ /^#/ ) {
            push @lines, $_;
        }
    }
    close $FH;

    my $parts  = $self->file_frags( $files->[0] );
    my $output = $parts->{path} . $config->{ugp_id} . "_final.WHAM.vcf";
    $self->file_store($output);

    open( my $OUT, '>>', $output );
    map { say $OUT $_ } @lines;
    close $OUT;

    my $join_file = join( " ", @{$files} );
    my $cmd = sprintf( "cat %s | grep -v \'^#\' | sort -k1,1n -k2,2n > %s",
        $join_file, $output );
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
