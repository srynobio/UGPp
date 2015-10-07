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

    if ( !$self->execute ) {
        $self->WARN(
            "bam2fastq will does not generate review commands.");
            return;
    }

    my @cmds;
    foreach my $file ( @{$bams} ) {
        chomp $file;
        next unless ( $file =~ /bam$/ );

        my $cmd = sprintf( "%s/bam2fastq.pl %s %s",
            $config->{Bam2Fastq}, $file, $opts->{command_string} );
        push @cmds, [$cmd];
    }
    $self->bundle( \@cmds );
    return;
}

##-----------------------------------------------------------

sub nantomics_bam2fastq {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('nantomics_bam2fastq');
    my $bams   = $self->file_retrieve;

    if ( !$self->execute ) {
        $self->WARN("bam2fastq will does not generate review commands.");
        return;
    }

    my @cmds;
    foreach my $bam ( @{$bams} ) {
        chomp $bam;
        next unless ( $bam =~ /bam$/ );

        my $file = $self->file_frags($bam);

        my $filename = $file->{name};
        ( my $id, undef ) = split /--/, $filename;

        my $pair1 = $file->{path} . $id . '_1.fastq.gz';
        my $pair2 = $file->{path} . $id . '_2.fastq.gz';

        my $cmd = sprintf(
            "%s/bam2fastq.pl %s %s -fq %s -fq2 %s",
            $config->{Bam2Fastq}, $bam, $opts->{command_string},
            $pair1, $pair2,
        );
        push @cmds, [$cmd];
    }
    $self->bundle( \@cmds );
    return;
}

##-----------------------------------------------------------

1;
