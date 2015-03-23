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

    my @cmds;
    while ( my $file = $tape->next ) {
        chomp $file;

        my $output;
        if ( $file =~ /(gz|bz2)/ ) {

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
        elsif ( $file =~ /(fastq|fq)/ ) {
            $tape->WARN("WARN: Files do not need to be unzipped.");
            $tape->file_store($file);
        }
    }
    $tape->bundle( \@cmds, 'off' );
}

##-----------------------------------------------------------

sub fastqc_run {
    my $tape = shift;
    $tape->pull;

    my $config = $tape->options;
    my $opts   = $tape->tool_options('fastqc_run');
    my $unzip  = $tape->file_retrieve('fastq_unzip');

    my @cmds;
    foreach my $z ( @{$unzip} ) {
        chomp $z;
        #next unless ( $z =~ /(fastq|fq)/ );
        next unless ( $z =~ /(fastq.gz|fq.gz)/ );

        my $cmd = sprintf( "%s/fastqc --threads %s -o %s -f fastq %s\n",
            $config->{FastQC}, $opts->{threads}, $config->{output}, $z );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds );
}

##-----------------------------------------------------------

1;
