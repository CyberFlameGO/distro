# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::Configure::Type

Base class of all types. Types are involved *only* in the presentation
of values in the configure interface. They do not play any part in
loading, saving or checking configuration values.

This is not an abstract class. Objects of this type are used when a
specialised class for a type cannot be found.

=cut

package Foswiki::Configure::TypeUI;

use strict;
use warnings;

use Assert;

use Foswiki::Configure::TypeUIs::UNKNOWN;

our %knownTypes;

sub new {
    my ( $class, $id ) = @_;

    return bless( { name => $id }, $class );
}

=begin TML

---++ StaticMethod load($id, $keys) -> $typeObject
Load the named type object
   * $id - the type name e.g. SELECTCLASS
   * $keys - the item the type is being loaded for. Only used to
     generate errors.

=cut

sub load {
    my ( $id, $keys ) = @_;
    ASSERT($id) if DEBUG;
    my $typer = $knownTypes{$id};
    unless ($typer) {
        my $failinfo;
        my $typeClass = 'Foswiki::Configure::TypeUIs::' . $id;
        eval "use $typeClass";
        if ($@) {
            $failinfo = "**$id** could not be 'use'd";
            print STDERR "$failinfo: $@";
            $typeClass = 'Foswiki::Configure::TypeUIs::UNKNOWN';
            eval "use $typeClass";
        }
        $typer = $typeClass->new($id);
        unless ($typer) {

            # unknown type - give it UNKNOWN behaviours
            $failinfo = "**$id** loaded, but the 'new' method returned undef";
            $typer    = new Foswiki::Configure::TypeUIs::UNKNOWN($id);
        }
        $typer->{failinfo} = $failinfo if defined $failinfo;
        $knownTypes{$id} = $typer;
    }
    return $typer;
}

=begin TML

---++ ObjectMethod prompt($model, $value, $class) -> $html
   * $model the Configure::Value for the value
   * $value current value of item (string)
   * $class CSS class
Generate HTML for a suitable prompt for the type.

=cut

sub prompt {
    my ( $this, $model, $value, $class ) = @_;

    my @spell;

    if ( $model->{SPELLCHECK} ) {
        @spell = ( -spellcheck => ( $1 eq 's' ? 'false' : 'true' ) );
    }
    if ( defined $model->{SIZE} && $model->{SIZE} =~ /(\d+)x(\d+)/ ) {
        my ( $cols, $rows ) = ( $1, $2 );
        return CGI::textarea(
            -name     => $model->{keys},
            -columns  => $cols,
            -rows     => $rows,
            -onchange => 'valueChanged(this)',
            -value    => $value,
            -class    => "foswikiTextarea $class",
            @spell,
          )

    }
    else {
        my $size = $Foswiki::Configure::DEFAULT_FIELD_WIDTH_NO_CSS;
        if ( defined $model->{SIZE} && $model->{SIZE} =~ /(\d+)/ ) {
            $size = $1;
        }

        # percentage size should be set in CSS
        return CGI::textfield(
            -name     => $model->{keys},
            -size     => $size,
            -default  => $value,
            -onchange => 'valueChanged(this)',
            -class    => "foswikiInputField $class",
            @spell,
        );
    }
}

=begin TML

---++ ObjectMethod equals($a, $b)
Test to determine if two values of this type are equal.
   * $a, $b the values (strings, usually)

=cut

sub equals {
    my ( $this, $val, $def ) = @_;

    if ( !defined $val ) {
        return 0 if defined $def;
        return 1;
    }
    elsif ( !defined $def ) {
        return 0;
    }
    return $val eq $def;
}

=begin TML

---++ ObjectMethod string2value($string) -> $data
Used to process input values from CGI. Values taken from the query
are run through this method before being saved in the value store.
It should *not* be used to do validation - use a Checker to do that, or
JavaScript invoked from the prompt.

This method is NOT invoked when values are read from LocalSite.cfg;
it is not (likely) the inverse of value2string.

=cut

sub string2value {
    my ( $this, $val ) = @_;
    return $val;
}

=begin TML

---++ ObjectMethod value2string($keys, $value) -> ($string, $require)
Used to encode output values during save.  The default is
adequate for most value types, but this hook allows for special
encoding when needed.  See PASSWORD for an example.

   * $keys - the {key}{s} of the value being output.

   * $value - the value to be encoded.  This is the actual value
              of the item, NOT a Foswiki::Configure::Value object.
              It should not be undef.

   * $string - the text to be entered in LocalSite.cfg for this value.
               For save to work, it must be in the form
               $Foswiki::cfg{key}{s} = ...;\n

   * $require - (optional) name of a require module that is
               required for decoding the value, and must be present in
               LSC. May be an arrayref [qw/mod1 mod2/].

This mechanism is intended for exceptional cases.  This default
method should be adequate for virtually every item type.

Do not confuse this method with others used to produce values for
human consumption.  Do not assume that it is the inverse of
string2value.

=cut

sub value2string {
    my $this = shift;
    my ( $keys, $value ) = @_;

    # For some reason Data::Dumper ignores the second parameter sometimes
    # when -T is enabled, so have to do a substitution

    my $txt = Data::Dumper->Dump( [$value] );
    $txt =~ s/VAR1/Foswiki::cfg$keys/;

    return ($txt);
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2010 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 2000-2006 TWiki Contributors. All Rights Reserved.
TWiki Contributors are listed in the AUTHORS file in the root
of this distribution. NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
