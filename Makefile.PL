use 5.008003;
use warnings;
use strict;
use ExtUtils::MakeMaker;


WriteMakefile(
    PL_FILES         => {},
    MIN_PERL_VERSION => '5.008003',
    LICENSE          => 'perl',
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
              type => 'git',
              web  => 'https://github.com/kuerbis/Term-Choose_HAE',
              url  => 'https://github.com/kuerbis/Term-Choose_HAE.git',
            },
        },
    },
    AUTHOR           => 'Matthaeus Kiem <cuer2s@gmail.com>',
    NAME             => 'Term::Choose_HAE',
    ABSTRACT_FROM    => 'lib/Term/Choose_HAE.pm',
    VERSION_FROM     => 'lib/Term/Choose_HAE.pm',
    EXE_FILES        => [],
    BUILD_REQUIRES   => {
        'File::Spec::Functions' => 0,
        'FindBin'               => 0,
        'Test::More'            => 0,
        'Test::Fatal'           => 0,
    },
    PREREQ_PM => {
        'strict'                  => 0,
        'warnings'                => 0,
        'Exporter'                => 0,
        'Term::Choose'            => '1.204',
        'Unicode::GCString'       => 0,
        'Text::ANSI::WideUtil'    => 0,
    },
    test  => {
        TESTS => 't/*/*.t',
    },
    dist  => {
        COMPRESS => 'gzip',
        SUFFIX   => '.gz',
        TARFLAGS => '--format=gnu -cvf',
    },
    clean => {
        FILES => 'Term-Choose_HAE-*',
    },
);
