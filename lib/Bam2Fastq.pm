package Bam2Fastq;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub bam2fastq {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('bam2fastq');
    my $bams   = $self->file_retrieve;

    if ( !self->execute ) {
        $self->WARN(
            "[WARN]: bam2fastq will does not generate review commands.");
        return;
    }

    my @cmds;
    foreach my $file ( @{$bams} ) {
        chomp $file;
        next unless ( $file =~ /bam$/ );

        my $cmd = sprintf(
            "%s/bam2fastq.pl %s %s",
            $config->{Bam2Fastq}, $file, $opts->{command_string}
        );
        push @cmds, [$cmd];
    }
    $self->bundle(\@cmds);
    return;
}

##-----------------------------------------------------------

1;
