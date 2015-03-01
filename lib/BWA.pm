package BWA;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub bwa_index {
	my $tape = shift;
	$tape->pull;

	my $config = $tape->options;
	my $opts = $tape->tool_options('bwa_index');

	my $cmd = sprintf( "%s/bwa -a %s index %s %s\n",
			$config->{BWA}, $opts->{a}, $config->{fasta} );
	$tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub bwa_mem {
	my $tape = shift;
	$tape->pull;

	my $config = $tape->options;
	my $opts = $tape->tool_options('bwa_mem');

	my @z_list;
	while ( my $file = $tape->next ) {
		chomp $file;
		next unless ( $file =~ /(gz|bz2)/ );
		push @z_list, $file;
	}

	# must have matching pairs.
	if ( scalar @z_list % 2 ) {
		$tape->ERROR("FQ files must be matching pairs");
	}

	my @cmds;
	my $id   = '1';
	my $pair = '1';
	while (@z_list) {
		my $file1 = $tape->file_frags( shift @z_list );
		my $file2 = $tape->file_frags( shift @z_list );

		# collect tag and uniquify the files.
		my $tags     = $file1->{parts}[0];
		my $bam      = $file1->{parts}[0] . "_" . $pair++ . "_sorted_Dedup.bam";
		my $path_bam = $config->{output} . $bam;

		# store the output files.
		$tape->file_store($path_bam);

		my $uniq_id = $file1->{parts}[0] . "_" . $id;
		my $r_group =
			'\'@RG' . "\\tID:$uniq_id\\tSM:$tags\\tPL:ILLUMINA\\tLB:$tags\'";

		my $cmd = sprintf(
				"%s/bwa mem -t %s -R %s %s %s %s | %s/samblaster | "
				. "%s/sambamba view -f bam -l 0 -S /dev/stdin | "
				. "%s/sambamba sort -m %sG -o %s /dev/stdin",
				$config->{BWA}, $opts->{t}, $r_group, $config->{fasta},
				$file1->{full}, $file2->{full},
				$tape->software->{Samblaster}, $tape->software->{Sambamba}, 
				$tape->software->{Sambamba}, $opts->{memory_limit}, $path_bam
				);
		push @cmds, $cmd;
		$id++;
	}
	$tape->bundle( \@cmds );
}

##-----------------------------------------------------------

1;
