# See bottom of file for license and copyright information
package Foswiki::Configure::Wizard;

=begin TML

---++ package Foswiki::Configure::Wizard

A Wizard is module that performs one or more configuration functions.
For example, you might have a wizard that helps set up email;
when you have all the email settings done, you invoke the wizard
to attempt to complete the configuration.

Any number of callable functions may be defined in a wizard.
Each function _fn_ has the signature:

=ObjectMethod _fn_ ($reporter, $spec) -> $boolean=

Wizards can accept
values from callers using the =$this->param()= method. Error messages
etc are reported via the =Foswiki::Configure::Reporter $reporter=.

$spec is the root of the type specification tree for configuration entries.
This is provided primarily for wizards that need to modify it e.g.
installers.

Wizard functions may modify =$Foswiki::cfg=, but must report
any such changes that have to persist using the
=$reporter->CHANGED= method.

It's up to the UI how wizards are called, and their results returned.
See the documentation for the UI for more information.

=cut

use Assert;
use Try::Tiny;

use Foswiki::Class -types;
extends qw(Foswiki::Object);

has param_source => (
    is      => 'rw',
    lazy    => 1,
    default => sub { {} },
    assert  => Maybe [HashRef],
);

=begin TML

---++ StaticMethod loadWizard($name, $param_source) -> $wizard

Loads the Foswiki::Configure::Wizards subclass identified
by $name. =$param_source= is a reference to an object that
supports the =param()= method for getting parameter values.

=cut

sub loadWizard {
    my ( $name, $param_source ) = @_;

    ASSERT( $name =~ m/^[A-Za-z][A-Za-z0-9]+$/ ) if DEBUG;

    my $class = 'Foswiki::Configure::Wizards::' . $name;

    my $wizardObj;

    try {
        Foswiki::load_class($class);
        $wizardObj = $class->new( param_source => $param_source );
    }
    catch {
        Foswiki::Exception::Fatal->throw(
            text => "Failed to load wizard $class: "
              . Foswiki::Exception::errorStr($_) );
    };

    return $wizardObj;
}

=begin TML

---++ ObjectMethod param($name) -> $value

Returns the value of a parameter that was given when the wizard was invoked.

=cut

sub param {
    my ( $this, $param ) = @_;
    return $this->param_source->{$param};
}

1;
