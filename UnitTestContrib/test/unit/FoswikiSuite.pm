# Run _all_ test suites in the current directory (core and plugins)
package FoswikiSuite;

require 5.006;
use strict;
use warnings;

use Unit::TestSuite;
use Cwd;
our @ISA = qw( Unit::TestSuite );

# Assumes we are run from the "test/unit" directory

sub list_tests {
    return ();
}

sub include_tests {
    my $this = shift;
    my $here = Cwd::abs_path;
    ($here) = $here =~ m/^(.*)$/;    # untaint
    push( @INC, $here );
    my @list;
    opendir( DIR, "." ) || die "Failed to open .";
    foreach my $i ( sort readdir(DIR) ) {
        next if $i =~ m/^Empty/ || $i =~ m/^\./;
        if ( $i =~ m/^Fn_[A-Z]+\.pm$/ || $i =~ m/^.*Tests\.pm$/ ) {
            push( @list, $i )
              unless $i =~ m/EngineTests\.pm/;

            # the engine tests break logging, so do them last
        }
    }
    closedir(DIR);

    # Add standard extensions tests
    my $read_manifest = 0;
    my $home          = "../..";
    unless ( -e "$home/lib/MANIFEST" ) {
        $home = $ENV{FOSWIKI_HOME};
    }
    require Cwd;
    $home = Cwd::abs_path($home);
    ($home) = $home =~ m/^(.*)$/;    # untaint

    print STDERR "Getting extensions from $home/lib/MANIFEST\n";
    if ( open( F, "$home/lib/MANIFEST" ) ) {
        $read_manifest = 1;
    }
    else {

        # dunno which extensions we require
        $read_manifest = 0;
    }
    if ($read_manifest) {
        local $/ = "\n";
        while (<F>) {
            if (m#^!include ([\w.]+)/.*?/(\w+)$#) {
                my $d = "$home/test/unit/$2";
                next unless ( -e "$d/${2}Suite.pm" );
                push( @list, "${2}Suite.pm" );
                ($d) = $d =~ m/^(.*)$/;
                push( @INC, $d );
            }
        }
        close(F);
    }
    push( @list, "UnitTestContribSuite.pm" );
    push( @INC,  "$here/UnitTestContrib" );
    push( @list, "EngineTests.pm" );

    print STDERR "Running tests from ", join( ', ', @list ), "\n";

    #foreach my $dir ( @INC ) {
    #   print "Checking $dir \n";
    #   Assert::UNTAINTED( $dir );
    #}

    return @list;
}

1;
