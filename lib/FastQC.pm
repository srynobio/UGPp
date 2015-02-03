package FastQC;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub fastq_unzip {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my @cmds;
    while ( my $file = $tape->next ) {
        chomp $file;

        next unless ( $file =~ /(gz|bz2)/ );

        (my $output = $file) =~ s/$/.fastq/;

        $tape->file_store($output);

        my $cmd = sprintf( "gunzip -c %s > %s", $file, $output );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds, 'off' );
}

=cut
sub fastq_unzip {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my @cmds;
    while ( my $file = $tape->next ) {
        chomp $file;

        next unless ( $file =~ /(gz|bz2)/ );

        my $output;
        if ( $file =~ /txt/ ) {
            ( $output = $file ) =~ s/\.gz$/\.fastq/;
        }
	elsif ( $file =~ /bz2/ ) {
            ( $output = $file ) =~ s/\.bz2$//;
	}
        elsif ( $file =~ /fastq/ ) {
            ( $output = $file ) =~ s/\.gz$//;
        }
        elsif ( $file =~ /fastq.gz/ ) {
            ( $output = $file ) =~ s/fastq.gz/fastq/;
        }

        $tape->file_store($output);

        my $cmd = sprintf( "gunzip -c %s > %s", $file, $output );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds, 'off' );
}
=cut

##-----------------------------------------------------------

sub fastqc_run {
    my $tape = shift;
    $tape->pull;

    my $opts  = $tape->options;
    my $unzip = $tape->file_retrieve('fastq_unzip');

    my @cmds;
    foreach my $z ( @{$unzip} ) {
        chomp $z;
        next unless ( $z =~ /\.fastq/ );

        my $cmd = sprintf( "%s/fastqc %s -o %s -f fastq %s\n",
            $opts->{FastQC}, $tape->ddash, $opts->{output}, $z );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds );
}

##-----------------------------------------------------------
1;
