package ClusterUtils;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub ucgd {
    my ( $self, $commands ) = @_;

    $self->ERROR("Required commands not found")
      unless ($commands);

    #collect original paths.
    my $input  = $self->main->{data};
    my $output = $self->main->{output};
    my $indel  = '/scratch/ucgd/lustre/u0413537/UGP_Pipeline_Data/GATK_Bundle/';

    my ( @cmds, @copies );
    foreach my $ele ( @{$commands} ) {
        $ele->[0] =~ s|$output|/scratch/local/|g if ( $ele->[1] );
        $ele->[0] =~ s|$input|/scratch/local/|g  if ( $ele->[1] );
        $ele->[0] =~ s|$indel|/scratch/local/|g  if ( $ele->[1] );
        push @cmds, "$ele->[0] &";

        if ( $ele->[1] ) {
            shift( @{$ele} );    # shift off command.
            foreach my $cp ( @{$ele} ) {
                ( my $all_file = $cp ) =~ s/\.ba.*$//g;
                push @copies, "cp $all_file* /scratch/local &";
            }
        }
    }

    my $cpNode  = join( "\n", @copies );
    my $cmdNode = join( "\n", @cmds );

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t 72:00:00
#SBATCH -N 1
#SBATCH -A ucgd-kp
#SBATCH -p ucgd-kp

source /uufs/chpc.utah.edu/common/home/u0413537/.bash_profile

# clean up before start
find /scratch/local/ -user u0413537 -exec rm -rf {} \\; 

$cpNode

wait

$cmdNode

wait

# move results
find /scratch/local/ -user u0413537 -exec mv -n {} $output \\;

# clean up after finish.
find /scratch/local/ -user u0413537 -exec rm -rf {} \\; 

EOM

    return $sbatch;
}

##-----------------------------------------------------------

1;

