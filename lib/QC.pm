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

}


##-----------------------------------------------------------

sub MD5_checksum {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my @cmds;
    while ( my $file = $tape->next ) {
        chomp $file;
        next unless ( $file =~ /md5_checksums.txt/ );

        my $path = $opts->{data};

        # add file path to file.
        my $file_update = "perl -lane '\$F[1] =~ s?^?  $path?; print \@F' $file > tmp.md5";
        if ( $tape->execute ) {
                `$file_update`;
                `mv tmp.md5 $file`;
        }

        my $cmd = sprintf(
            "md5sum -c %s", $file
        );
        push @cmds, $cmd;
    }
    $tape->bundle(\@cmds);
}

##-----------------------------------------------------------

1;

