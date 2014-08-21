package MD5;
use Moo;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
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
                `mv tmp.md5 $path`;
        }
	my $output = $path . 'md5_results';

        my $cmd = sprintf(
            "md5sum -c %stmp.md5 &> %s", $path, $output
        );
        push @cmds, $cmd;
    }
    $tape->WARN("No md5 file found") unless (@cmds);
    $tape->bundle(\@cmds, 'off');
}

##-----------------------------------------------------------

1;

