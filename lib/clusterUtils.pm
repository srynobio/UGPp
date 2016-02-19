package clusterUtils;
use Moo::Role;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub ucgd {
    my ( $self, $commands, $step ) = @_;

    $self->ERROR("Required commands not found")
      unless ($commands);

    my ( @cmds, @copies );
    foreach my $ele ( @{$commands} ) {
        push @cmds, "$ele &";
    }
    my $cmdNode = join( "\n", @cmds );

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t 336:00:00
#SBATCH -N 1
#SBATCH -A ucgd-kp
#SBATCH -p ucgd-kp
#SBATCH -o $step\_%A.out 

source /uufs/chpc.utah.edu/common/home/u0413537/.bashrc
module load fastqforward

# clean up before start
find /scratch/local/ -user u0413537 -exec rm -rf {} \\; 

$cmdNode

wait

# clean up after finish.
find /scratch/local/ -user u0413537 -exec rm -rf {} \\; 

EOM
    return $sbatch;
}

##-----------------------------------------------------------

sub fqf {
    my ( $self, $commands, $step ) = @_;

    $self->ERROR("Required commands not found")
      unless ($commands);

    my ( @cmds, @copies );
    foreach my $ele ( @{$commands} ) {
        push @cmds, "$ele";
    }
    my $cmdNode = join( "\n", @cmds );

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t 72:00:00
#SBATCH -N 7
#SBATCH -A ucgd-kp
#SBATCH -p ucgd-kp
#SBATCH -o $step\_%A.out 

source /uufs/chpc.utah.edu/common/home/u0413537/.bashrc
source /uufs/chpc.utah.edu/common/home/yandell-group1/shell/slurm_job_prerun
module load fastqforward

# clean all shared memory.
/uufs/chpc.utah.edu/common/home/ucgdstor/common/apps/kingspeak.peaks/ucgd/dev/clean_shared.sh

# clean up before start
find /scratch/local/ -user u0413537 -exec rm -rf {} \\; 

export TMPDIR=/scratch/local

$cmdNode

wait

# clean up after finish.
find /scratch/local/ -user u0413537 -exec rm -rf {} \\; 
source /uufs/chpc.utah.edu/common/home/yandell-group1/shell/slurm_job_postrun

EOM
    return $sbatch;
}

##-----------------------------------------------------------

sub fqf_guest {
    my ( $self, $commands, $step ) = @_;

    $self->ERROR("Required commands not found")
      unless ($commands);

    my ( @cmds, @copies );
    foreach my $ele ( @{$commands} ) {
        push @cmds, "$ele";
    }
    my $cmdNode = join( "\n", @cmds );

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t 72:00:00
#SBATCH -N 7
#SBATCH -x kp[168-195,200-227]
#SBATCH -A owner-guest
#SBATCH -p kingspeak-guest
#SBATCH -o $step\_%A.out 

source /uufs/chpc.utah.edu/common/home/u0413537/.bashrc
source /uufs/chpc.utah.edu/common/home/yandell-group1/shell/slurm_job_prerun
module load fastqforward

# clean all shared memory.
/uufs/chpc.utah.edu/common/home/ucgdstor/common/apps/kingspeak.peaks/ucgd/dev/clean_shared.sh

# clean up before start
find /scratch/local/ -user u0413537 -exec rm -rf {} \\; 

export TMPDIR=/scratch/local

$cmdNode

wait

# clean up after finish.
find /scratch/local/ -user u0413537 -exec rm -rf {} \\; 
source /uufs/chpc.utah.edu/common/home/yandell-group1/shell/slurm_job_postrun

EOM
    return $sbatch;
}

##-----------------------------------------------------------

sub guest {
    my ( $self, $commands, $step ) = @_;

    $self->ERROR("Required commands not found")
      unless ($commands);

    my ( @cmds, @copies );
    foreach my $ele ( @{$commands} ) {
        push @cmds, "$ele &";
    }
    my $cmdNode = join( "\n", @cmds );

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t 72:00:00
#SBATCH -N 1
#SBATCH -x kp[168-195,200-227]
#SBATCH -A owner-guest
#SBATCH -p kingspeak-guest
#SBATCH -o $step\_%A.out 

source /uufs/chpc.utah.edu/common/home/u0413537/.bashrc

# clean up before start
find /scratch/local/ -user u0413537 -exec rm -rf {} \\; 

$cmdNode

wait

# clean up after finish.
find /scratch/local/ -user u0413537 -exec rm -rf {} \\; 

EOM
    return $sbatch;
}

##-----------------------------------------------------------

1;

