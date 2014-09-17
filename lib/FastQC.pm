package FastQC;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub FastQC_unzip {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my @cmds;
    while ( my $file = $tape->next ) {
        chomp $file;

        next unless ( $file =~ /\.gz$/ );

        my $output;
        if ( $file =~ /txt/ ) {
            ( $output = $file ) =~ s/\.gz$/\.fastq/;
        }
        elsif ( $file =~ /fastq/ ) {
            ( $output = $file ) =~ s/\.gz$//;
        }

        $tape->file_store($output);

        my $cmd = sprintf( "gunzip -c %s > %s", $file, $output );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds, 'off' );
}

##-----------------------------------------------------------

sub FastQC_QC {
    my $tape = shift;
    $tape->pull;

    my $opts  = $tape->options;
    my $unzip = $tape->file_retrieve('FastQC_unzip');

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
