package Tabix;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub bz_tabix {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('bz_tabix');

    my $combine_file = $self->file_retrieve('CombineVariants');
    my $output_file  = "$combine_file->[0]" . '.gz';

    my $cmd = sprintf(
        "(%s/bgzip -c %s > %s; %s/tabix -p vcf %s)",
        $config->{Tabix}, $combine_file->[0], $output_file,
        $config->{Tabix}, $output_file
    );
    $self->bundle( \$cmd );
}

##-----------------------------------------------------------

1;
