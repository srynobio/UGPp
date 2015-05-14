package UGP;
use Moo;
use IPC::System::Simple qw|run|;
use Config::Std;
use File::Basename;
use Parallel::ForkManager;
use IO::File;

extends 'Base';

with qw|
  BWA
  FastQC
  SamTools
  Sambamba
  GATK
  QC
  ClusterUtils
  |;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

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

has 'slurm_template' => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->commandline->{slurm_template};
    },
);

has 'log_path' => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return unless ( $self->commandline->{log_path} );

        my $path = $self->commandline->{log_path};

        if ( $path =~ /\/$/ ) { return $path }
        else {
            $path =~ s/$/\//;
            return $path;
        }
    },
);

has qstat_limit => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        my $limit = $self->commandline->{qstat_limit} || '10';
        return $limit;
    },
);

##-----------------------------------------------------------
##---------------------- METHODS ----------------------------
##-----------------------------------------------------------

sub UGP_Pipeline {
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
            delete $self->{bundle};
            next;
        }

        # print stack for review
        if ( !$self->execute ) {
            my $stack = $self->{bundle};
            map { print "Review of command[s] from: $sub => @$_[0]\n" }
              @{ $stack->{$sub} };
            delete $stack->{$sub};
            next;
        }
        if ( $self->engine eq 'server' ) {
            $self->_server;
        }
        elsif ( $self->engine eq 'cluster' ) {
            $self->_cluster;
        }
    }
    return;
}

#-----------------------------------------------------------

sub pull {
    my $self = shift;

    # setup the data information in object.
    $self->_build_data_files;

    # get caller info to build opts.
    my $caller = ( caller(1) )[3];
    my ( $package, $sub ) = split /::/, $caller;

    #collect software for caller
    my $path = $self->software->{$package};
    my %programs = ( $package => $path );

    # for caller ease, return one large hashref.
    my %options = ( %{ $self->main }, %programs );

    $self->{options} = \%options;
    return $self;
}

##-----------------------------------------------------------

sub bundle {
    my ( $self, $cmd ) = @_;

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

    my $id;
    foreach my $cmd ( @{$cmd} ) {

        #foreach my $cmd ( @{$cmd} ) {

        if ( $cmd->[0] ) {
            my $log     = "$sub.log-" . ++$id;
            my $add_log = $cmd->[0] . " 2> $log";
            $cmd->[0] = $add_log;
        }
    }

    # place in list and add log file;
    my @cmds;
    if ( ref $cmd eq 'ARRAY' ) {
        ##if ( ref $cmd eq 'array' ) {
        @cmds = @{$cmd};
    }
    else { @cmds = [$$cmd] }
    chomp @cmds;

    # add to object
    $self->{bundle}{$sub} = \@cmds;

    return;
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

sub _server {
    my $self = shift;
    my $pm   = Parallel::ForkManager->new( $self->workers );

    # command information .
    my @sub      = keys %{ $self->{bundle} };
    my @stack    = values %{ $self->{bundle} };
    my @commands = map { @$_ } @stack;

    # first pass check
    unless (@commands) {
        $self->ERROR("No commands found, review steps");
    }

    # print to log.
    $self->LOG( 'start', $sub[0] );

    # run the stack.
    my $status = 'run';
    while (@commands) {
        my $cmd = shift(@commands);

        $self->LOG( 'cmd', $cmd->[0] );
        $pm->start and next;
        eval { run( $cmd->[0] ); };
        if ($@) {
            $self->ERROR("Error occured running command: $@\n");
            $status = 'die';
            die;
        }
        $pm->finish;
    }
    $pm->wait_all_children;

    # die on errors.
    die if ( $status eq 'die' );

    $self->LOG( 'finish',   $sub[0] );
    $self->LOG( 'progress', $sub[0] );

    delete $self->{bundle};
    return;
}

##-----------------------------------------------------------

sub _cluster {
    my $self = shift;

    # command information.
    my @sub      = keys %{ $self->{bundle} };
    my @stack    = values %{ $self->{bundle} };
    my @commands = map { @$_ } @stack;

    return if ( !@commands );

    # jobs per node per step
    my $jpn = $self->config->{ $sub[0] }->{jpn} || '1';

    # get nodes selection from config file
    my $opts = $self->tool_options( $sub[0] );
    my $node = $opts->{node} || 'ucgd';

    $self->LOG( 'start', $sub[0] );

    my $id;
    my ( @parts, @copies, @slurm_stack );
    while (@commands) {
        my $tmp = $sub[0] . "_" . ++$id . ".sbatch";

        my $RUN = IO::File->new( $tmp, 'w' )
          or $self->ERROR('Can not create needed slurm file [cluster]');

        # don't go over total file amount.
        if ( $jpn > scalar @commands ) {
            $jpn = scalar @commands;
        }

        # get the right collection of files
        @parts = splice( @commands, 0, $jpn );

        # write out the commands not copies.
        map { $self->LOG( 'cmd', $_ ) } @parts;

        # call to create sbatch script.
        my $batch = $self->$node( \@parts, $sub[0]);

        print $RUN $batch;
        push @slurm_stack, $tmp;
        $RUN->close;
    }

    my $running = 0;
    foreach my $launch (@slurm_stack) {
        if ( $running >= $self->qstat_limit ) {
            my $status = $self->_jobs_status;
            if ( $status eq 'add' ) {
                $running--;
                redo;
            }
            elsif ( $status eq 'wait' ) {
                sleep(10);
                redo;
            }
        }
        else {
            system "sbatch $launch &>> launch.index";
            $running++;
            next;
        }
    }

    # give sbatch system time to start
    sleep(60);

    # check the status of current sbatch jobs
    # before moving on.
    $self->_wait_all_jobs;

    `rm launch.index`;

    delete $self->{bundle};
    $self->LOG( 'finish',   $sub[0] );
    $self->LOG( 'progress', $sub[0] );
    return;
}

##-----------------------------------------------------------

sub _jobs_status {
    my $self  = shift;
    my $state = `squeue -u u0413537|wc -l`;

    if ( $state >= $self->qstat_limit ) {
        return 'wait';
    }
    else {
        return 'add';
    }
}

##-----------------------------------------------------------

sub _wait_all_jobs {
    my $self   = shift;
    my @indexs = `cat launch.index`;
    chomp @indexs;

    foreach my $job (@indexs) {
        my @parts = split /\s/, $job;

      LINE:
        my $state = `scontrol show job $parts[-1] |grep 'JobState'`;
        if ( $state =~ /(RUNNING|PENDING)/ ) {
            sleep(60);
            goto LINE;
        }
        else { next }
    }
    return;
}

##-----------------------------------------------------------
1;
