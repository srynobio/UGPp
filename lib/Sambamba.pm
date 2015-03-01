package Sambamba;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub sambamba_merge {
	my $tape = shift;
	$tape->pull;

	my $config = $tape->options;
	my $opts = $tape->tool_options('sambamba_merge');

	# the original collected step from sorting.
	my $sam_files = $tape->file_retrieve('bwa_mem');

	# collect one or more files based on id of the set.
	my %id_collect;
	my %merged_version;
	foreach my $sam ( @{$sam_files} ) {
		my $file = $tape->file_frags($sam);

		# change name and stack to store later.
		my $search = qr/$file->{parts}[0]/;
		( my $merged = $file->{full} ) =~ s/\.bam/_merged.bam/;

		# collect input and merge statement, also store merge file
		my $input = "INPUT=" . $sam;
		push @{ $id_collect{ $file->{parts}[0] } }, $input;

		$merged_version{ $file->{parts}[0] } = $merged;
	}

	# check to see if we should run merge
	my $id_total   = scalar keys %id_collect;
	my @ids_files  = values %id_collect;
	my $file_total = scalar map { @$_ } @ids_files;

	# return if does not need to run
	if ( $id_total eq $file_total ) { return }

	# add the merged file names to store if working with lanes
	map { $tape->file_store($_) } values %merged_version;

	my @cmds;
	foreach my $id ( keys %id_collect ) {
		my $input = join( " ", @{ $id_collect{$id} } );
		my $output = $merged_version{$id};

		my $cmd = sprintf(
				"%s/sambamba merge --nthreads=%s %s %s -p",
				$config->{Sambamba}, $opts->{nthreads}, $output, $input
				);
		push @cmds, $cmd;
	}
	$tape->bundle( \@cmds );
}

##-----------------------------------------------------------

=cut
sub sambamba_dedup {
	my $tape = shift;
	$tape->pull;

	my $config = $tape->options;

# see how many files were used.
	my $sam_files	 = $tape->file_retrieve('sambamba_sort');
	my $merged_files = $tape->file_retrieve('sambamba_merge');

	my $file_stack;
	if   ($merged_files) { $file_stack = $merged_files }
	else                 { $file_stack = $sam_files }

	my @cmds;
	foreach my $bam ( @{$file_stack} ) {
		( my $output = $bam ) =~ s/\.bam/_Dedup.bam/;

		$tape->file_store($output);

		my $cmd = sprintf(
				"%s/sambamba markdup --tmpdir=%s %s %s %s -p",
				$config->{Sambamba}, $config->{tmp}, $tape->{ddash},
				$bam, $output
				);
		push @cmds, $cmd;
	}
	$tape->bundle( \@cmds );
}
=cut 

##-----------------------------------------------------------

=cut
sub sambamba_sort {
	my $tape = shift;
	$tape->pull;

	my $config = $tape->options;

	my $bwa_files = $tape->file_retrieve('bwa_mem');

	my @cmds;
	foreach my $s ( @{$bwa_files} ) {
		( my $sort = $s ) =~ s/\.bam$/\_sorted.bam/;
		$tape->file_store($sort);

		my $cmd = sprintf(
				"%s/sambamba sort --tmpdir=%s %s %s -o %s -p",
				$config->{Sambamba}, $config->{tmp}, $tape->{ddash},
				$s, $sort 
				);
		push @cmds, $cmd;
	}
	$tape->bundle( \@cmds );
}
=cut

##-----------------------------------------------------------

1;
