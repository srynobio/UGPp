#!/usr/bin/env perl
# UGP-SCP.pl
use strict;
use warnings;
use Net::SCP::Expect;
use Getopt::Long;
use Parallel::ForkManager;
use Carp;

my $usage = "

Synopsis:

	./UGP-SCP.pl -dt /path/to/fastqs -dt /path/to/additional/fastqs -d /path/on/remote/machine --cpu 5 --password *****

Description:

	Script to aid transfering large data sets to and from different servers.

Required options:

	-dt, --data_transfer	Path to data to transfer.  One or many can be added and can be a directory.
	-d,  --destination	Target location to move files.
	-s,  --server		Name of the server to move files to.  Currently: ember, ugp.  Groups can be added.
	-p,  --password		Password to login to remote server.
	-c,  --cpu		How many cpu/jobs to use/create to transfer data quicker.  Default 1.

Additional options:
	none

\n";

my ( $tt, $d, $target, $pass, $cpu );
GetOptions(
    "data_transfer|dt=s@" => \$tt,
    "destination|d=s"     => \$d,
    "target|t=s"          => \$target,
    "password|p=s"        => \$pass,
    "cpu|c=i"             => \$cpu,
);
croak "Required options missing\n$usage"
  unless ( $tt and $d and $target and $pass );

$cpu //= 1;
my $pm = Parallel::ForkManager->new($cpu);

# Add detail for each server to connect to
if ( $target eq 'ember' ) {

    # connection info
    my $host = 'ember.chpc.utah.edu';
    my $user = 'u0413537';
    my $des  = '~/ember-scratch';

    # build the scp object
    my $scp = Net::SCP::Expect->new(
        host      => $host,
        user      => $user,
        password  => $pass,
        recursive => 1,
    );
    transfer( $host, $des, $scp );
}

if ( $target eq 'ugp' ) {

    # connection info
    my $host = 'ugp.genetics.utah.edu';
    my $user = 'srynearson';
    my $des  = '/Repository';

    # build the scp object
    my $scp = Net::SCP::Expect->new(
        host      => $host,
        user      => $user,
        password  => $pass,
        recursive => 1,
    );
    transfer( $host, $des, $scp );
}

##--------------------------------------##
##--------------------------------------##

sub transfer {
    my ( $host, $des, $scp ) = @_;

    foreach my $datum ( @{$tt} ) {
        chomp $datum;
        $pm->start and next;

        $scp->scp( $datum, "$host:$des" )
          or croak "could not transfer\n";
        $pm->finish;
    }
    $pm->wait_all_children;
    return;
}

