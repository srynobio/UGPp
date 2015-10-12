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

sub wham_merge_cat {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('wham_merge_cat');
    my $files  = $self->file_retrieve('wham_graphing');

    ## just temp the first item to get info.
    my $parts = $self->file_frags($files->[0]);

    my $join_file = join(" ", @{$files});
    my $output = $parts->{path} . $config->{ugp_id} . "_merged.WHAM.vcf"; 
    $self->file_store($output);

    my $cmd = sprintf("cat %s > %s", $join_file, $output);
    $self->bundle(\$cmd);
}

##-----------------------------------------------------------

sub wham_merge_sort {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('wham_merge_sort');
    my $files  = $self->file_retrieve('wham_merge_cat');

    ## just temp the first item to get info.
    my $parts = $self->file_frags($files->[0]);

    my $output = $parts->{path} . $config->{ugp_id} . "_merged_sorted.WHAM.vcf";
    $self->file_store($output);

    my $cmd =
      sprintf( "grep -v '^#' %s | sort -T %s -k1,1 -k2,2n > %s", 
          @{$files}, $self->config->{main}->{tmp}, $output 
      );

    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

sub wham_merge_indiv {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('wham_merge_indiv');
    my $files  = $self->file_retrieve('wham_merge_sort');

    ## just temp the first item to get info.
    my $parts = $self->file_frags( $files->[0] );

    my $output = $parts->{path} . $config->{ugp_id} . "_mergeIndvs.WHAM.vcf";
    $self->file_store($output);

    my $cmd = sprintf( "%s/mergeIndvs -f %s > %s",
        $config->{WHAM}, $files->[0], $output );
    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

sub wham_filter {
	my $self = shift;
	$self->pull;

	my $config = $self->options;
	my $opts   = $self->tool_options('wham_filter');
	my $files  = $self->file_retrieve('wham_merge_indiv');

	open( my $VCF,'<',  @{$files}[0] );

	my @kept;
	foreach my $line (<$VCF>) {
		chomp $line;

		my @parts = split /\t/, $line;
		my @info  = split /;/,  $parts[7];
	
		foreach my $pair (@info) {
			chomp $pair;
			my ( $id, $value ) = split /=/, $pair;

			next unless ( $id eq 'SUPPORT' or $id eq 'SVLEN');

			if ( $id eq 'SVLEN' ) {
				unless ( $value <= $opts->{lt_svlen} and $value >= $opts->{gt_svlen}) {
					undef $line;
					next;
				}
			}

			if ( $id eq 'SUPPORT') {	
				my ( $left, $right ) = split /,/, $value;
				unless ( $left >= $opts->{support} and $right >= $opts->{support} ) {
					undef $line;
					next;
				}
			}
		}
			push @kept, $line if $line;
	}
	(my $output = @{$files}[0]) =~ s/\.vcf$/\_filtered.vcf/;

	open(my $OUTPUT, '>', $output);
	map { say $OUTPUT $_ } @kept;
}

##-----------------------------------------------------------

#sub wham_genotyping {
#    my $self = shift;
#    $self->pull;
#
#    my $config = $self->options;
#    my $opts   = $self->tool_options('wham_genotyping');
#    my $files  = $self->file_retrieve('wham_merge_indiv');
#    my $bam_files  = $self->file_retrieve('sambamba_bam_merge');
#
#    ## collect polished bams.
#    my $bams = join(",", @{$bam_files});
#
#    my $file   = $self->file_frags( $files->[0] );
#    my $output = $file->{path} . $config->{ugp_id} . "_final_WHAM.vcf";
#    $self->file_store($output);
#
#    my $threads;
#    ( $opts->{x} ) ? ( $threads = $opts->{x} ) : ( $threads = 1 );
#
#    my $cmd = sprintf( "%s/WHAM-GRAPHENING -a %s -x %s -b %s -f %s > %s",
#        $config->{WHAM}, $config->{fasta}, $threads, $files->[0], $bams, $output );
#
#    $self->bundle( \$cmd );
#}

##-----------------------------------------------------------

1;

