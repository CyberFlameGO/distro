# See bottom of file for license and copyright information

=begin TML

---+!! Class Foswiki::App

The core class of the project responsible for low-level and code glue
functionality.

=cut

package Foswiki::App;
use v5.14;

use constant TRACE_REQUEST => 0;

use Assert;
use Cwd;
use Try::Tiny;
use Storable qw(dclone);
use Foswiki qw(%regex);
use CGI                ();
use Compress::Zlib     ();
use Foswiki::Config    ();
use Foswiki::Engine    ();
use Foswiki::Templates ();
use Foswiki::Exception ();
use Foswiki qw(load_package load_class);

use Moo;
use namespace::clean;
extends qw(Foswiki::Object);

has access => (
    is        => 'ro',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    isa =>
      Foswiki::Object::isaCLASS( 'access', 'Foswiki::Access', noUndef => 1, ),
    default => sub {
        my $this        = shift;
        my $accessClass = $this->cfg->data->{AccessControl}
          || 'Foswiki::Access::TopicACLAccess';
        return $this->create($accessClass);
    },
);
has attach => (
    is        => 'ro',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub { $_[0]->create('Foswiki::Attach'); },
);
has cache => (
    is        => 'rw',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub {
        my $this = shift;
        my $cfg  = $this->cfg;
        if (   $cfg->data->{Cache}{Enabled}
            && $cfg->data->{Cache}{Implementation} )
        {
            load_class( $cfg->data->{Cache}{Implementation} );
            ASSERT( !$@, $@ ) if DEBUG;
            return $this->create( $cfg->data->{Cache}{Implementation} );
        }
        return undef;
    },
);

=begin TML
---++ ObjectAttribute cfg

This attribute stores application configuration object - a =Foswiki::Config=
instance.

=cut

has cfg => (
    is      => 'rw',
    lazy    => 1,
    builder => '_prepareConfig',
    isa => Foswiki::Object::isaCLASS( 'cfg', 'Foswiki::Config', noUndef => 1, ),
);
has env => (
    is       => 'rw',
    required => 1,
);
has forms => (
    is      => 'ro',
    lazy    => 1,
    clearer => 1,
    default => sub { {} },
);
has logger => (
    is        => 'ro',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub {
        my $this        = shift;
        my $cfg         = $this->cfg;
        my $loggerClass = 'Foswiki::Logger';
        if ( $cfg->data->{Log}{Implementation} ne 'none' ) {
            $loggerClass = $cfg->data->{Log}{Implementation};
        }
        return $this->create($loggerClass);
    },
);
has engine => (
    is        => 'rw',
    lazy      => 1,
    predicate => 1,
    builder   => '_prepareEngine',
    isa =>
      Foswiki::Object::isaCLASS( 'engine', 'Foswiki::Engine', noUndef => 1, ),
);

# Heap is to be used for data persistent over session lifetime.
# Usage: $sessiom->heap->{key} = <your data>;
has heap => (
    is      => 'rw',
    clearer => 1,
    lazy    => 1,
    default => sub { {} },
);
has i18n => (
    is        => 'ro',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub {

        # language information; must be loaded after
        # *all possible preferences sources* are available
        $_[0]->create('Foswiki::I18N');
    },
);
has net => (
    is        => 'ro',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub { return $_[0]->create('Foswiki::Net'); },
);
has plugins => (
    is        => 'rw',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub { return $_[0]->create('Foswiki::Plugins'); },
);
has prefs => (
    is        => 'ro',
    lazy      => 1,
    predicate => 1,
    clearer   => 1,
    builder   => '_preparePrefs',
);
has renderer => (
    is        => 'ro',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub {
        return $_[0]->create('Foswiki::Render');
    },
);
has request => (
    is      => 'rw',
    lazy    => 1,
    builder => '_prepareRequest',
    isa =>
      Foswiki::Object::isaCLASS( 'request', 'Foswiki::Request', noUndef => 1, ),
);
has response => (
    is      => 'rw',
    lazy    => 1,
    clearer => 1,
    default => sub { $_[0]->create('Foswiki::Response') },
    isa     => Foswiki::Object::isaCLASS(
        'response', 'Foswiki::Response', noUndef => 1,
    ),
);
has search => (
    is        => 'ro',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub {
        return $_[0]->create('Foswiki::Search');
    },
);
has store => (
    is        => 'rw',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    isa =>
      Foswiki::Object::isaCLASS( 'store', 'Foswiki::Store', noUndef => 1, ),
    default => sub {
        my $storeClass = $Foswiki::cfg{Store}{Implementation}
          || 'Foswiki::Store::PlainFile';
        ASSERT( $storeClass, "Foswiki::store base class is not defined" )
          if DEBUG;
        return $_[0]->create($storeClass);
    },
);
has templates => (
    is        => 'ro',
    lazy      => 1,
    predicate => 1,
    clearer   => 1,
    default   => sub { return $_[0]->create('Foswiki::Templates'); },
);
has macros => (
    is      => 'rw',
    lazy    => 1,
    default => sub { return $_[0]->create('Foswiki::Macros'); },
    isa =>
      Foswiki::Object::isaCLASS( 'macros', 'Foswiki::Macros', noUndef => 1, ),
);
has context => (
    is      => 'rw',
    lazy    => 1,
    clearer => 1,
    default => sub {
        return {};
    },
);
has ui => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        return $_[0]->create('Foswiki::UI');
    },
);
has remoteUser => (
    is        => 'rw',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub {
        my $this = shift;
        my $user = $this->has_user ? $this->user : $this->engine->user;
        return $this->users->loadSession($user);
    },
);
has user => (
    is        => 'rw',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub {
        my $this = shift;
        return $this->users->initialiseUser( $this->remoteUser );
    },
);
has users => (
    is        => 'rw',
    lazy      => 1,
    predicate => 1,
    clearer   => 1,
    default   => sub { return $_[0]->create('Foswiki::Users'); },
);
has zones => (
    is        => 'ro',
    lazy      => 1,
    clearer   => 1,
    predicate => 1,
    default   => sub { return $_[0]->create('Foswiki::Render::Zones'); },
);
has _dispatcherAttrs => (
    is  => 'rw',
    isa => Foswiki::Object::isaHASH( '_dispatcherAttrs', noUndef => 1 ),
);

# List of system messages to be displayed to user. Could be used to display non-critical errors or important warnings.
has system_messages => (
    is      => 'rw',
    lazy    => 1,
    clearer => 1,
    default => sub { [] },
    isa     => Foswiki::Object::isaARRAY( 'system_messages', noUndef => 1, ),
);

has inUnitTestMode => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $this   = shift;
        my $inTest = $Foswiki::inUnitTestMode
          || ( $this->has_engine && ref( $this->engine ) =~ /::Test$/ );
        return $inTest;
    },
);

=begin TML

---++ ClassMethod new([%parameters])

The following keys could be defined in =%parameters= hash:

|*Key*|*Type*|*Description*|
|=env=|hashref|Environment hash such as shell environment or PSGI env| 

=cut

sub BUILD {
    my $this   = shift;
    my $params = shift;

    $Foswiki::app = $this;

    my $cfg = $this->cfg;
    if ( $cfg->data->{Store}{overrideUmask} && $cfg->data->{OS} ne 'WINDOWS' ) {

# Note: The addition of zero is required to force dirPermission and filePermission
# to be numeric.   Without the additition, certain values of the permissions cause
# runtime errors about illegal characters in subtraction.   "and" with 777 to prevent
# sticky-bits from breaking the umask.
        my $oldUmask = umask(
            (
                oct(777) - (
                    (
                        $cfg->data->{Store}{dirPermission} + 0 |
                          $cfg->data->{Store}{filePermission} + 0
                    )
                ) & oct(777)
            )
        );

#my $umask = sprintf('%04o', umask() );
#$oldUmask = sprintf('%04o', $oldUmask );
#my $dirPerm = sprintf('%04o', $Foswiki::cfg{Store}{dirPermission}+0 );
#my $filePerm = sprintf('%04o', $Foswiki::cfg{Store}{filePermission}+0 );
#print STDERR " ENGINE changes $oldUmask to  $umask  from $dirPerm and $filePerm \n";
    }

    # Enforce some shell environment variables.
    # SMELL Would it be tolerated in PSGI?
    $CGI::TMPDIRECTORY = $ENV{TMPDIR} = $ENV{TEMP} = $ENV{TMP} =
      $cfg->data->{TempfileDir};

    # Make %ENV safer, preventing hijack of the search path. The
    # environment is set per-query, so this can't be done in a BEGIN.
    # This MUST be done before any external programs are run via Sandbox.
    # or it will fail with taint errors.  See Item13237
    if ( defined $cfg->data->{SafeEnvPath} ) {
        $ENV{PATH} = $cfg->data->{SafeEnvPath};
    }
    else {
        # Default $ENV{PATH} must be untainted because
        # Foswiki may be run with the -T flag.
        # SMELL: how can we validate the PATH?
        $this->systemMessage(
"Unsafe shell variable PATH is used, consider setting SafeEnvPath configuration parameter."
        );
        $ENV{PATH} = Foswiki::Sandbox::untaintUnchecked( $ENV{PATH} );
    }
    delete @ENV{qw( IFS CDPATH ENV BASH_ENV )};

# TODO It's not clear yet as how to deal with logger configuration - see Foswiki::BUILDARGS().

    unless ( defined $this->engine ) {
        Foswiki::Exception::Fatal->throw( text => "Cannot initialize engine" );
    }

    unless ( $this->cfg->data->{isVALID} ) {
        $this->cfg->bootstrapSystemSettings;
    }

    $this->_prepareDispatcher;

    # Check if we can get CGI session.
    ASSERT( $this->remoteUser, "set remoteUser" );

    # Override user to be admin if no configuration exists.
    # Do this really early, so that later changes in isBOOTSTRAPPING can't
    # change Foswiki's behavior.
    $this->user('admin') if ( $cfg->data->{isBOOTSTRAPPING} );

    $this->_readPrefs;
}

=begin TML

---++ StaticMethod run([%parameters])

Starts application, prepares and initiates request processing. The following
keys could be defined in =%parameters= hash:

|*Key*|*Type*|*Description*|
|=env=|hashref|Environment hash such as shell environment or PSGI env| 

=cut

sub run {
    my $class  = shift;
    my %params = @_;

    # Do nice in shared code environment, localize ALL request-related globals.
    local %Foswiki::app;
    local %Foswiki::cfg;
    local %TWiki::cfg;

    # Before localizing shell environment we need to preserve and restore it.
    local %ENV = %ENV;

    my ( $app, $rc );

    # We use shell environment by default. PSGI would supply its own env
    # hashref. Because PSGI env is not the same as shell env we would need to
    # avoid any side effects related to situations when changes to the env
    # hashref are gettin' translated back onto the shell env.
    $params{env} //= dclone( \%ENV );

    # Use current working dir for fetching the initial setlib.cfg
    $params{env}{PWD} //= getcwd;

    try {
        local $SIG{__DIE__} = sub {

            # Somehow overriding of __DIE__ clashes with remote perl debugger in
            # Komodo unless we die again instantly.
            die $_[0] if (caller)[0] =~ /^DB::/;
            Foswiki::Exception::Fatal->rethrow( $_[0] );
        };
        local $SIG{__WARN__} = sub {
            Foswiki::Exception::Fatal->rethrow( $_[0] );
          }
          if DEBUG;

        $app = $class->new(%params);
        $rc  = $app->handleRequest;
    }
    catch {
        my $e = Foswiki::Exception::Fatal->transmute( $_, 0 );

        if ( defined $app && defined $app->logger ) {
            $app->logger->log( 'error', $e->stringify, );
        }

        my $errStr = Foswiki::Exception::errorStr($e);

        # Low-level report of errors to user.
        if ( defined $app && $app->has_engine ) {

            $errStr = '<pre>' . Foswiki::entityEncode($errStr) . '</pre>';

            # Send error output to user using the initialized engine.
            $rc = $app->engine->finalizeReturn(
                [
                    500,
                    [
                        'Content-Type'   => 'text/html; charset=utf-8',
                        'Content-Length' => length($errStr),
                    ],
                    [$errStr]
                ]
            );
        }
        else {
            # Propagade the error using the most primitive way.
            die $errStr;
        }
    };
    return $rc;
}

sub handleRequest {
    my $this = shift;

    my $req = $this->request;
    my $res = $this->response;
    my $rc;

    try {
        $this->_checkBootstrapStage2;
        $this->_checkTickle;
        $this->_checkReqCache;

        if (TRACE_REQUEST) {
            print STDERR "INCOMING "
              . $req->method() . " "
              . $req->url . " -> "
              . $this->_dispatcherAttrs->{method} . "\n";
            print STDERR "validation_key: "
              . ( $req->param('validation_key') || 'no key' ) . "\n";

            #require Data::Dumper;
            #print STDERR Data::Dumper->Dump([$req]);
        }

        $this->_checkActionAccess;

        # Set both isadmin and authenticated contexts. If the current user is
        # admin, then they either authenticated, or we are in bootstrap.
        if ( $this->users->isAdmin( $this->user ) ) {
            $this->context->{authenticated} = 1;
            $this->context->{isadmin}       = 1;
        }

        # Finish plugin initialization - register handlers
        $this->plugins->enable();

        my $method = $this->_dispatcherAttrs->{method};
        $this->_prepareContext;
        $this->ui->$method;
    }
    catch {
        my $e = Foswiki::Exception::Fatal->transmute( $_, 0 );

        $res = $this->response;

        # SMELL TODO At this stage we shall be able to display any expection in
        # a pretty HTMLized way if engine is HTTPCompliant. Rethrowing of an
        # exception is just a temporary stub.
        if ( $e->isa('Foswiki::AccessControlException') ) {

            unless ( $this->users->getLoginManager->forceAuthentication ) {

                # Login manager did not want to authenticate, perhaps because
                # we are already authenticated.
                my $exception = $this->create(
                    'Foswiki::OopsException',
                    template => 'accessdenied',
                    status   => 403,
                    web      => $e->web,
                    topic    => $e->topic,
                    def      => 'topic_access',
                    params   => [ $e->mode, $e->reason ]
                );

                $exception->generate;
            }
        }
        elsif ( $e->isa('Foswiki::OopsException') ) {
            $e->generate;
        }
        elsif ( $e->isa('Foswiki::EngineException') ) {
            $res->header( -type => 'text/html', );
            $res->status( $e->status );
            my $html = CGI::start_html( $e->status . ' Bad Request' );
            $html .= CGI::h1( {}, 'Bad Request' );
            $html .= CGI::p( {}, $e->reason );
            $html .= CGI::end_html();
            $res->print( Foswiki::encode_utf8($html) );
        }
        else {
            Foswiki::Exception::Fatal->rethrow($e);
        }
    };

    my $return = $res->as_array;
    $res->outputHasStarted(1);
    $rc = $this->engine->finalizeReturn($return);

    return $rc;
}

=begin TML

--++ ObjectMethod create($className, %initArgs)

Similar to =Foswiki::AppObject::create()= method but for the =Foswiki::App=
itself.

=cut

sub create {
    my $this  = shift;
    my $class = shift;

    $class = ref($class) if ref($class);

    Foswiki::load_class($class);

    unless ( $class->does('Foswiki::AppObject') ) {
        Foswiki::Exception::Fatal->throw(
            text => "Class $class doesn't do Foswiki::AppObject role." );
    }

    return $class->new( app => $this, @_ );
}

=begin TML

---++ ObjectMethod deepWebList($filter, $web) -> @list

Deep list subwebs of the named web. $filter is a Foswiki::WebFilter
object that is used to filter the list. The listing of subwebs is
dependent on $Foswiki::cfg{EnableHierarchicalWebs} being true.

Webs are returned as absolute web pathnames.

=cut

sub deepWebList {
    my ( $this, $filter, $rootWeb ) = @_;
    my @list;
    my $webObject = $this->create( 'Foswiki::Meta', web => $rootWeb );
    my $it = $webObject->eachWeb( $this->cfg->data->{EnableHierarchicalWebs} );
    return $it->all() unless $filter;
    while ( $it->hasNext() ) {
        my $w = $rootWeb || '';
        $w .= '/' if $w;
        $w .= $it->next();
        if ( $filter->ok( $this, $w ) ) {
            push( @list, $w );
        }
    }
    return @list;
}

=begin TML

---++ ObjectMethod enterContext( $id, $val )

Add the context id $id into the set of active contexts. The $val
can be anything you like, but should always evaluate to boolean
TRUE.

An example of the use of contexts is in the use of tag
expansion. The commonTagsHandler in plugins is called every
time tags need to be expanded, and the context of that expansion
is signalled by the expanding module using a context id. So the
forms module adds the context id "form" before invoking common
tags expansion.

Contexts are not just useful for tag expansion; they are also
relevant when rendering.

Contexts are intended for use mainly by plugins. Core modules can
use $session->inContext( $id ) to determine if a context is active.

=cut

sub enterContext {
    my ( $this, $id, $val ) = @_;
    $val ||= 1;
    $this->context->{$id} = $val;
}

=begin TML

---++ ObjectMethod leaveContext( $id )

Remove the context id $id from the set of active contexts.
(see =enterContext= for more information on contexts)

=cut

sub leaveContext {
    my ( $this, $id ) = @_;
    my $res = $this->context->{$id};
    delete $this->context->{$id};
    return $res;
}

=begin TML

---++ ObjectMethod inContext( $id )

Return the value for the given context id
(see =enterContext= for more information on contexts)

=cut

sub inContext {
    my ( $this, $id ) = @_;
    return $this->context->{$id};
}

=begin TML

---++ ObjectMethod inlineAlert($template, $def, ... ) -> $string

Format an error for inline inclusion in rendered output. The message string
is obtained from the template 'oops'.$template, and the DEF $def is
selected. The parameters (...) are used to populate %PARAM1%..%PARAMn%

=cut

sub inlineAlert {
    my $this     = shift;
    my $template = shift;
    my $def      = shift;

    my $req = $this->request;

    # web and topic can be anything; they are not used
    my $topicObject = $this->create(
        'Foswiki::Meta',
        web   => $req->web,
        topic => $req->topic,
    );
    my $text = $this->templates->readTemplate( 'oops' . $template );
    if ($text) {
        my $blah = $this->templates->expandTemplate($def);
        $text =~ s/%INSTANTIATE%/$blah/;

        $text = $topicObject->expandMacros($text);
        my $n = 1;
        while ( defined( my $param = shift ) ) {
            $text =~ s/%PARAM$n%/$param/g;
            $n++;
        }

        # Suppress missing params
        $text =~ s/%PARAM\d+%//g;

        # Suppress missing params
        $text =~ s/%PARAM\d+%//g;
    }
    else {

        # Error in the template system.
        $text = $topicObject->renderTML(<<MESSAGE);
---+ Foswiki Installation Error
Template 'oops$template' not found or returned no text, expanding $def.

Check your configuration settings for {TemplateDir} and {TemplatePath}
or check for syntax errors in templates,  or a missing TMPL:END.
MESSAGE
    }

    return $text;
}

=begin TML

---++ ObjectMethod redirect( $url, $passthrough, $status )

   * $url - url or topic to redirect to
   * $passthrough - (optional) parameter to pass through current query
     parameters (see below)
   * $status - HTTP status code (30x) to redirect with. Defaults to 302.

Redirects the request to =$url=, *unless*
   1 It is overridden by a plugin declaring a =redirectCgiQueryHandler=
     (a dangerous, deprecated handler!)
   1 =$session->{request}= is =undef=
Thus a redirect is only generated when in a CGI context.

Normally this method will ignore parameters to the current query. Sometimes,
for example when redirecting to a login page during authentication (and then
again from the login page to the original requested URL), you want to make
sure all parameters are passed on, and for this $passthrough should be set to
true. In this case it will pass all parameters that were passed to the
current query on to the redirect target. If the request_method for the
current query was GET, then all parameters will be passed by encoding them
in the URL (after ?). If the request_method was POST, then there is a risk the
URL would be too big for the receiver, so it caches the form data and passes
over a cache reference in the redirect GET.

NOTE: Passthrough is only meaningful if the redirect target is on the same
server.

=cut

sub redirect {
    my $this = shift;
    my ( $url, $passthru, $status ) = @_;
    ASSERT( defined $url ) if DEBUG;

    my $req = $this->request;

    ( $url, my $anchor ) = Foswiki::splitAnchorFromUrl($url);

    if ( $passthru && defined $req->method() ) {
        my $existing = '';
        if ( $url =~ s/\?(.*)$// ) {
            $existing = $1;    # implicit untaint OK; recombined later
        }
        if ( uc( $req->method() ) eq 'POST' ) {

            # Redirecting from a post to a get
            my $cache = $req->cacheQuery;
            if ($cache) {
                if ( $url eq '/' ) {
                    $url = $this->cfg->getScriptUrl( 1, 'view' );
                }
                $url .= $cache;
            }
        }
        else {

            # Redirecting a get to a get; no need to use passthru
            if ( $req->query_string() ) {
                $url .= '?' . $req->query_string();
            }
            if ($existing) {
                if ( $url =~ m/\?/ ) {
                    $url .= ';';
                }
                else {
                    $url .= '?';
                }
                $url .= $existing;
            }
        }
    }

    # prevent phishing by only allowing redirect to configured host
    # do this check as late as possible to catch _any_ last minute hacks
    # TODO: this should really use URI
    if ( !Foswiki::_isRedirectSafe($url) ) {

        # goto oops if URL is trying to take us somewhere dangerous
        $url = $this->cfg->getScriptUrl(
            1, 'oops',
            $this->webName   || $Foswiki::cfg{UsersWebName},
            $this->topicName || $Foswiki::cfg{HomeTopicName},
            template => 'oopsredirectdenied',
            def      => 'redirect_denied',
            param1   => "$url",
            param2   => "$Foswiki::cfg{DefaultUrlHost}",
        );
    }

    $url .= $anchor if $anchor;

    # Dangerous, deprecated handler! Might work, probably won't.
    return
      if (
        $this->plugins->dispatch(
            'redirectCgiQueryHandler', $this->response, $url
        )
      );

    $url = $this->users->getLoginManager->rewriteRedirectUrl($url);

    # Foswiki::Response::redirect doesn't automatically pass on the cookies
    # for us, so we have to do it explicitly; otherwise the session cookie
    # won't get passed on.
    $this->response->redirect(
        -url     => $url,
        -cookies => $this->response->cookies,
        -status  => $status,
    );
}

=begin TML

---++ ObjectMethod redirectto($url) -> $url

If the CGI parameter 'redirectto' is present on the query, then will validate
that it is a legal redirection target (url or topic name). If 'redirectto'
is not present on the query, performs the same steps on $url.

Returns undef if the target is not valid, and the target URL otherwise.

=cut

sub redirectto {
    my ( $this, $url ) = @_;

    my $req         = $this->request;
    my $redirecturl = $req->param('redirectto');
    $redirecturl = $url unless $redirecturl;

    return unless $redirecturl;

    if ( $redirecturl =~ m#^$regex{linkProtocolPattern}://# ) {

        # assuming URL
        return $redirecturl if Foswiki::_isRedirectSafe($redirecturl);
        return;
    }

    my @attrs = ();

    # capture anchor
    if ( $redirecturl =~ s/#(.*)// ) {
        push( @attrs, '#' => $1 );
    }

    # capture params
    if ( $redirecturl =~ s/\?(.*)// ) {
        push( @attrs, map { split( '=', $_, 2 ) } split( /[;&]/, $1 ) );
    }

    # assuming 'web.topic' or 'topic'
    my ( $w, $t ) = $req->normalizeWebTopicName( $req->web, $redirecturl );

    return $this->cfg->getScriptUrl( 0, 'view', $w, $t, @attrs );
}

=begin TML

---++ ObjectMethod satisfiedByCache( $action, $web, $topic ) -> $boolean

Try and satisfy the current request for the given web.topic from the cache, given
the current action (view, edit, rest etc).

If the action is satisfied, the cache content is written to the output and
true is returned. Otherwise ntohing is written, and false is returned.

Designed for calling from Foswiki::UI::*

=cut

sub satisfiedByCache {
    my ( $this, $action, $web, $topic ) = @_;

    my $cache = $this->cache;
    return 0 unless $cache;

    my $cachedPage = $cache->getPage( $web, $topic ) if $cache;
    return 0 unless $cachedPage;

    Foswiki::Func::writeDebug("found $web.$topic for $action in cache")
      if Foswiki::PageCache::TRACE();
    if ( int( $this->response->status || 200 ) >= 500 ) {
        Foswiki::Func::writeDebug(
            "Cache retrieval skipped due to non-200 status code "
              . $this->response->status )
          if DEBUG;
        return 0;
    }
    Monitor::MARK("found page in cache");

    my $hdrs = { 'Content-Type' => $cachedPage->{contenttype} };

    # render uncacheable areas
    my $text = $cachedPage->{data};

    if ( $cachedPage->{isdirty} ) {
        $cache->renderDirtyAreas( \$text );

        # dirty pages are cached in unicode
        $text = Foswiki::encode_utf8($text);
    }
    elsif ( $Foswiki::cfg{HttpCompress} ) {

        # Does the client accept gzip?
        if ( my $encoding = $this->engine->gzipAccepted ) {

            # Cache has compressed data, just whack it out
            $hdrs->{'Content-Encoding'} = $encoding;
            $hdrs->{'Vary'}             = 'Accept-Encoding';

            # Mark the response so we know it was satisfied from the cache
            $hdrs->{'X-Foswiki-PageCache'} = 1;
        }
        else {
        # e.g. CLI request satisfied from the cache, or old browser that doesn't
        # support gzip. Non-isdirty pages are cached already utf8-encoded, so
        # all we have to do is unzip.
            $text = Compress::Zlib::memGunzip( $cachedPage->{data} );
        }
    }    # else { Non-isdirty pages are stored already utf8-encoded }

    # set status
    my $response = $this->response;
    if ( $cachedPage->{status} == 302 ) {
        $response->redirect( $cachedPage->{location} );
    }
    else {

     # See Item9941
     # Don't allow a 200 status to overwrite a status (possibly an error status)
     # coming from elsewhere in the code. Note that 401's are not cached (they
     # fail Foswiki::PageCache::isCacheable) but all other statuses are.
     # SMELL: Cdot doesn't think any other status can get this far.
        $response->status( $cachedPage->{status} )
          unless int( $cachedPage->{status} ) == 200;
    }

    # set remaining headers
    $text = undef unless $this->setETags( $cachedPage, $hdrs );
    $response->generateHTTPHeaders($hdrs);

    # send it out
    $response->body($text) if defined $text;

    Monitor::MARK('Wrote HTML');
    $this->logger->log(
        {
            level    => 'info',
            action   => $action,
            webTopic => $web . '.' . $topic,
            extra    => '(cached)',
        }
    );

    return 1;
}

=begin TML

---++ ObjectMethod setCacheControl( $pageType, \%hopts )

Set the cache control headers in a response

   * =$pageType= - page type - 'view', ;edit' etc
   * =\%hopts - ref to partially filled in hash of headers

=cut

sub setCacheControl {
    my ( $this, $pageType, $hopts ) = @_;

    if ( $pageType && $pageType eq 'edit' ) {

        # Edit pages - future versions will extend to
        # of other types of page, with expiry time driven by page type.

        # Get time now in HTTP header format
        my $lastModifiedString =
          Foswiki::Time::formatTime( time, '$http', 'gmtime' );

        # Expiry time is set high to avoid any data loss.  Each instance of
        # Edit page has a unique URL with time-string suffix (fix for
        # RefreshEditPage), so this long expiry time simply means that the
        # browser Back button always works.  The next Edit on this page
        # will use another URL and therefore won't use any cached
        # version of this Edit page.
        my $expireHours   = 24;
        my $expireSeconds = $expireHours * 60 * 60;

        # and cache control headers, to ensure edit page
        # is cached until required expiry time.
        $hopts->{'last-modified'} = $lastModifiedString;
        $hopts->{expires}         = "+${expireHours}h";
        $hopts->{'Cache-Control'} = "max-age=$expireSeconds";
    }
    else {

        # we need to force the browser into a check on every
        # request; let the server decide on an 304 as below
        my $cacheControl = 'max-age=0';

        my $req = $this->request;

        # allow the admin to disable us from setting the max-age, as then
        # it can't be set by apache
        $cacheControl = $Foswiki::cfg{BrowserCacheControl}->{ $req->web }
          if ( $Foswiki::cfg{BrowserCacheControl}
            && defined( $Foswiki::cfg{BrowserCacheControl}->{ $req->web } ) );

        # don't remove the 'if'; we need the header to not be there at
        # all for the browser to use the cached version
        $hopts->{'Cache-Control'} = $cacheControl if ( $cacheControl ne '' );
    }
}

=begin TML

---++ ObjectMethod setETags( $cachedPage, \%hopts ) -> $boolean

Set etags (and modify status) depending on what the cached page specifies.
Return 1 if the page has been modified since it was last retrieved, 0 otherwise.

   * =$cachedPage= - page cache to use
   * =\%hopts - ref to partially filled in hash of headers

=cut

sub setETags {
    my ( $this, $cachedPage, $hopts ) = @_;

    # check etag and last modification time
    my $etag         = $cachedPage->{etag};
    my $lastModified = $cachedPage->{lastmodified};

    $hopts->{'ETag'}          = $etag         if $etag;
    $hopts->{'Last-Modified'} = $lastModified if $lastModified;

    # only send a 304 if both criteria are true
    return 1
      unless (
           $etag
        && $lastModified

        && $this->env->{'HTTP_IF_NONE_MATCH'}
        && $etag eq $this->env->{'HTTP_IF_NONE_MATCH'}

        && $this->env->{'HTTP_IF_MODIFIED_SINCE'}
        && $lastModified eq $this->env->{'HTTP_IF_MODIFIED_SINCE'}
      );

    # finally decide on a 304 reply
    $hopts->{'Status'} = '304 Not Modified';

    #print STDERR "NOT modified\n";
    return 0;
}

=begin TML

---++ ObjectMethod getSkin () -> $string

Get the currently requested skin path

=cut

sub getSkin {
    my $this = shift;

    my @skinpath;
    my $skins;

    if ( $this->request ) {
        $skins = $this->request->param('cover');
        if ( defined $skins
            && $skins =~ m/([[:alnum:].,\s]+)/ )
        {

            # Implicit untaint ok - validated
            $skins = $1;
            push( @skinpath, split( /,\s]+/, $skins ) );
        }
    }

    $skins = $this->prefs->getPreference('COVER');
    if ( defined $skins
        && $skins =~ m/([[:alnum:].,\s]+)/ )
    {

        # Implicit untaint ok - validated
        $skins = $1;
        push( @skinpath, split( /[,\s]+/, $skins ) );
    }

    $skins = $this->request ? $this->request->param('skin') : undef;
    $skins = $this->prefs->getPreference('SKIN') unless $skins;

    if ( defined $skins && $skins =~ m/([[:alnum:].,\s]+)/ ) {

        # Implicit untaint ok - validated
        $skins = $1;
        push( @skinpath, split( /[,\s]+/, $skins ) );
    }

    return join( ',', @skinpath );
}

=begin TML

---++ ObjectMethod systemMessage( @messages )

Adds a new system message to be displayed to a user (who most likely would be an
admin) either as a banner on the top of a wiki topic or by a special macro.

This method is to be used with care when really necessary.

=cut

sub systemMessage {
    my $this = shift;
    if (@_) {
        push @{ $this->system_messages }, @_;
    }
    return join( '%BR%', @{ $this->system_messages } );
}

=begin TML

---++ ObjectMethod writeCompletePage( $text, $pageType, $contentType )

Write a complete HTML page with basic header to the browser.
   * =$text= is the text of the page script (&lt;html&gt; to &lt;/html&gt; if it's HTML)
   * =$pageType= - May be "edit", which will cause headers to be generated that force
     caching for 24 hours, to prevent Codev.BackFromPreviewLosesText bug, which caused
     data loss with IE5 and IE6.
   * =$contentType= - page content type | text/html

This method removes noautolink and nop tags before outputting the page unless
$contentType is text/plain.

=cut

sub writeCompletePage {
    my ( $this, $text, $pageType, $contentType ) = @_;

    # true if the body is to be output without encoding to utf8
    # first. This is the case if the body has been gzipped and/or
    # rendered from the cache
    my $binary_body = 0;

    $contentType ||= 'text/html';

    my $cgis = $this->users->getCGISession();
    if (   $cgis
        && $contentType =~ m!^text/html!
        && $Foswiki::cfg{Validation}{Method} ne 'none' )
    {

        # Don't expire the validation key through login, or when
        # endpoint is an error.
        Foswiki::Validation::expireValidationKeys($cgis)
          unless ( $this->request->action() eq 'login'
            or ( $ENV{REDIRECT_STATUS} || 0 ) >= 400 );

        my $usingStrikeOne = $Foswiki::cfg{Validation}{Method} eq 'strikeone';
        if ($usingStrikeOne) {

            # add the validation cookie
            my $valCookie = Foswiki::Validation::getCookie($cgis);
            $valCookie->secure( $this->request->secure );
            $this->response->cookies(
                [ $this->response->cookies, $valCookie ] );

            # Add the strikeone JS module to the page.
            my $src = (DEBUG) ? '.uncompressed' : '';
            $this->zones->addToZone(
                'script',
                'JavascriptFiles/strikeone',
                '<script type="text/javascript" src="'
                  . $this->cfg->getPubURL(
                    $this->cfg->data->{SystemWebName}, 'JavascriptFiles',
                    "strikeone$src.js"
                  )
                  . '"></script>',
                'JQUERYPLUGIN'
            );

            # Add the onsubmit handler to the form
            $text =~ s/(<form[^>]*method=['"]POST['"][^>]*>)/
                Foswiki::Validation::addOnSubmit($1)/gei;
        }

        my $context =
          $this->request->url( -full => 1, -path => 1, -query => 1 ) . time();

        # Inject validation key in HTML forms
        $text =~ s/(<form[^>]*method=['"]POST['"][^>]*>)/
          $1 . Foswiki::Validation::addValidationKey(
              $cgis, $context, $usingStrikeOne )/gei;

        #add validation key to HTTP header so we can update it for ajax use
        $this->response->pushHeader(
            'X-Foswiki-Validation',
            Foswiki::Validation::generateValidationKey(
                $cgis, $context, $usingStrikeOne
            )
        ) if ($cgis);
    }

    if ( $this->zones ) {

        $text = $this->zones->_renderZones($text);
    }

    # Validate format of content-type (defined in rfc2616)
    my $tch = qr/[^\[\]()<>@,;:\\"\/?={}\s]/;
    if ( $contentType =~ m/($tch+\/$tch+(\s*;\s*$tch+=($tch+|"[^"]*"))*)$/i ) {
        $contentType = $1;
    }
    else {
        # SMELL: can't compute; faking content-type for backwards compatibility;
        # any other information might become bogus later anyway
        $contentType = "text/plain;contenttype=invalid";
    }
    my $hdr = "Content-type: " . $1 . "\r\n";

    # Call final handler
    $this->plugins->dispatch( 'completePageHandler', $text, $hdr );

    # cache final page, but only view and rest
    my $cachedPage;
    if ( $contentType ne 'text/plain' ) {

        # Remove <nop> and <noautolink> tags
        $text =~ s/([\t ]?)[ \t]*<\/?(nop|noautolink)\/?>/$1/gis;
        if ( $Foswiki::cfg{Cache}{Enabled}
            && ( $this->inContext('view') || $this->inContext('rest') ) )
        {
            $cachedPage = $this->cache->cachePage( $contentType, $text );
            $this->cache->renderDirtyAreas( \$text )
              if $cachedPage && $cachedPage->{isdirty};
        }

        # remove <dirtyarea> tags
        $text =~ s/<\/?dirtyarea[^>]*>//g;

        # Check that the templates specified clean HTML
        if (DEBUG) {

            # When tracing is enabled in Foswiki::Templates, then there will
            # always be a <!--bodyend--> after </html>. So we need to disable
            # this check.
            if (   !Foswiki::Templates->TRACE
                && $contentType =~ m#text/html#
                && $text =~ m#</html>(.*?\S.*)$#s )
            {
                ASSERT( 0, <<BOGUS );
Junk after </html>: $1. Templates may be bogus
- Check for excess blank lines at ends of .tmpl files
-  or newlines after %TMPL:INCLUDE
- You can enable TRACE in Foswiki::Templates to help debug
BOGUS
            }
        }
    }

    $this->response->pushHeader( 'X-Foswiki-Monitor-renderTime',
        $this->request->getTime() );

    my $hopts = { 'Content-Type' => $contentType };

    $this->setCacheControl( $pageType, $hopts );

    if ($cachedPage) {
        $text = '' unless $this->setETags( $cachedPage, $hopts );
    }

    if ( $Foswiki::cfg{HttpCompress} && length($text) ) {

        # Generate a zipped page, if the client accepts them

        # SMELL: $ENV{SPDY} is a non-standard way to detect spdy protocol
        if ( my $encoding = $this->engine->gzipAccepted ) {
            $hopts->{'Content-Encoding'} = $encoding;
            $hopts->{'Vary'}             = 'Accept-Encoding';

            # check if we take the version from the cache. NOTE: we don't
            # set X-Foswiki-Pagecache because this is *not* coming from
            # the cache (well it is, but it was only just put there)
            if ( $cachedPage && !$cachedPage->{isdirty} ) {
                $text = $cachedPage->{data};
            }
            else {
                # Not available from the cache, or it has dirty areas
                $text = Compress::Zlib::memGzip( encode_utf8($text) );
            }
            $binary_body = 1;
        }
    }    # Otherwise fall through and generate plain text

    # Generate (and print) HTTP headers.
    $this->response->generateHTTPHeaders($hopts);

    if ($binary_body) {
        $this->response->body($text);
    }
    else {
        $this->response->print($text);
    }
}

sub _prepareContext {
    my $this = shift;
    $this->context->{SUPPORTS_PARA_INDENT}   = 1;
    $this->context->{SUPPORTS_PREF_SET_URLS} = 1;
    if ( $this->cfg->data->{Password} ) {
        $this->context->{admin_available} = 1;
    }
}

sub _prepareEngine {
    my $this = shift;
    my @args = @_;
    my $env  = $this->env;
    my $engine;

    # Foswiki::Engine has to determine what environment are we run within and
    # return an object of corresponding class.
    $engine = Foswiki::Engine::start( env => $env, app => $this, @args );

    $this->cfg->data->{Engine} //= ref($engine) if $engine;

    return $engine;
}

sub _preparePrefs {
    my $this = shift;

    my $prefs = $this->create('Foswiki::Prefs');

    return $prefs;
}

sub _readPrefs {
    my $this = shift;

    my $req = $this->request;

    # Push global preferences from %SYSTEMWEB%.DefaultPreferences
    $this->prefs->loadDefaultPreferences();

    # Static session variables that can be expanded in topics when they are
    # enclosed in % signs
    # SMELL: should collapse these into one. The duplication is pretty
    # pointless.
    $this->prefs->setInternalPreferences(
        BASEWEB        => $req->web,
        BASETOPIC      => $req->topic,
        INCLUDINGWEB   => $req->web,
        INCLUDINGTOPIC => $req->topic,
    );

    # Push plugin settings
    $this->plugins->settings();

    # Now the rest of the preferences
    $this->prefs->loadSitePreferences();

    # User preferences only available if we can get to a valid wikiname,
    # which depends on the user mapper.
    my $wn = $this->users->getWikiName( $this->user );
    if ($wn) {
        $this->prefs->setUserPreferences($wn);
    }

    $this->prefs->pushTopicContext( $req->web, $req->topic );
}

# The request attribute default method.
sub _prepareRequest {
    my $this = shift;
    my @args = @_;

    state $preparing = 0;

    if ($preparing) {
        Foswiki::Exception::Fatal->throw(
            text => 'Circular call to _prepareRequest' );
    }
    $preparing = 1;

    # The following is preferable form of Request creation. The request
    # constructor will then initialize itself using $app->engine as the source
    # of information about the environment we're running under.

    # app must be the last key of init hash to avoid occasional override from
    # user-supplied parameters.
    my $request;
    try {
        $request = Foswiki::Request::prepare( app => $this, @args );
    }
    catch {
        Foswiki::Exception::Fatal->rethrow($_);
    }
    finally {
        $preparing = 0;
    };
    return $request;
}

sub _prepareConfig {
    my $this = shift;
    my $cfg = $this->create( 'Foswiki::Config', env => $this->env );
    return $cfg;
}

# Determines what dispatcher to use for the action requested.
sub _prepareDispatcher {
    my $this = shift;
    my $res  = $this->response;

    # Duplicate the entry to avoid changing the original.
    my $dispatcher =
      $this->cfg->data->{SwitchBoard}{ $this->engine->pathData->{action} };
    unless ( defined $dispatcher ) {
        Foswiki::Exception::HTTPError->throw(
            status => 404,
            header => 'Not Found',
            text   => 'The requested URL '
              . (
                $this->engine->pathData->{uri}
                  // 'action:' . $this->engine->pathData->{action}
              )
              . ' was not found on this server.',
        );
    }

    # SMELL Shouldn't it be deprecated?
    if ( ref($dispatcher) eq 'ARRAY' ) {

        # Old-style array entry in switchboard from a plugin
        my @array = @$dispatcher;
        $dispatcher = {
            package  => $array[0],
            function => $array[1],
            context  => $array[2],
        };
    }

    $dispatcher->{package} //= 'Foswiki::UI';
    $dispatcher->{method} //= $dispatcher->{function} || 'dispatch';
    $this->ui( $this->create( $dispatcher->{package} ) );
    $this->_dispatcherAttrs($dispatcher);
}

# If the X-Foswiki-Tickle header is present, this request is an attempt to
# verify that the requested function is available on this Foswiki. Respond with
# the serialised dispatcher, and finish the request. Need to stringify since
# VERSION is a version object.
sub _checkTickle {
    my $this = shift;
    my $req  = $this->request;

    if ( $req->header('X-Foswiki-Tickle') ) {
        my $res  = $this->response;
        my $data = {
            SCRIPT_NAME => $ENV{SCRIPT_NAME},
            VERSION     => $Foswiki::VERSION->stringify(),
            RELEASE     => $Foswiki::RELEASE,
        };
        $res->header( -type => 'application/json', -status => '200' );

        my $d = JSON->new->allow_nonref->encode($data);
        $res->print($d);
        Foswiki::Exception::HTTPResponse->throw;
    }
}

sub _checkReqCache {
    my $this = shift;
    my $req  = $this->request;

    # Get the params cache from the path
    my $cache = $req->param('foswiki_redirect_cache');
    if ( defined $cache ) {
        $req->delete('foswiki_redirect_cache');
    }

    # If the path specifies a cache path, use that. It's arbitrary
    # as to which takes precedence (param or path) because we should
    # never have both at once.
    my $path_info = $req->pathInfo;
    if ( $path_info =~ s#/foswiki_redirect_cache/([a-f0-9]{32})## ) {
        $cache = $1;
        $req->pathInfo($path_info);
    }

    if ( defined $cache && $cache =~ m/^([a-f0-9]{32})$/ ) {

        # implicit untaint required, because $cache may be used in a
        # filename. Note that the cache serialises the method and path_info,
        # which will be restored.
        Foswiki::Request::Cache->new->load( $1, $req );
    }
}

sub _checkBootstrapStage2 {
    my $this = shift;
    my $cfg  = $this->cfg;

    # Phase 2 of Bootstrap.  Web settings require that the Foswiki request
    # has been parsed.
    if ( $cfg->data->{isBOOTSTRAPPING} ) {
        my $phase2_message =
          $cfg->bootstrapWebSettings( $this->request->action );
        $this->systemMessage(
            $this->engine->HTTPCompliant
            ? ( '<div class="foswikiHelp"> ' . $phase2_message . '</div>' )
            : $phase2_message
        );
        $this->systemMessage( $cfg->bootstrapMessage );
    }
}

sub _checkActionAccess {
    my $this            = shift;
    my $req             = $this->request;
    my $dispatcherAttrs = $this->_dispatcherAttrs;

    if (   UNIVERSAL::isa( $Foswiki::engine, 'Foswiki::Engine::CLI' )
        || UNIVERSAL::isa( $Foswiki::engine, 'Foswiki::Engine::Test' ) )
    {
        $dispatcherAttrs->{context}{command_line} = 1;
    }
    elsif (
        defined $req->method
        && (
            (
                defined $dispatcherAttrs->{allow}
                && !$dispatcherAttrs->{allow}->{ uc( $req->method() ) }
            )
            || ( defined $dispatcherAttrs->{deny}
                && $dispatcherAttrs->{deny}->{ uc( $req->method() ) } )
        )
      )
    {
        my $res = $this->response;
        $res->header( -type => 'text/html', -status => '405' );
        $res->print( '<H1>Bad Request:</H1>  The request method: '
              . uc( $req->method() )
              . ' is denied for the '
              . $req->action()
              . ' action.' );
        if ( uc( $req->method() ) eq 'GET' ) {
            $res->print( '<br/><br/>'
                  . 'The <tt><b>'
                  . $req->action()
                  . '</b></tt> script can only be called with the <tt>POST</tt> type method'
                  . '<br/><br/>'
                  . 'For example:<br/>'
                  . '&nbsp;&nbsp;&nbsp;<tt>&lt;form method="post" action="%SCRIPTURL{'
                  . $req->action()
                  . '}%/%WEB%/%TOPIC%"&gt;</tt><br/>'
                  . '<br/><br/>See <a href="http://foswiki.org/System/CommandAndCGIScripts#A_61'
                  . $req->action()
                  . '_61">System.CommandAndCGIScripts</a> for more information.'
            );
        }
        Foswiki::Exception::HTTPResponse->throw;
    }

}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2010 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 1999-2007 Peter Thoeny, peter@thoeny.org
and TWiki Contributors. All Rights Reserved. TWiki Contributors
are listed in the AUTHORS file in the root of this distribution.
Copyright (C) 2005 Martin at Cleaver.org
Copyright (C) 2005-2007 TWiki Contributors

and also based/inspired on Catalyst framework, whose Author is
Sebastian Riedel. Refer to
http://search.cpan.org/~mramberg/Catalyst-Runtime-5.7010/lib/Catalyst.pm
for more credit and liscence details.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
