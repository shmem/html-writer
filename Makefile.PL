use 5.020002;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'HTML::Writer',
    VERSION_FROM      => 'lib/HTML/Writer.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
    PREREQ_PM         => {
        'XML::Writer'     => 0,
        'XML::DTDParser'  => 0,
        'LWP::Simple'     => 0,
        'File::Slurp'     => 0,
    }, # e.g., Module::Name => 1.1
    ABSTRACT_FROM     => 'lib/HTML/Writer.pm', # retrieve abstract from module
    AUTHOR            => 'Georg Moritz <shmem@cpan.org>',
    #LICENSE           => 'perl',
    #Value must be from legacy list of licenses here
    #http://search.cpan.org/perldoc?Module%3A%3ABuild%3A%3AAPI
);
