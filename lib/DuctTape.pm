package DuctTape;
use Moo;
use IPC::System::Simple qw|run|;
use Config::Std;
use File::Basename;
use IO::File;
use MCE;

extends qw|
  FastQC
  Picard
  SamTools
  GATK
  BWA
  |;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

has equal_dash => (
    is     => 'rwp',
    reader => 'equal_dash',
);

has no_dash => (
    is     => 'rwp',
    reader => 'no_dash',
);

has dash => (
    is     => 'rwp',
    reader => 'dash',
);

has ddash => (
    is     => 'rwp',
    reader => 'ddash',
);

has options => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{options};
    }
);

has output => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->{options}->{output};
    },
);

has engine => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->commandline->{engine};
    },
);

##-----------------------------------------------------------
##---------------------- METHODS ----------------------------
##-----------------------------------------------------------

sub wrap {
    my $self = shift;

    my $PROG;
    my %progress_list;
    my $steps = $self->order;

    if ( $self->execute ) {
        $self->LOG('config');

        if ( -e 'PROGRESS' and -s 'PROGRESS' ) {
            my @progress = `cat PROGRESS`;
            chomp @progress;

            map {
                my @prgs = split ":", $_;
                $progress_list{ $prgs[0] } = 'complete'
                  if ( $prgs[1] eq 'complete' );
            } @progress;
        }
    }

    # collect the cmds on stack.
    my @cmd_stack;
    foreach my $sub ( @{$steps} ) {
        chomp $sub;
        next if ( $progress_list{$sub} and $progress_list{$sub} eq 'complete' );

        eval { $self->$sub };
        if ($@) { $self->ERROR("Error when calling $sub: $@") }

        if ( !$self->execute ) {
            map { print "Review of command[s] from: $sub => $_\n" }
              @{ $self->{cmd_list}->{$sub} };
        }
        elsif ( $self->engine eq 'MCE' ) {
            $self->_MCE_engine;
        }
        elsif ( $self->engine eq 'cluster' ) {
            $self->_cluster;
        }
    }
    return;
}

##-----------------------------------------------------------

sub pull {
    my $self = shift;

    # setup the data information in object.
    $self->_build_data;

    # get caller info to build opts.
    my $caller = ( caller(1) )[3];
    my ( $package, $sub ) = split /::/, $caller;

    # get options from caller config section.
    my $opts = $self->config->{$sub};
    $self->option_dash($opts);

    #collect software for caller
    my $path = $self->programs->{$package};
    my %programs = ( $package => $path );

    # for caller ease, return one large hashref.
    my %options = ( %{ $self->main }, %programs );
    my $tidy_opts = $self->option_tidy( \%options );

    $self->{options} = $tidy_opts;
    return $self;
}

##-----------------------------------------------------------

sub bundle {
    my ( $self, $cmd, $record) = @_;
    $record //= 'on';

    # get caller info to create log file.
    my $caller = ( caller(1) )[3];
    my ( $package, $sub ) = split /::/, $caller;

    my $log = "$sub.log";

    # what type of call
    my $call_type = ref $cmd;
    unless ( $call_type and $call_type ne 'HASH' ) {
        $self->ERROR( 
		"bundled command from $sub command must be an scalar or array reference."
        );
    }

    # place in list and add log file;
    my @cmds;
    if ( ref $cmd eq 'ARRAY' ) {
        @cmds = @{$cmd};
    }
    else { @cmds = $$cmd; }
    chomp @cmds;

    #collect all the cmd in object
#    if ( $self->options->{run_log} eq 'TRUE' ) {

    if ( $record eq 'off' ) {
       push @{ $self->{cmd_list}->{$sub} }, @cmds;
    }
    else { 
    	my @add_log = map { "$_ &> $log" } @cmds;
    	push @{ $self->{cmd_list}->{$sub} }, @add_log;
    }
    return;
}

##-----------------------------------------------------------

sub software {
    my $self = shift;
    return $self->programs;
}

##-----------------------------------------------------------

sub option_dash {
    my ( $self, $opts ) = @_;

	$opts //= {};

    my ( $no_dash, $dash, $double_dash, $equal_dash );

	# added this section so when $opts->"dash" 
	# is call it does not fail.
	unless ( $opts) {
		$equal_dash  = '';
            	$no_dash     = ''; 
            	$dash        = '';
            	$double_dash = '';
	}	

    foreach my $i ( keys %{$opts} ) {
        next unless $opts->{$i};
        if ( $opts->{$i} eq 'TRUE' ) {
            delete $opts->{$i};
            $equal_dash  .= "$i ";
            $no_dash     .= "$i ";
            $dash        .= "-$i ";
            $double_dash .= "--$i ";
            next;
        }

        # value or placeholder
        $equal_dash  .= "$i=$opts->{$i} ";
        $no_dash     .= "$i $opts->{$i} ";
        $dash        .= "-$i $opts->{$i} ";
        $double_dash .= "--$i $opts->{$i} ";
    }
    $self->_set_equal_dash($equal_dash);
    $self->_set_no_dash($no_dash);
    $self->_set_dash($dash);
    $self->_set_ddash($double_dash);
    return;
}

##-----------------------------------------------------------

sub option_tidy {
    my ( $self, $opt_hash ) = @_;

    while ( my ( $key, $value ) = each %{$opt_hash} ) {

        #add trailing slash to data
        unless ( $opt_hash->{data} =~ /\/$/ ) {
            $opt_hash->{data} =~ s/$/\//;
        }

        # if not output use data directory
        unless ( $opt_hash->{'output'} ) {
            $opt_hash->{output} = $opt_hash->{data};
        }

        # add trailing slash to output.
        unless ( $opt_hash->{output} =~ /\/$/ ) {
            $opt_hash->{output} =~ s/$/\//;
        }
    }
    return $opt_hash;
}

##-----------------------------------------------------------

sub file_frags {
    my ( $self, $file, $divider ) = @_;
    $divider //= '_';

    my ( $name, $path, $suffix ) = fileparse($file);

    my @file_parts = split( $divider, $name );

    my $result = {
        full  => $file,
        name  => $name,
        path  => $path,
        parts => \@file_parts,
    };
    return $result;
}

##-----------------------------------------------------------

sub _MCE_engine {
    my $self = shift;

    # add the parent process id if error occurs.
    $self->{pid} = $$;

    unless ( keys %{ $self->{cmd_list} } ) { return }
    my %stack = %{ $self->{cmd_list} };
    my ( $sub, $stack_data ) = each %stack;

    $self->LOG( 'start', $sub );

    my $mce = MCE->new(
        max_workers  => $self->cpu,
        user_func    => \&_MCE_run,
        input_data   => $stack_data,
        on_post_exit => \&_MCE_error_kill,
        user_args    => { 'ducttape' => $self },
    );
    $mce->run;
    $self->LOG( 'finish',   $sub );
    $self->LOG( 'progress', $sub );

    map { delete $self->{cmd_list}->{$_} } keys %stack;
    return;
}

##-----------------------------------------------------------

sub _MCE_run {
    my ( $mce, $chunk_ref, $chunk_id ) = @_;
    my $tape = $mce->{user_args}->{ducttape};

    foreach my $step ( @{$chunk_ref} ) {
        $tape->LOG( 'cmd', $step );
        eval { run($step) };
        if ($@) {
            $tape->ERROR("ERROR running command: $@");
            MCE->shutdown;
            MCE->exit( 0, 'failed run engine shutting down' );
        }
    }
    return;
}

##-----------------------------------------------------------

sub _MCE_error_kill {
    my ( $mce, $e ) = @_;
    my $tape = $mce->{user_args}->{ducttape};

    my $parent_id = $tape->{pid};
    my $mce_id    = $e->{pid};
    `kill -9 $parent_id $mce_id`;
}

##-----------------------------------------------------------

sub _cluster {
    my $self = shift;

    unless ( keys %{ $self->{cmd_list} } ) { return }
    my %stack = %{ $self->{cmd_list} };
    my ( $sub, $stack_data ) = each %stack;

    $self->LOG( 'start', $sub );

    my $id = 1;
    my @qsubs;
    foreach my $step ( @{$stack_data} ) {
        my $tmp = "$sub" . "_" . $id . ".pbs";

        $self->LOG( 'cmd', $step );

        my $PBS = IO::File->new( $self->{main}->{pbs_template}, 'r' )
          or $self->ERROR('Can not open PBS template file or not found');

        my $RUN = IO::File->new( $tmp, 'w' )
          or $self->ERROR('Can not create needed pbs file [cluster]');

        map { print $RUN $_ } <$PBS>;
        print $RUN $step, "\n";

        push @qsubs, $tmp;
        $id++;

        $RUN->close;
        $PBS->close;
    }

    if ( -e 'launch.index' ) {
        my @jobs = `cat launch.index`;
        `rm launch.index`;

        my @before;
        foreach my $i (@jobs) {
            chomp $i;
            push @before, $i;
        }
        my $wait = join( ":", @before );

        foreach my $launch (@qsubs) {
            print "qsub -W depend=afterok:$wait $launch\n";
            system "qsub -W depend=afterok:$wait $launch &>> launch.index";
        }
    }
    else {
        foreach my $launch (@qsubs) {
            print "qsub $launch &>> launch.index\n";
            system "qsub $launch &>> launch.index";
        }
    }
    map { delete $self->{cmd_list}->{$_} } keys %stack;
    $self->LOG( 'finish',   $sub );
    $self->LOG( 'progress', $sub );
    sleep(10);
    return;
}

=cut
sub _cluster {
	my $self = shift;

	mkdir('cmd_tmp') unless ( -d 'cmd_tmp');
	mkdir('pbs_tmp') unless ( -d 'pbs_tmp');

	unless ( keys %{$self->{cmd_list}} ) { return }
	my %stack = %{ $self->{cmd_list} };
	my ($sub, $stack_data) = each %stack; 

	my @qsubs;
	{
		# command creation section
		my $cmd_file = "cmd_tmp/$sub-cmd.tmp";
		
		my $CMD = IO::File->new($cmd_file, 'w')
			or $self->ERROR("Can not create needed command file");

		$self->LOG('start', $sub);

		map { print $CMD $_, "\n" } @{$stack_data};

		my $cmd = "mpiexec -np 2 capture_tools/mpi.code $cmd_file";


		# PBS creation section
		my $pbs_job = "pbs_tmp/$sub.pbs";

		my $PBS = IO::File->new($self->{main}->{pbs_template}, 'r')
			or $self->ERROR('Can not open PBS template file or not found');

		my $TMP = IO::File->new($pbs_job, 'w') 
			or $self->ERROR('Can not create needed pbs file [cluster]');

		map { print $TMP $_ } <$PBS>;
		print $TMP $cmd, "\n";

		push @qsubs, $pbs_job;
	}

	if ( -e 'launch.index' ) {
		my @jobs = `cat launch.index`;
		`rm launch.index`;

		my @before;
		foreach my $i (@jobs) {
			chomp $i;
			push @before, $i;
		}
		my $wait = join( ":", @before );

		foreach my $launch (@qsubs) {
			print "qsub -W depend=afterok:$wait $launch\n";
			system "qsub -W depend=afterok:$wait $launch &>> launch.index";
		}
	}
	else {
		foreach my $launch (@qsubs) {
			print "Submitting job:  $launch\n";
			
			$self->LOG('cmd', "qsub $launch");
			#system "qsub $launch &>> launch.index";
		}
	}
	$self->LOG('finish', $sub);
	$self->LOG('progress', $sub);
	sleep(10);

	map { delete $self->{cmd_list}->{$_} } keys %stack;
	return;
}
=cut

##-----------------------------------------------------------
1;
