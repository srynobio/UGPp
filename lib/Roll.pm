package Roll;
use Moo;
use Config::Std;
use File::Basename;
use Storable qw(dclone store retrieve);
use IO::Dir;
use Carp;
use feature 'state';

state %stored;

#-----------------------------------------------------------
#---------------------- ATTRIBUTES -------------------------
#-----------------------------------------------------------

has VERSION => (
    is      => 'ro',
    default => sub { '1.2.1' },
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

has programs => (
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
        my $workers = $self->config->{main}->{workers} || '1';
        return $workers if 'auto';
        return $workers + 1;
    },
);

has execute => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->commandline->{run};
    },
);

#-----------------------------------------------------------
#---------------------- METHODS ----------------------------
#-----------------------------------------------------------

sub _build_data {
    my $self = shift;

    my $data_path = $self->data;

    unless ( -e $data_path ) {
        $self->WARN("Data directory not found our not used");
        return;
    }

    unless ( $data_path =~ /\/$/ ) {
        $data_path =~ s/$/\//;
    }

    my @file_info = fileparse($data_path);
    my $DIR       = IO::Dir->new($data_path);

    my @file_path_list;
    foreach my $file ( $DIR->read ) {
        chomp $file;
        next if ( -d $file );
        push @file_path_list, "$file_info[1]$file_info[0]$file";
    }
    my @sorted_files = sort @file_path_list;

    $self->{file_path_list} = \@sorted_files;

    $DIR->close;
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
	my ($self, $tool ) = @_;
	return $self->config->{$tool};
}

#-----------------------------------------------------------

sub next {
    my $self = shift;
    return shift @{ $self->{file_path_list} };
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
    print STDOUT carp "$message\n";
    return;
}

#-----------------------------------------------------------

sub ERROR {
    my ( $self, $message ) = @_;
    my $ERROR = IO::File->new( 'FATAL.log', 'a+' );

    print $ERROR $self->timestamp, ": $message\n";
    print "Fatal error occured please check log file\n";
    $ERROR->close;
    die;
}

#-----------------------------------------------------------

sub LOG {
    my ( $self, $type, $message ) = @_;
    $message //= 'Pipeline';

    my $log_file = $self->main->{log} || 'cApTUrE-cmds.txt';
    my $LOG = IO::File->new( $log_file, 'a+' );

    if ( $type eq 'config' ) {
        print $LOG "-" x 55;
        print $LOG "\n----- UGP Pipeline -----\n";
        print $LOG "-" x 55;
        print $LOG "\nRan on ", $self->timestamp;
        print $LOG "\nUsing the following programs:\n";
        print $LOG "\nUGP Pipeline Version: ", $self->VERSION, "\n";
        print $LOG "BWA: " . $self->main->{bwa_version},           "\n";
        print $LOG "Picard: " . $self->main->{picard_version},     "\n";
        print $LOG "GATK: " . $self->main->{gatk_version},         "\n";
        print $LOG "SamTools: " . $self->main->{samtools_version}, "\n";
        print $LOG "-" x 55, "\n";
    }
    elsif ( $type eq 'start' ) {
        print $LOG "Started process $message at ", $self->timestamp, "\n";
    }
    elsif ( $type eq 'cmd' ) {
        print $LOG "command started at ", $self->timestamp, " ==> $message\n";
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

sub QC_report {
    my ( $self, $message ) = @_;
    my $caller = ( caller(1) )[3];

    my $QC = IO::File->new( 'QC-report.txt', 'a+' );

    $self->ERROR("QC_report message must be arrayref\n")
      if ( ref $message ne 'ARRAY' );

    print $QC "# ==== Quality Info from $caller ====#\n";
    map { print $QC $_, "\n" } @$message;
    print $QC "-" x 55, "\n";

    $QC->close;
    return;
}

#-----------------------------------------------------------

sub file_store {
    my ( $self, $file ) = @_;

    my $caller = ( caller(1) )[3];
    my ( $class, $method ) = split "::", $caller;
    push @{ $stored{$method} }, $file unless $file ~~ [ values %stored ];
    return;
}

#-----------------------------------------------------------

sub file_retrieve {
    my ( $self, $class ) = @_;
    $self->ERROR("Method file_retrieve must have request class")
      unless $class;

    if ( $self->{commandline}->{file} and !-e 'CMD_stack.store' ) {
        `touch CMD_stack.store`;
        $self->_make_storable($class);
        return $stored{$class};
    }

    unless ( keys %stored ) {
        $self->ERROR( 'Must have stack store file or pass file (-f) list in. '
              . ' Are you sure you have entered data path in config file?' )
          if ( !-e 'CMD_stack.store' );

        my $stack = retrieve('CMD_stack.store');
        %stored = %{$stack};
        return $stored{$class};
    }
    else {

        # just return a clone of the store so
        # original is not deleted
        my $clone;
        if ( $stored{$class} ) {
            $clone = dclone( $stored{$class} );
        }
        else {
            $clone = undef;
        }
        return $clone;
    }
}

#-----------------------------------------------------------

sub _make_storable {
    my ( $self, $class ) = @_;
    my $list = $self->{commandline}->{file};

    my $FH = IO::File->new($list)
      or $self->ERROR("Given File $list can not be opened or corrupt");

    foreach my $file (<$FH>) {
        chomp $file;
        push @{ $stored{$class} }, $file if $file;
    }
    $FH->close;
    return;
}

#-----------------------------------------------------------

sub DEMOLISH {
    my $self = shift;
    store \%stored, 'CMD_stack.store';
}

#-----------------------------------------------------------
1;
