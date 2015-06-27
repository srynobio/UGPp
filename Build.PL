## Build.PL
use Module::Build;

print "External dependencies are not installed\n";

my $build = Module::Build->new(
    module_name    => 'UGP',
    license        => 'perl',
    dist_author    => 'Shawn Rynearson <shawn.rynearson@gmail.com>',
    build_requires => {
        'Parallel::ForkManager' => '1.06',
        'Moo'                   => '1.006000',
        'IPC::System::Simple'   => '1.25',
        'Config::Std'           => '0.901',
    },
);

$build->create_build_script();

