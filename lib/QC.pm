package QC;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub QC_Fastqc_check {
	my $tape = shift;
	$tape->pull;
	
	my $opts = $tape->options;
	my $output_dir = $opts->{output};

	my @fails = `find $output_dir -name \"summary.txt\" -exec grep \'FAIL\' {} \\;`;
	my @warns = `find $output_dir -name \"summary.txt\" -exec grep \'WARN\' {} \\;`;

	# Clean up
	my @reports;
	if ( @fails ) {
		$tape->WARN("Fastqc reported FAIL, please review QC-report.txt\n");
		chomp @fails;
		@reports = map { $_ } @fails; 
	}
	if ( @warns ) { 
		chomp  @warns; 
		@reports = map { $_ } @warns; 
	}
	$tape->QC_report(\@reports);
	return;
}

##-----------------------------------------------------------

sub QC_idxstats {
	my $tape = shift;
	$tape->pull;
	
	my $opts = $tape->options;
	
	my $output_dir = $opts->{output};
	my @stats = `find $output_dir -name \"*_sorted.stats\"`;
	chomp @stats;

	if ( ! @stats ) {
		$tape->WARN("idxstats files not found\n");
		return;
	}

	my @report;
	foreach my $stat ( @stats ) {
		chomp $stat;
		
		my $IDX = IO::File->new($stat, 'r') 
			or $tape->WARN("idxstats $stat file can't be opened\n");

		foreach my $line (<$IDX>) {
			my @results = split("\t", $line);
			next if ($results[0] =~ /(^GL|^NC|^hs)/);

			if ( $results[2] <= $results[3] ) {
				my $record = 
					"File $stat shows a high number of unmapped reads compared to mapped at chromosome $results[0]";
				push @report, $record;
			}
		}		
		$IDX->close;
	}
	$tape->QC_report(\@report);
}

##-----------------------------------------------------------

1;

