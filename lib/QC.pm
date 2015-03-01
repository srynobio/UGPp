package QC;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub md5_check {
	my $tape = shift;
	$tape->pull;
	unless ( $tape->execute ) { return }

	while ( my $check = $tape->next ) {
		chomp $check;
		next unless ( $check =~ /md5_results/ );

		my @md5_results = `cat $check`;

		my @passed;
		foreach my $test (@md5_results) {
			chomp $test;
			next unless ( $test =~ /OK$/ );
			push @passed, $test;
		}

		unless ( scalar @md5_results eq scalar @passed ) {
			$tape->ERROR("One or more md5 sum checked did not pass");
		}
	}
	return;
}

##-----------------------------------------------------------

sub fastqc_check {
	my $tape = shift;
	$tape->pull;
	unless ( $tape->execute ) { return }

	my $config       = $tape->options;
	my $output_dir = $config->{output};

	my @fails =
		`find $output_dir -name \"summary.txt\" -exec grep \'FAIL\' {} \\;`;
	my @data = `find $output_dir -name \"fastqc_data.txt\"`;

	# Clean up
	my @reports;
	if (@fails) {
		$tape->WARN("Fastqc reported contains FAIL files, please review QC-report.txt");
		chomp @fails;
		@reports = map { $_ } @fails;
	}

	foreach my $d (@data) {
		chomp $d;

		my $DT = IO::File->new( $d, 'r' )
			or $tape->WARN("Fastqc file $d can't be opened\n");

		my $fail;
		foreach my $result (<$DT>) {
			chomp $result;
			next unless ( $result =~ 
				/(^Encoding|^Total Sequences|^Filtered Sequences|^Sequence length|^\%GC|^Total Duplicate Percentage)/
			);
			my @view = split "\t", $result;

			if ( $view[0] eq 'Encoding' and $view[1] ne 'Sanger / Illumina 1.9' ) {
				$fail++;
				next;
			}
			if ( $view[0] eq 'Total Sequences' and $view[1] < 30000000 ) {
				$fail++;
				next;
			}
			if ( $view[0] eq 'Filtered Sequences' and $view[1] >= 5 ) {
				$fail++;
				next;
			}
			if ( $view[0] eq 'Sequence length' and $view[1] ne '100' ) {
				$fail++;
				next;
			}
			if ( $view[0] eq '%GC' and ( $view[1] > 55 or $view[1] < 45 ) ) {
				$fail++;
				next;
			}
			if ( $view[0] eq 'Total Duplicate Percentage' and $view[1] > '60.0' ) {
				$fail++;
				next;
			}
			$tape->WARN("One or more QC data report values failed review QC-report.txt file") if $fail;
		}
		push @reports, $d if $fail;
	}
	$tape->QC_report( \@reports );
}

##-----------------------------------------------------------

sub idxstats_check {
	my $tape = shift;
	$tape->pull;
	unless ( $tape->execute ) { return }

	my $config = $tape->options;
	my $output_dir = $config->{output};

	my @stats      = `find $output_dir -name \"*_sorted.stats\"`;
	chomp @stats;

	if ( !@stats ) {
		$tape->WARN("idxstats files not found\n");
		return;
	}

	my @report;
	foreach my $stat (@stats) {
		chomp $stat;

		my $IDX = IO::File->new( $stat, 'r' )
			or $tape->WARN("idxstats $stat file can't be opened\n");

		foreach my $line (<$IDX>) {
			my @results = split( "\t", $line );
			next if ( $results[0] =~ /(^GL|^NC|^hs)/ );

			if ( $results[2] <= $results[3] ) {
				my $record =
					"File $stat shows a high number of unmapped reads compared to mapped at chromosome $results[0]";
				push @report, $record;
			}
		}
		$IDX->close;
	}
	$tape->QC_report( \@report );
}

##-----------------------------------------------------------

#TODO
sub metrics_check {}

##-----------------------------------------------------------

1;
