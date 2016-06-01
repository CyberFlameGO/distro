# See bottom of file for license and copyright

package FoswikiFnTestCase;

=begin TML

---+ package FoswikiFnTestCase

This base class layers some extra stuff on FoswikiTestCase to
try and make life for Foswiki testers even easier at higher levels.
Normally this will be the base class for tests that require an almost
complete user environment. However it does quite a lot of relatively
slow setup, so should not be used for simpler tests (such as those
targeting single classes).

   1. Do not be afraid to modify Foswiki::cfg. You cannot break other
      tests that way.
   2. Never, ever write to any webs except the test_web and
      users_web, or any other test webs you create and remove
      (following the pattern shown below)
   3. The password manager is set to HtPasswdUser, and you can create
      users as shown in the creation of {test_user}
   4. A single user has been pre-registered, wikinamed 'ScumBag'

=cut

use Foswiki();

#use Unit::Response();
use Foswiki::UI::Register();
use Try::Tiny;
use Carp qw(cluck);

our @mails;

use Moo;
use namespace::clean;
extends qw(FoswikiTestCase);

has testSuite => (
    is       => 'ro',
    required => 1,
);
has test_web => (
    is      => 'rw',
    lazy    => 1,
    clearer => 1,
    builder => sub {
        my $testSuite = $_[0]->testSuite;
        return 'Temporary' . $testSuite . 'TestWeb' . $testSuite;
    },
);
has test_topic => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { return 'TestTopic' . $_[0]->testSuite; },
);
has users_web => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { return 'Temporary' . $_[0]->testSuite . 'UsersWeb'; },
);
has test_user_forename => ( is => 'rw', );
has test_user_surname  => ( is => 'rw', );
has test_user_wikiname => ( is => 'rw', );
has test_user_login    => ( is => 'rw', );
has test_user_email    => ( is => 'rw', );
has test_user_cuid     => ( is => 'rw', );
has response           => (
    is        => 'rw',
    clearer   => 1,
    lazy      => 1,
    predicate => 1,
    isa       => Foswiki::Object::isaCLASS( 'response', 'Foswiki::Response' ),
    default   => sub { return $_[0]->app->response; },
);

=begin TML

---++ ObjectMethod loadExtraConfig()
This method can be overridden (overrides should call up to the base class)
to add extra stuff to Foswiki::cfg.

=cut

around loadExtraConfig => sub {
    my $orig = shift;
    my $this = shift;

    $orig->( $this, @_ );

    #$Foswiki::cfg{Store}{Implementation}   = "Foswiki::Store::RcsLite";
    $Foswiki::cfg{Store}{Implementation}   = "Foswiki::Store::PlainFile";
    $Foswiki::cfg{RCS}{AutoAttachPubFiles} = 0;

    $Foswiki::cfg{Register}{AllowLoginName} = 1;
    $Foswiki::cfg{Htpasswd}{FileName} = "$Foswiki::cfg{WorkingDir}/htpasswd";
    unless ( -e $Foswiki::cfg{Htpasswd}{FileName} ) {
        my $fh;
        open( $fh, ">:encoding(utf-8)", $Foswiki::cfg{Htpasswd}{FileName} )
          || die $!;
        close($fh) || die $!;
    }
    $Foswiki::cfg{PasswordManager}       = 'Foswiki::Users::HtPasswdUser';
    $Foswiki::cfg{Htpasswd}{GlobalCache} = 0;
    $Foswiki::cfg{UserMappingManager}    = 'Foswiki::Users::TopicUserMapping';
    $Foswiki::cfg{LoginManager} = 'Foswiki::LoginManager::TemplateLogin';
    $Foswiki::cfg{Register}{EnableNewUserRegistration} = 1;
    $Foswiki::cfg{RenderLoggedInButUnknownUsers} = 0;

    $Foswiki::cfg{Register}{NeedVerification} = 0;
    $Foswiki::cfg{MinPasswordLength}          = 0;
    $Foswiki::cfg{UsersWebName}               = $this->users_web;
};

around set_up => sub {
    my $orig = shift;
    my $this = shift;

    $orig->( $this, @_ );

    my $env = $this->app->cloneEnv;

    # Note: some tests are testing Foswiki::UI which also creates a session
    $this->createNewFoswikiApp(

        #env           => $env,
        requestParams => { initializer => "" },
        engineParams  => {
            initialAttributes =>
              { path_info => "/" . $this->test_web . "/" . $this->test_topic },
        },
    );

    #$this->response( $this->create('Unit::Response') );
    @mails = ();
    $this->app->net->setMailHandler( \&FoswikiFnTestCase::sentMail );
    my $webObject = $this->populateNewWeb( $this->test_web );
    undef $webObject;
    $this->clear_test_topicObject;
    $this->test_topicObject(
        Foswiki::Func::readTopic( $this->test_web, $this->test_topic ) );
    $this->test_topicObject->text("BLEEGLE\n");
    $this->test_topicObject->save( forcedate => ( time() + 60 ) );

    $webObject = $this->populateNewWeb( $this->users_web );
    undef $webObject;

    $this->test_user_forename('Scum');
    $this->test_user_surname('Bag');
    $this->test_user_wikiname(
        $this->test_user_forename . $this->test_user_surname );
    $this->test_user_login('scum');
    $this->test_user_email('scumbag@example.com');
    $this->registerUser(
        $this->test_user_login,   $this->test_user_forename,
        $this->test_user_surname, $this->test_user_email
    );
    $this->test_user_cuid(
        $this->app->users->getCanonicalUserID( $this->test_user_login ) );
};

around tear_down => sub {
    my $orig = shift;
    my $this = shift;

    my $app = $this->app;
    my $cfg = $app->cfg;

    $this->removeWebFixture( $this->test_web );
    $this->removeWebFixture( $cfg->data->{UsersWebName} );
    unlink( $Foswiki::cfg{Htpasswd}{FileName} );
    $orig->( $this, @_ );

};

=begin TML

---++ ObjectMethod removeWeb($web)

Remove a temporary web fixture (data and pub)

=cut

sub removeWeb {
    my ( $this, $web ) = @_;
    $this->removeWebFixture($web);
}

=begin TML

---++ StaticMethod sentMail($net, $mess)

Default implementation for the callback used by Net.pm. Sent mails are
pushed onto a global variable @FoswikiFnTestCase::mails.

=cut

sub sentMail {
    my ( $net, $mess ) = @_;
    push( @mails, $mess );
    return undef;
}

=begin TML

---++ ObjectMethod registerUser($loginname, $forename, $surname, $email)

Can be used by subclasses to register test users.

=cut

sub registerUser {
    my ( $this, $loginname, $forename, $surname, $email ) = @_;

    $this->pushApp;

    my $reqParams = {
        'TopicName'     => ['UserRegistration'],
        'Twk1Email'     => [$email],
        'Twk1WikiName'  => ["$forename$surname"],
        'Twk1Name'      => ["$forename $surname"],
        'Twk0Comment'   => [''],
        'Twk1FirstName' => [$forename],
        'Twk1LastName'  => [$surname],
        'action'        => ['register']
    };

    if ( $Foswiki::cfg{Register}{AllowLoginName} ) {
        $reqParams->{"Twk1LoginName"} = $loginname;
    }

    $this->createNewFoswikiApp(
        requestParams => { initializer => $reqParams, },
        engineParams =>
          { path_info => "/" . $this->users_web . "/UserRegistration", },
    );
    $this->assert(
        $this->app->store->topicExists(
            $this->test_web, $Foswiki::cfg{WebPrefsTopicName}
        )
    );

    $this->app->net->setMailHandler( \&FoswikiFnTestCase::sentMail );
    try {
        my $uiRegister = $this->create('Foswiki::UI::Register');
        $this->captureWithKey(
            register_cgi => \&Foswiki::UI::Register::register_cgi,
            $uiRegister,
        );
    }
    catch {
        my $e = $_;
        if ( $e->isa('Foswiki::OopsException') ) {
            if ( $this->check_dependency('Foswiki,<,1.2') ) {
                $this->assert_str_equals( "attention", $e->{template},
                    $e->stringify() );
                $this->assert_str_equals( "thanks", $e->{def},
                    $e->stringify() );
            }
            else {
                $this->assert_str_equals( "register", $e->{template},
                    $e->stringify() );
                $this->assert_str_equals( "thanks", $e->{def},
                    $e->stringify() );
            }
        }
        elsif ( $e->isa('Foswiki::AccessControlException') ) {
            $this->assert( 0, $e->stringify );
        }
        elsif ( $e->isa('Foswiki::Exception') ) {
            $this->assert( 0, $e->stringify );
        }
        else {
            $this->assert( 0, "expected an oops redirect" );
        }
    };

    # Reload caches
    #$this->createNewFoswikiApp( requestParams => $q );
    #$this->app->net->setMailHandler( \&FoswikiFnTestCase::sentMail );
    $this->popApp;

    # Reset
    $this->app->users->mapping->invalidate;
}

1;
