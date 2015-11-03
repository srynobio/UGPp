package Base;
use Moo;
use Config::Std;
use File::Basename;
use IO::Dir;
use Storable 'dclone';
use File::Slurper 'read_lines';
use feature 'say';

#-----------------------------------------------------------
#---------------------- ATTRIBUTES -------------------------
#-----------------------------------------------------------

has VERSION => (
    is      => 'ro',
    default => sub { '1.4.0' },
);

has commandline => (
    is       => 'rw',
    required => 1,
    default  => sub {
        die "commandline options were not given\n";
    },
);

has config => (
    is      => 'rw',
    builder => '_build_config',
);

has main => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->config->{main};
    },
);

has software => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->config->{software};
    },
);

has data => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->config->{main}->{data};
    },
);

has order => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->config->{order}->{command_order};
    },
);

has workers => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        my $workers = $self->main->{workers} || '1';
        return $workers + 1;
    },
);

has execute => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->commandline->{run} || 0;
    },
);

has individuals => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->commandline->{individuals} || 0;
    },
);

## TODO review how this is used.
has file_from_command => (
    is      => 'rw',
    default => sub {
        return undef;
    },
);

#-----------------------------------------------------------
#---------------------- METHODS ----------------------------
#-----------------------------------------------------------

sub _build_data_files {
    my $self = shift;

    my $data_path = $self->data;

    unless ( -d $data_path ) {
	    $self->WARN("Data directory not found or $data_path not a directory");
	    unless ( $self->{commandline}->{file} ) {
		    $self->ERROR("Data path or -f option must be used.");
	    }
    }

    my @file_path_list;
    if ( $data_path ) {	
	    unless ( $data_path =~ /\/$/ ) {
		    $data_path =~ s/$/\//;
	    }

	    #update path data
	    $self->{data} = $data_path;

	    ## check for output directory.
	    ## or add default.
	    if ( ! $self->main->{output} ) {
		    $self->main->{output} = $data_path;
	    }
	    elsif ( $self->main->{output} ) {
		    my $out = $self->main->{output};
		    unless ( $out =~ /\/$/ ) {
			    $out =~ s/$/\//;
			    $self->main->{output} = $out;
		    }
	    }

	    my $DIR = IO::Dir->new($data_path);
	    foreach my $file ( $DIR->read ) {
		    chomp $file;
		    next if ( -d $file );
		    push @file_path_list, "$data_path$file";
	    }
	    $DIR->close;
    }

    ## file from the command line.
    if ( $self->{commandline}->{file} ) {
	    @file_path_list = read_lines($self->{commandline}->{file});

	    if ( ! $self->main->{output} ) {
		    my ( $name,$path ) = fileparse($file_path_list[0]);
		    $self->main->{output} = $path;
	    }
	    elsif ( $self->main->{output} ) {
		    my $out = $self->main->{output};
		    unless ( $out =~ /\/$/ ) {
			    $out =~ s/$/\//;
			    $self->main->{output} = $out;
		    }
	    }	
    }
    my @sorted_files = sort @file_path_list;

    if ( ! @sorted_files ) {
	    $self->ERROR("data path or -f option not found.");
    }
    $self->{start_files} = \@sorted_files;

    ## make individual stacks
    $self->_build_individuals if $self->individuals;

    return;
}

#-----------------------------------------------------------

sub _build_individuals {
	my $self = shift;
	my $files = $self->{start_files};

	my %individuals;
	foreach my $data ( @{$files}) {
		chomp $data;
		my $filename = fileparse($data);
		my @elm = split /_/, $filename;
		$individuals{$elm[0]}++;
	}
	$self->{individuals} = \%individuals;
	return;
}

#-----------------------------------------------------------

sub _build_config {
    my $self = shift;

    my $config = $self->commandline->{config};
    $self->ERROR('config file required') unless $config;

    read_config $config => my %config;
    $self->config( \%config );
}

#-----------------------------------------------------------

sub tool_options {
    my ( $self, $tool ) = @_;
    return $self->config->{$tool};
}

#-----------------------------------------------------------

sub timestamp {
    my $self = shift;
    my $time = localtime;
    return $time;
}

#-----------------------------------------------------------

sub WARN {
    my ( $self, $message ) = @_;
    print STDOUT "[WARN] $message\n";
    return;
}

#-----------------------------------------------------------

sub ERROR {
	my ( $self, $message ) = @_;
	open (my $ERROR, '>>', 'FATAL.log');

	say $ERROR $self->timestamp, "[ERROR] $message";
	say "Fatal error occured please check FATAL.log file";
	$ERROR->close;
	die;
}

#-----------------------------------------------------------

sub LOG {
    my ( $self, $type, $message ) = @_;
    $message //= 'Pipeline';

    my @time = split /\s+/, $self->timestamp;
    my $log_time = "$time[1]_$time[2]_$time[4]";
    my $default_log = 'UGPp_UCGD_Pipeline.GVCF.' . $self->VERSION . "_$log_time-log.txt";

    my $log_file = $self->main->{log} || $default_log;
    $self->{log_file} = $log_file;
    my $LOG = IO::File->new( $log_file, 'a+' );

    if ( $type eq 'config' ) {
        print $LOG "-" x 55;
        print $LOG "\n----- UGP Pipeline -----\n";
        print $LOG "-" x 55;
        print $LOG "\nRan on ", $self->timestamp;
        print $LOG "\nUsing the following programs:\n";
        print $LOG "\nUGP Pipeline Version: ", $self->VERSION, "\n";
        print $LOG "BWA: " . $self->main->{bwa_version},               "\n";
        print $LOG "GATK: " . $self->main->{gatk_version},             "\n";
        print $LOG "SamTools: " . $self->main->{samtools_version},     "\n";
        print $LOG "Samblaster: " . $self->main->{samblaster_version}, "\n";
        print $LOG "Sambamba: " . $self->main->{sambamba_version},     "\n";
        print $LOG "FastQC: " . $self->main->{fastqc_version},         "\n";
        print $LOG "Tabix: " . $self->main->{tabix_version},           "\n";
        print $LOG "WHAM: " . $self->main->{wham_version},           "\n";
        print $LOG "-" x 55, "\n";
    }
    elsif ( $type eq 'start' ) {
        print $LOG "Started process $message at ", $self->timestamp, "\n";
    }
    elsif ( $type eq 'cmd' ) {
        print $LOG "command started at ", $self->timestamp, " ==> @$message\n"
          if $self->engine eq 'cluster';
        print $LOG "command started at ", $self->timestamp, " ==> $message\n"
          if $self->engine eq 'server';
    }
    elsif ( $type eq 'finish' ) {
        print $LOG "Process finished $message at ", $self->timestamp, "\n";
        print $LOG "-" x 55, "\n";
    }
    elsif ( $type eq 'progress' ) {
        my $PROG = IO::File->new( 'PROGRESS', 'a+' );
        print $PROG "$message:complete\n";
        $PROG->close;
    }
    else {
        $self->ERROR("Requested LOG message type unknown\n");
    }
    $LOG->close;
    return;
}

#-----------------------------------------------------------
=cut
sub file_store {
    my ( $self, $file, $override ) = @_;

    my $caller = ( caller(1) )[3];
    my ( $class, $method ) = split "::", $caller;

    # override of method to allow you to push file downstream
    # without changing all forward calls.
    $method = $override if $override;

    push @{ $self->{file_store}{$method} }, $file;
    return;
}
=cut

sub file_store {
    my ( $self, $file ) = @_;

    my $caller = ( caller(1) )[3];
    my ( $class, $method ) = split "::", $caller;

    push @{ $self->{file_store}{$method} }, $file;
    return;
}

#-----------------------------------------------------------

sub file_retrieve {
	my ( $self, $class, $exact) = @_;

	if ( ! $class ) {
		return $self->{start_files};
	}
	if ( $class ) {
		if ( $self->{file_store}{$class} ) {
			my $copy = dclone( $self->{file_store} );
			return $copy->{$class};

		}
		else {
			( $exact ) ? (return) : (return $self->{start_files});
		}
	}





=cut
# first step of pipeline will have no data.
    # if not from commandline
    if ( ! $self->{commandline}->{file} and ! $class ) {
        return $self->{start_files};
    }

    # self discovery for first step
    # of the pipeline
    unless ($class) {
        my $caller = ( caller(1) )[3];
        my @caller = split "::", $caller;
        $class = $caller[1];
    }

    if ( $self->{commandline}->{file} ) {
        $self->_make_store($class);
        $self->file_from_command('1');
        delete $self->{commandline}->{file};
        return $self->{file_store}{$class};
    }

    if ( $self->{file_store}{$class} ) {
        my $copy = dclone( $self->{file_store} );
        return $copy->{$class};
    }
=cut

}

#-----------------------------------------------------------

sub _make_store {
	my ( $self, $class ) = @_;
	my $list = $self->{commandline}->{file};

	open( my $FH, '<', $list) 
		or $self->ERROR("File $list can not be opened");

	foreach my $file (<$FH>) {
		chomp $file;
		push @{ $self->{file_store}{$class} }, $file;
	}
	$FH->close;
	return;
}

#-----------------------------------------------------------

1;
