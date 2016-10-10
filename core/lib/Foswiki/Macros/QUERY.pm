# See bottom of file for license and copyright information
package Foswiki::Macros::QUERY;
use v5.14;

use Foswiki::Serialise ();
use Try::Tiny;

use Foswiki::Class qw(app);
extends qw(Foswiki::Object);
with qw(Foswiki::Macro);

has evalParser => (
    is      => 'rw',
    lazy    => 1,
    default => sub { return $_[0]->create('Foswiki::Query::Parser'); },
);

has evaluatingEval => (
    is      => 'rw',
    lazy    => 1,
    default => sub { {} },
);

sub expand {
    my ( $this, $params, $topicObject ) = @_;
    my $result;
    my $expr = $params->{_DEFAULT};
    $expr = '' unless defined $expr;
    my $style = ucfirst( lc( $params->{style} || 'default' ) );
    if ( $style =~ m/[^a-zA-Z0-9_]/ ) {
        return "%RED%QUERY: invalid 'style' parameter passed%ENDCOLOR%";
    }
    $style = Foswiki::Sandbox::untaintUnchecked($style);

    my $rev = $params->{rev};

    # FORMFIELD does its own caching.
    # Either the home-made cache there should go into Meta so that both
    # FORMFIELD and QUERY benefit, or the store should be made a lot smarter.

    if ( defined $rev ) {
        my $crev = $topicObject->getLoadedRev();
        if ( defined $crev && $crev != $rev ) {
            $topicObject =
              Foswiki::Meta->load( $topicObject->app, $topicObject->web,
                $topicObject->topic, $rev );
        }
    }
    elsif ( !$topicObject->latestIsLoaded() ) {

        # load latest rev
        $topicObject = $topicObject->load();
    }

    # Block after 5 levels.
    if (   $this->evaluatingEval->{$expr}
        && $this->evaluatingEval->{$expr} > 5 )
    {
        delete $this->evaluatingEval->{$expr};
        return '';
    }

    $this->evaluatingEval->{$expr}++;
    try {
        my $node = $this->evalParser->parse($expr);
        $result = $node->evaluate( tom => $topicObject, data => $topicObject );
        $result = Foswiki::Serialise::serialise( $result, $style );
    }
    catch {
        if ( $_->isa('Foswiki::Infix::Error') ) {
            $result =
              $this->app->inlineAlert( 'alerts', 'generic', 'QUERY{',
                $params->stringify(), '}:', $_->text );
        }
        else {
            Foswiki::Exception->rethrow($_);
        }
    }
    finally {
        delete $this->evaluatingEval->{$expr};
    };

    return $result;
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2010 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
