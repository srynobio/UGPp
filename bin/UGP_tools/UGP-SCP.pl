#!/usr/bin/perl
# UGP-SCP.pl
use strict;
use warnings;
use Net::SCP::Expect;
use Getopt::Long;
use IO::Dir;
use Carp;

my $usage = "

Synopsis:

	./UGP-SCP.pl --remote_path <string> --local_path <string> --password <string>
	./UGP-SCP.pl -rp /remote/data -lp /place/that/data -p *****

Description:

	Script to aid transfering large data sets to and from UGP server.

Required options:

	-rp, --remote_path: 	Path on remote server to get data.
	-lp, --local_path:	Path to place data on local server.
	-p,  --password:	Password to login to remote server. 
				Enclose in \'\' for best results.

\n";

my ( $rp, $lp, $server, $pass );
GetOptions(
    "remote_path|rp=s" => \$rp,
    "local_path|lp=s"  => \$lp,
    "password|p=s"     => \$pass,
);
croak "Required options missing\n$usage" unless ( $rp and $lp );

# connection info
my $host = 'ugp.genetics.utah.edu';
my $user = 'srynearson';

# build the scp object
my $scp = Net::SCP::Expect->new(
    user      => $user,
    password  => $pass,
    recursive => 1,
    timeout   => 20,
    verbose   => 1,
);
$scp->scp( "$host:$rp", "$lp" );

