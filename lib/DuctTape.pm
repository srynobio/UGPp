package DuctTape;
use Moo;
use IPC::System::Simple qw|run|;
use Config::Std;
use File::Basename;
use IO::File;
use MCE;

extends qw|
  BWA
  FastQC
  Picard
  SamTools
  Sambamba
  GATK
  MD5
  QC
  |;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

=cut
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
=cut

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

has 'jobs_per_node' => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->commandline->{jobs_per_node};
    },
);

has 'pbs_template' => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->commandline->{pbs_template};
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

        eval { $self->$sub };
        if ($@) { $self->ERROR("Error when calling $sub: $@") }

        if ( $progress_list{$sub} and $progress_list{$sub} eq 'complete' ) {
            delete $self->{cmd_list}->{$sub};
            next;
        }

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
    #my $opts = $self->config->{$sub};
    #$self->option_dash($opts);

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
    my ( $self, $cmd, $record ) = @_;
    $record //= 'on';

    # get caller info to create log file.
    my $caller = ( caller(1) )[3];
    my ( $package, $sub ) = split /::/, $caller;

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

    if ( $record eq 'off' ) {
        push @{ $self->{cmd_list}->{$sub} }, @cmds;
    }
    else {

        my $id;
        foreach my $cmd (@cmds) {
            $id++;
            my $log     = "$sub.log" . "-$id";
            my $add_log = "$cmd &> $log";
            push @{ $self->{cmd_list}->{$sub} }, $add_log;
        }
    }
    return;
}

##-----------------------------------------------------------

sub software {
    my $self = shift;
    return $self->programs;
}

##-----------------------------------------------------------

=cut
sub option_dash {
    my ( $self, $opts ) = @_;

    $opts //= {};

    my ( $no_dash, $dash, $double_dash, $equal_dash );

    # added this section so when $opts->"dash"
    # is call it does not fail.
    unless ( keys %{$opts} ) {
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
=cut
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
        max_workers  => $self->workers,
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
            $tape->ERROR("error running command: $@");
            mce->shutdown;
            mce->exit( 0, 'failed run engine shutting down' );
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

    #jobs per node
    my $jpn = $self->jobs_per_node;

    # add the & to end of each command.
    my @appd_runs = map { "$_ &" } @{$stack_data};

    $self->LOG( 'start', $sub );

    my $id;
    my ( @parts, @pbs_stack );
    while (@appd_runs) {
        my $tmp = $sub . "_" . ++$id . ".pbs";

        $self->LOG( 'cmd', $sub );

        my $PBS = IO::File->new( $self->pbs_template, 'r' )
          or $self->ERROR('Can not open PBS template file or not found');

        my $RUN = IO::File->new( $tmp, 'w' )
          or $self->ERROR('Can not create needed pbs file [cluster]');

        # don't go over total file amount.
        if ( $jpn > scalar @appd_runs ) {
            $jpn = scalar @appd_runs;
        }

        @parts = splice( @appd_runs, 0, $jpn );

        map { print $RUN $_ } <$PBS>;
        print $RUN join( "\n", @parts );
        print $RUN "\nwait\n";
        print $RUN "\ndate\n";

        push @pbs_stack, $tmp;

        $PBS->close;
        $RUN->close;
    }

    foreach my $launch (@pbs_stack) {
        system "qsub $launch &>> launch.index";
    }

    sleep(30);
    my @indexs = `cat launch.index`;
    chomp @indexs;

    foreach my $job (@indexs) {
        my @parts = split /\./, $job;

        my $state = `checkjob $parts[0] |grep 'State'`;
      STATE: if ( $state =~ /Running/ ) {
            sleep(60);
            $state = `checkjob $parts[0] |grep 'State'`;
            goto STATE;
        }
        else { next }
    }
    `rm launch.index`;

    map { delete $self->{cmd_list}->{$_} } keys %stack;
    $self->LOG( 'finish',   $sub );
    $self->LOG( 'progress', $sub );
    return;

}

##-----------------------------------------------------------
1;
