package Base;
use Moo;
use Config::Std;
use File::Basename;
use IO::Dir;
use Storable qw(dclone);

#-----------------------------------------------------------
#---------------------- ATTRIBUTES -------------------------
#-----------------------------------------------------------

has VERSION => (
    is      => 'ro',
    default => sub { '1.3.0' },
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

    unless ( -e $data_path ) {
        $self->WARN("Data directory not found our not used");
        return;
    }

    unless ( $data_path =~ /\/$/ ) {
        $data_path =~ s/$/\//;
    }

    #update path data
    $self->{data} = $data_path;

    #check for output directory.
    if ( !$self->main->{output} ) {
        $self->main->{output} = $data_path;
    }
    elsif ( $self->main->{output} ) {
        my $out = $self->main->{output};
        unless ( $out =~ /\/$/ ) {
            $out =~ s/$/\//;
            $self->main->{output} = $out;
        }
    }

    my @file_info = fileparse($data_path);
    my $DIR       = IO::Dir->new($data_path);

    my @file_path_list;
    foreach my $file ( $DIR->read ) {
        chomp $file;
        next if ( -d $file );
        push @file_path_list, "$file_info[1]$file_info[0]$file";
    }

    $self->ERROR("Required files not found in $data_path")
      unless (@file_path_list);
    my @sorted_files = sort @file_path_list;

    # store the begining file list in object
    $self->{start_files} = \@sorted_files
      unless $self->{commandline}->{file};

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
    print STDOUT $message, "\n";
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

    my $log_file = $self->main->{log} || 'capture-cmds.txt';
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
        print $LOG "command started at ", $self->timestamp, " ==> @$message\n";
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

#TODO
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
    my ( $self, $file, $override ) = @_;

    my $caller = ( caller(1) )[3];
    my ( $class, $method ) = split "::", $caller;

    # override of method to allow you to push file downstream
    # without changing all forward calls.
    $method = $override if $override;

    push @{ $self->{file_store}{$method} }, $file;
    ##unless $file ~~ [ values %stored ];
    return;
}

#-----------------------------------------------------------

sub file_retrieve {
    my ( $self, $class ) = @_;

    # first step of pipeline will have no data.
    # if not from commandline
    unless ($class) {
        return $self->{start_files};
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
}

#-----------------------------------------------------------

sub _make_store {
    my ( $self, $class ) = @_;
    my $list = $self->{commandline}->{file};

    my $FH = IO::File->new($list)
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
