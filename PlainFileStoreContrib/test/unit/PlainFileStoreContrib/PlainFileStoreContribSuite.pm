package PlainFileStoreContribSuite;

use strict;
use warnings;

use Unit::TestSuite;
our @ISA = qw( Unit::TestSuite );

sub name { 'PlainFileStoreContribSuite' }

sub include_tests { qw(PlainFileStoreContribTests LoadedRevTests) }

1;
