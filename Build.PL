use 5.010;
use strict;
use warnings FATAL => 'all';
use Module::Build;
use Getopt::Long;
my $install      = 0;
my $dist         = 0;
my $help         = 0;
my $meta         = 0;
my $orgcondition = 0;
GetOptions(
    'h|help'               => \$help,
    'i|install'            => \$install,
    'd|dist'               => \$dist,
    'm|meta'               => \$meta,
    'o|original-condition' => \$orgcondition,
);
my $builder = Module::Build->new(
    module_name       => 'store',
    license           => 'Perl_5',
    dist_author       => q{Heiko Klausing <h.klausing@gmx.de>},
    dist_abstract     => 'Backup and Restore tools based on rsync-backup',
    dist_version_from => 'script/store.pl',
    create_readme     => 0,                                                                 # do not touch the existing README
    sign              => 0,                                                                 # no signature is required
    release_status    => 'stable',
    configure_requires => {    # Modules must be installed before running the Build.PL script.
        'Module::Build' => '0.40',
    },
    build_requires => {        # necessary to build and install, but not necessary for regular usage
#       'Test::File'   => '1.34',
        'Test::More'   => '0.98',
        'Test::Output' => '1.02',
        'Test::Pod'    => '1.48',
#       'Test::Warn'   => '0.24',
    },
    requires => {              # specifies any module prerequisites that the current module depends on.
        'Carp'                    => '1.32',
        'English'                 => '1.04',
        'File::Basename'          => '2.82',
        'File::Path'              => '2.08_01',
        'Getopt::Long'            => '2.42',
        'perl'                    => '5.14.2',
        'Pod::Usage'              => '1.36',
        'Sys::Hostname'           => '1.18',
        'Term::ANSIColor'         => '3.00',
    },
    script_files => [    # this requires install_path
        'script/store.pl'
    ],
    install_path => {
        'script' => '/usr/local/sbin',
    },
    add_to_cleanup     => ['Makefile', 'store-*', 't/store-html', 't/profile', 'test_results', '*.out', '*.log' ],
    create_makefile_pl => 'traditional',
);

if ($meta) {
    $builder->dispatch('manifest') if (not -f 'MANIFEST');
    $builder->dispatch('distmeta');
} elsif ($dist) {
    $builder->dispatch('manifest') if (not -f 'MANIFEST');
    $builder->dispatch('distmeta');
    $builder->dispatch('build');
    $builder->dispatch('test');
    $builder->dispatch('dist');
    $builder->create_build_script();
} elsif ($install) {
    $builder->dispatch('build');
    $builder->dispatch('test', verbose => 1);
    $builder->dispatch('fakeinstall');
    $builder->create_build_script();
} elsif ($orgcondition) {
    ## put the project to HEAD of repository
    ## delete paths
    foreach my $path ('_build', 'cover_db', 'blib') {
        system("rm -rf $path");
    }
    ## delete files
    foreach my $file ('MANIFEST', 'META.*', 'MYMETA.*', 'Makefile.PL', 'Build', 'store-*.gz') {
        system("rm -f $file");
    }
} elsif ($help) {
    print("\n");
    print("Usage: Build.PL [-h|--help | -m|--meta | -d|--dist | -i|--install | -o|--original-condition]\n");
    print("\n");
} else {
    $builder->create_build_script();
}
# stop script
exit 0;

