package UGP;
use Moo;
use IPC::System::Simple 'run';
use Config::Std;
use File::Basename;
use Parallel::ForkManager;
use IO::File;
use File::Slurper 'read_lines';
use feature 'say';

extends 'Base';

with qw|
  bam2fastq
  bwa
  sambamba
  fastqc
  samtools
  gatk
  tabix
  wham
  clusterUtils
  |;

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

has class_config => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{class_config};
    }
);

has output => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->main->{output};
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

sub pipeline {
    my $self = shift;

    my %progress_list;
    my $steps = $self->order;

    if ( $self->execute ) {
        $self->LOG('config');

        if ( -e 'PROGRESS' and -s 'PROGRESS' ) {
            my @progress = read_lines('PROGRESS');

            map {
                my @prgs = split ":", $_;
                $progress_list{ $prgs[0] } = 'complete'
                  if ( $prgs[1] eq 'complete' );
            } @progress;
        }
    }

    # collect the cmds on stack.
    foreach my $sub ( @{$steps} ) {
        chomp $sub;

        eval { $self->$sub };
        if ($@) {
            $self->ERROR("Error during call to $sub: $@");
        }

        ## next if $sub commands already done.
        if ( $progress_list{$sub} and $progress_list{$sub} eq 'complete' ) {
            delete $self->{bundle};
            next;
        }

        ## print stack for review
        if ( !$self->execute ) {
            my $stack = $self->{bundle};
            map { print "Review of command[s] from: $sub => $_\n" }
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

    $self->{class_config} = \%options;
    return $self;
}

##-----------------------------------------------------------

sub bundle {
    my ( $self, $cmd ) = @_;

    # get caller info to create log file.
    my $caller = ( caller(1) )[3];
    my ( $package, $sub ) = split /::/, $caller;

    # what type of call
    my $ref_type = ref $cmd;
    unless ( $ref_type =~ /(ARRAY|SCALAR)/ ) {
        $self->ERROR("bundle method expects reference to array or scalar.");
    }

    my $id;
    my @cmds;
    if ( $ref_type eq 'ARRAY' ) {
        foreach my $i ( @{$cmd} ) {
            my $log     = "$sub.log-" . ++$id;
            my $add_log = $i . " 2> $log";
            $i = $add_log;
            push @cmds, $i;
        }
    }
    else {
        my $i       = $$cmd;
        my $log     = "$sub.log-" . ++$id;
        my $add_log = $i . " 2> $log";
        $i = $add_log;
        push @cmds, $i;
    }
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
        $self->WARN("No commands found, review steps");
        return;
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

sub node_setup {
    my ( $self, $step ) = @_;

    my $opts = $self->{config}->{$step};
    my $node = $opts->{node} || 'ucgd';

    ## jpn need higher values for default.
    my $jpn;
    if ( $step eq 'fastqforward' ) {
        ( $opts->{jpn} )
          ? ( $jpn = $opts->{jpn} )
          : ( $jpn = '4' );
    }
    else {
        $jpn = $opts->{jpn} || '1';
    }

    return $jpn, $node;
}

##-----------------------------------------------------------

sub _cluster {
    my ( $self, $stack ) = @_;

    # command information.
    my @sub      = keys %{ $self->{bundle} };
    my @stack    = values %{ $self->{bundle} };
    my @commands = map { @$_ } @stack;

    return if ( ! @commands );

    # jobs per node per step
    my $jpn = $self->config->{ $sub[0] }->{jpn} || '1';

    # get nodes selection from config file
    my $opts = $self->tool_options( $sub[0] );
    my $node = $opts->{node} || 'ucgd';

    $self->LOG( 'start', $sub[0] );

    my $id;
    my ( @parts, @copies, @slurm_stack );
    while (@commands) {
        my $slurm_file = $sub[0] . "_" . ++$id . ".sbatch";

        my $RUN = IO::File->new( $slurm_file, 'w' )
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
        my $batch = $self->$node( \@parts, $sub[0] );

        print $RUN $batch;
        push @slurm_stack, $slurm_file;
        $RUN->close;
    }

    open( my $FH, '>>', 'launch.index' );
    my $running = 0;
    foreach my $launch (@slurm_stack) {
        if ( $running >= $self->qstat_limit ) {
            my $status = $self->_jobs_status($node);
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
            print $FH "$launch\t";
            system "sbatch $launch >> launch.index";
            $running++;
            next;
        }
    }

    ## give smaller stacks time to start.
    sleep(60);

    # check the status of current sbatch jobs
    # before moving on.
    $self->_wait_all_jobs($node, $sub[0]);
    $self->_error_check;
    unlink('launch.index');

    delete $self->{bundle};
    $self->LOG( 'finish',   $sub[0] );
    $self->LOG( 'progress', $sub[0] );
    return;
}

##-----------------------------------------------------------

sub _jobs_status {
    my ( $self, $node ) = @_;

    my $partition = $self->_which_node($node);
    my $state = `squeue -A $partition -u u0413537 -h | wc -l`;

    if ( $state >= $self->qstat_limit ) {
        return 'wait';
    }
    else {
        return 'add';
    }
}

##-----------------------------------------------------------

## method used when using preemptable nodes.

sub _relaunch {
    my $self = shift;

    my @error = `grep error *.out`;
    chomp @error;
    if ( !@error ) { return }

    my %relaunch;
    my @error_files;
    foreach my $cxl (@error) {
        chomp $cxl;
        next unless ( $cxl =~ /PREEMPTION/ );

        my @ids = split /\s/, $cxl;

        ## collect error files.
        my ( $sbatch, undef ) = split /:/, $ids[0];
        push @error_files, $sbatch;

        ## record launch id.
        $relaunch{ $ids[4] }++;
    }

    open( my $FH, '>>', 'launch.index' );

    my @indexs = read_lines 'launch.index';
    foreach my $line (@indexs) {
        chomp $line;
        my @parts = split /\s/, $line;

        ## find in lookup and dont re-relaunch.
        if ( $relaunch{ $parts[-1] } ) {
            print $FH "$parts[0]\t";
            system "sbatch $parts[0] >> launch.index";
            $self->WARN("Relaunching job $parts[0]");
        }
    }

    ## remove error files.
    unlink @error_files;
}

##-----------------------------------------------------------

sub _wait_all_jobs {
    my ( $self, $node, $sub) = @_;

    my $process;
    do {
        sleep(60);
        $self->_relaunch;
        sleep(60);
        $process = $self->_process_check( $node, $sub );
    } while ($process);
}

##-----------------------------------------------------------

sub _process_check {
    my ( $self, $node, $sub) = @_;
    my $partition = $self->_which_node($node);

    my @processing = `squeue -A $partition -u u0413537 -h --format=%30j |grep $sub`;
    chomp @processing;
    if ( ! @processing ) { return 0 }
    
    ## check run specific processing.
    ## make lookup of what is running.
    my %running;
    foreach my $active ( @processing ) {
        chomp $active;
        $active =~ s/\s+//g;
        $running{$active}++;
    }

    ## check what was launched.
    open(my $LAUNCH, '<', 'launch.index') 
        or $self->ERROR("Can't find needed launch.index file.");

    my $current = 0;
    foreach my $launched ( <$LAUNCH> ) {
        chomp $launched;
        my @result = split /\t/, $launched;

        if ( $running{$result[0]} ) {
            $current++;
        }
    }
    ($current) ? (return 1) : (return 0);
}

##-----------------------------------------------------------

sub _which_node {
    my ( $self, $node ) = @_;

    if ( $node eq 'ucgd' ) {
        return 'ucgd-kp';
    }
    elsif ( $node eq 'fqf' ) {
        return 'ucgd-kp';
    }
    elsif ( $node eq 'guest' ) {
        return 'owner-guest';
    }
}

##-----------------------------------------------------------

sub _error_check {
    my $self = shift;

    my @error = `grep error *.out`;
    if ( !@error ) { return }

    $self->ERROR("Jobs could not be launch or completed");
}

##-----------------------------------------------------------

1;
