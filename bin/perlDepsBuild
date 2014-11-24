#!/usr/bin/env perl
use warnings;
use strict;

BEGIN { 
	unless ( $ENV{USER} eq 'root' ) {
		die "Please run script as root user\n";
	}
};

print "Attempting to install needed Perl modules\n";
system("perl -MCPAN -e 'install Moo'");
system("perl -MCPAN -e 'install MCE'");
system("perl -MCPAN -e 'install Config::Std'");
system("perl -MCPAN -e 'install IPC::System::Simple'");

