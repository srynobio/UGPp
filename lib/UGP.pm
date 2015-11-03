package UGP;
use Moo;
use IPC::System::Simple qw|run|;
use Config::Std;
use File::Basename;
use Parallel::ForkManager;
use IO::File;
use File::Slurper 'read_lines';
use feature 'say';

extends 'Base';

with qw|
  Bam2Fastq
  BWA
  FastQC
  SamTools
  Sambamba
  GATK
  ClusterUtils
  Tabix
  WHAM
  Utils
  |;

## Master lookup of steps which need to be group called.
my $grouped_called = {
    GenotypeGVCF              => '1',
    CatVariants_Genotype      => '1',
    VariantRecalibrator_SNP   => '1',
    VariantRecalibrator_INDEL => '1',
    ApplyRecalibration_SNP    => '1',
    ApplyRecalibration_INDEL  => '1',
    CombineVariants           => '1',
    bgzip                     => '1',
    tabix                     => '1',
    wham_filter               => '1',
    wham_sort                 => '1',
    wham_merge_indiv          => '1',
    wham_splitter             => '1',
    wham_genotype             => '1',
    wham_genotype_cat         => '1',
    bam_cleanup               => '1',
};

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

        ## next if $sub commands already done.
        next if ( $progress_list{$sub} and $progress_list{$sub} eq 'complete' );

        eval { $self->$sub };
        if ($@) {
            $self->ERROR("Error during call to $sub: $@");
        }
    }

    ## order important here
    ## first run all individuals then group commands.
    $self->launch_cmds('individuals');
    $self->launch_cmds('group');
    return;
}

#-----------------------------------------------------------

sub launch_cmds {
    my ( $self, $step ) = @_;

    my $stack;
    ( $step eq 'individuals' )
      ? ( $stack = $self->{individuals_stack} )
      : ( $stack = $self->{bundle} );

    # print stack for review
    if ( !$self->execute ) {
        foreach my $peps ( keys %{$stack} ) {
            say "Review of command[s] for individual: $peps";
            map { say "\t$_" } @{ $stack->{$peps} };
        }
    }
    else {
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

    ## place in object bundle or individual stack.
    if ( $grouped_called->{$sub} ) {
        $self->{bundle}{$sub} = \@cmds;
    }

    if ( $self->individuals and !$grouped_called->{$sub} ) {
        foreach my $indv ( keys %{ $self->individuals } ) {
            my @found = grep { /$indv/ } @cmds;
            push @{ $self->{individuals_stack}{$indv} }, @found;
        }
    }
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
        my $batch = $self->$node( \@parts, $sub[0] );

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
