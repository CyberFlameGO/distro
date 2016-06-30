package HierarchicalWebsTests;
use v5.14;

use Foswiki();
use Try::Tiny;
use Foswiki::AccessControlException ();

use Moo;
use namespace::clean;
extends qw( FoswikiStoreTestCase );

has sub_web      => ( is => 'rw', );
has sub_web_path => ( is => 'rw', );

around set_up => sub {
    my $orig = shift;
    my $this = shift;

    $this->app->cfg->data->{DisableAllPlugins} = 1;

    $this->app->cfg->data->{EnableHierarchicalWebs} = 1;

    $this->sub_web("Subweb");
    $this->sub_web_path( $this->test_web . "/" . $this->sub_web );
    $orig->( $this, @_ );
};

around set_up_for_verify => sub {
    my $orig = shift;
    my $this = shift;

    $this->createNewFoswikiApp;

    # subweb of test web, so default tear_down will nosh it
    my $webObject = $this->populateNewWeb( $this->sub_web_path );
};

sub verify_createSubSubWeb {
    my $this = shift;

    $this->createNewFoswikiApp;
    my $webTest   = 'Item0';
    my $webObject = $this->populateNewWeb( $this->sub_web_path . "/$webTest" );
    undef $webObject;
    $this->assert(
        $this->app->store->webExists( $this->sub_web_path . "/$webTest" ) );

    $webTest   = 'Item0_';
    $webObject = $this->populateNewWeb( $this->sub_web_path . "/$webTest" );
    undef $webObject;
    $this->assert(
        $this->app->store->webExists( $this->sub_web_path . "/$webTest" ) );

    return;
}

sub verify_createSubWebTopic {
    my $this = shift;

    $this->createNewFoswikiApp;
    my ($topicObject) =
      Foswiki::Func::readTopic( $this->sub_web_path, $this->test_topic );
    $topicObject->text("page stuff\n");
    $topicObject->save();
    undef $topicObject;
    $this->assert(
        $this->app->store->topicExists(
            $this->sub_web_path, $this->test_topic
        )
    );

    return;
}

sub verify_include_subweb_non_wikiword_topic {
    my $this = shift;
    $this->createNewFoswikiApp;
    my $user = $this->app->user;

    my $baseTopic    = "Include" . $this->sub_web . "NonWikiWordTopic";
    my $includeTopic = 'Topic';
    my $testText     = 'TEXT';
    my $sub_web_path = $this->sub_web_path;

    # create the (including) page
    my ($topicObject) = Foswiki::Func::readTopic( $sub_web_path, $baseTopic );
    $topicObject->text( <<"TOPIC" );
%INCLUDE{ "$sub_web_path/$includeTopic" }%
TOPIC
    $topicObject->save();
    undef $topicObject;
    $this->assert(
        $this->app->store->topicExists( $this->sub_web_path, $baseTopic ) );

    # create the (included) page
    ($topicObject) =
      Foswiki::Func::readTopic( $this->sub_web_path, $includeTopic );
    $topicObject->text($testText);
    $topicObject->save();
    undef $topicObject;
    $this->assert(
        $this->app->store->topicExists( $this->sub_web_path, $includeTopic ) );

    # verify included page's text
    ($topicObject) =
      Foswiki::Func::readTopic( $this->sub_web_path, $includeTopic );
    $this->assert_matches( qr/$testText\s*$/, $topicObject->text );
    undef $topicObject;

    # base page should evaluate (more or less) to the included page's text
    ($topicObject) =
      Foswiki::Func::readTopic( $this->sub_web_path, $baseTopic );
    my $text = $topicObject->text;
    $text = $topicObject->expandMacros($text);
    $this->assert_matches( qr/$testText\s*$/, $text );

    return;
}

sub verify_create_subweb_with_same_name_as_a_topic {
    my $this = shift;
    $this->createNewFoswikiApp;
    my $user = $this->app->user;

    $this->test_topic( $this->sub_web );
    my $testText = 'TOPIC';

    # create the page
    my ($topicObject) =
      Foswiki::Func::readTopic( $this->sub_web_path, $this->test_topic );
    $topicObject->text($testText);
    $topicObject->save();
    $this->assert(
        $this->app->store->topicExists(
            $this->sub_web_path, $this->test_topic
        )
    );

    my ($meta) =
      Foswiki::Func::readTopic( $this->sub_web_path, $this->test_topic );
    $this->assert_matches( qr/$testText\s*$/, $topicObject->text );
    undef $topicObject;
    undef $meta;

    # create the subweb with the same name as the page
    my $webObject =
      $this->populateNewWeb( $this->sub_web_path . "/" . $this->test_topic );
    $this->assert(
        $this->app->store->webExists(
            $this->sub_web_path . "/" . $this->test_topic
        )
    );

    ($topicObject) =
      Foswiki::Func::readTopic( $this->sub_web_path, $this->test_topic );
    $this->assert_matches( qr/$testText\s*$/, $topicObject->text );
    undef $topicObject;

    $webObject->removeFromStore();
    undef $webObject;

    $this->assert(
        !$this->app->store->webExists(
            $this->sub_web_path . "/" . $this->test_topic
        )
    );

    return;
}

sub verify_create_sub_web_missingParent {
    my $this = shift;

    $this->createNewFoswikiApp;
    my $user = $this->app->user;

    my $webObject = $this->getWebObject( "Missingweb/" . $this->sub_web );

    try {
        $webObject->populateNewWeb();
        $this->assert('No error thrown from populateNewWe() ');
    }
    catch {
        my $e = $_;
        Foswiki::Exception::Fatal->rethrow($e) unless ref($e);
        my $errStr = $e->stringify;
        $this->assert_matches( qr/^Parent web Missingweb does not exist.*/,
            $errStr, "Unexpected error $errStr" );
    };
    undef $webObject;
    $this->assert(
        !$this->app->store->webExists( "Missingweb/" . $this->sub_web ) );
    $this->assert( !$this->app->store->webExists("Missingweb") );

    return;
}

sub verify_createWeb_InvalidBase {
    my $this = shift;

    $this->createNewFoswikiApp;

    my $user = $this->app->user;

    my $webTest   = 'Item0';
    my $webObject = $this->getWebObject( $this->sub_web_path . "/$webTest" );

    try {
        $webObject->populateNewWeb("Missingbase");
        $this->assert('No error thrown from populateNewWe() ');
    }
    catch {
        my $e = $_;
        Foswiki::Exception::Fatal->rethrow($e) unless ref($e);
        my $errStr = $e->stringify;
        $this->assert_matches( qr/^Template web Missingbase does not exist.*/,
            $errStr, "Unexpected error $errStr" );
    };
    undef $webObject;
    $this->assert(
        !$this->app->store->webExists( $this->sub_web_path . "/$webTest" ) );

    return;
}

sub verify_createWeb_hierarchyDisabled {
    my $this = shift;
    $this->app->cfg->data->{EnableHierarchicalWebs} = 0;

    $this->createNewFoswikiApp;

    my $user = $this->app->user;

    my $webTest = 'Item0';
    my $webObject =
      $this->getWebObject( $this->sub_web_path . "/$webTest" . 'x' );

    try {
        $webObject->populateNewWeb();
        $this->assert('No error thrown from populateNewWe() ');
    }
    catch {
        my $e = shift;
        Foswiki::Exception::Fatal->rethrow($e) unless ref($e);
        my $errStr = $e->stringify;
        $this->assert_matches(
            qr/^Unable to create .* Hierarchical webs are disabled.*/,
            $errStr, "Unexpected error '$errStr'" );
    };
    undef $webObject;
    $this->assert(
        !$this->app->store->webExists(
            $this->sub_web_path . "/$webTest" . 'x'
        )
    );

    return;
}

sub verify_url_parameters {
    my $this = shift;

#TODO: I don't know why this topic exists at the start of this test - it should not be.
    if ( Foswiki::Func::topicExists( $this->test_web, $this->sub_web ) ) {
        my ($t) = Foswiki::Func::readTopic( $this->test_web, $this->sub_web );
        $t->removeFromStore();
    }

    $this->createNewFoswikiApp;
    $this->assert(
        !Foswiki::Func::topicExists( $this->test_web, $this->sub_web ) );
    my $user = $this->app->user;

    # Now query the subweb path. We should get the webhome of the subweb.

    $this->createNewFoswikiApp(
        user          => $this->app->cfg->data->{DefaultUserLogin},
        requestParams => {
            initializer => {
                action => 'view',
                topic  => $this->sub_web_path,
            },
        },
    );

    if ( $this->check_dependency('Foswiki,>=,1.2') ) {

#there is no topic named $this->sub_web, so we convert the req to the existant web
#Item9225: an improvement on goto a web even when it doesn't exist
        $this->assert_str_equals( $this->sub_web_path,
            $this->app->request->web );
        $this->assert_str_equals( "WebHome", $this->app->request->topic );
    }
    else {
        # Item3243:  PTh and haj suggested to change the spec
        $this->assert_str_equals( $this->test_web, $this->app->request->web );
        $this->assert_str_equals( $this->sub_web,  $this->app->request->topic );
    }

    # make a topic with the same name as the subweb. Now the previous
    # query should hit that topic
    my ($topicObject) =
      Foswiki::Func::readTopic( $this->test_web, $this->sub_web );
    $topicObject->text("nowt");
    $topicObject->save();
    undef $topicObject;

    $this->createNewFoswikiApp(
        user          => $this->app->cfg->data->{DefaultUserLogin},
        requestParams => {
            initializer => {
                action => 'view',
                topic  => $this->sub_web_path,
            }
        },
    );

    $this->assert_str_equals( $this->test_web, $this->app->request->web );
    $this->assert_str_equals( $this->sub_web,  $this->app->request->topic );

    # try a query with a non-existant topic in the subweb.
    $this->createNewFoswikiApp(
        user          => $this->app->cfg->data->{DefaultUserLogin},
        requestParams => {
            initializer => {
                action => 'view',
                topic  => $this->sub_web_path . "/NonExistant",
            },
        },
    );

    $this->assert_str_equals( $this->sub_web_path, $this->app->request->web );
    $this->assert_str_equals( 'NonExistant',       $this->app->request->topic );

    # Note that this implictly tests %TOPIC% and %WEB% expansions, because
    # they come directly from {webName}

    return;
}

# Check expansion of [[TestWeb]] in TestWeb/NonExistant
# It should expand to creation of topic TestWeb
sub test_squab_simple {
    my $this = shift;

    $this->createNewFoswikiApp(
        user          => $this->app->cfg->data->{DefaultUserLogin},
        requestParams => { initializer => '', },
        engineParams  => {
            initialAttributes =>
              { path_info => "/" . $this->test_web . "/NonExistant", },
        },
    );

    my $text = "[[" . $this->test_web . "]]";
    my ($topicObject) =
      Foswiki::Func::readTopic( $this->test_web, 'NonExistant' );
    $text = $topicObject->renderTML($text);
    undef $topicObject;
    my $test_web = $this->test_web;
    $this->assert_matches(
qr!<a class="foswikiNewLink" href=".*?/$test_web/$test_web\?topicparent=$test_web\.NonExistant!,
        $text
    );

    return;
}

# Check expansion of [[$this->sub_web]] in TestWeb/NonExistant.
# It should expand to a create link to the TestWeb/$this->sub_web topic with
# TestWeb.WebHome as the parent
sub test_squab_subweb {
    my $this = shift;

    # Make a query that should set topic=$test$this->sub_web
    $this->createNewFoswikiApp(
        user          => $this->app->cfg->data->{DefaultUserLogin},
        requestParams => { initializer => '', },
        engineParams  => {
            initialAttributes =>
              { path_info => "/" . $this->test_web . "/NonExistant", },
        },
    );

    my $text = "[[" . $this->sub_web . "]]";
    my ($topicObject) =
      Foswiki::Func::readTopic( $this->test_web, 'NonExistant' );
    $text = $topicObject->renderTML($text);
    undef $topicObject;
    my $sub_web_path = $this->sub_web_path;
    my $test_web     = $this->test_web;
    $this->assert_matches(
qr!<a class="foswikiNewLink" href=".*?/$sub_web_path\?topicparent=$test_web.NonExistant!,
        $text
    );

    return;
}

# Check expansion of [[TestWeb.$this->sub_web]] in TestWeb/NonExistant.
# It should expand to create topic TestWeb/$this->sub_web
sub test_squab_subweb_full_path {
    my $this = shift;

    my $test_web     = $this->test_web;
    my $sub_web      = $this->sub_web;
    my $sub_web_path = $this->sub_web_path;

    # Make a query that should set topic=$test$this->sub_web
    $this->createNewFoswikiApp(
        user          => $this->app->cfg->data->{DefaultUserLogin},
        requestParams => { initializer => '', },
        engineParams =>
          { initialAttributes => { path_info => "/$test_web/NonExistant", }, },
    );

    my $text = "[[$test_web.$sub_web]]";
    my ($topicObject) = Foswiki::Func::readTopic( $test_web, 'NonExistant' );
    $text = $topicObject->renderTML($text);
    undef $topicObject;
    $this->assert_matches(
qr!<a class="foswikiNewLink" href=".*?/$sub_web_path\?topicparent=$test_web.NonExistant!,
        $text
    );

    return;
}

# Check expansion of [[$this->sub_web]] in TestWeb/NonExistant.
# It should expand to TestWeb/$this->sub_web
sub test_squab_subweb_wih_topic {
    my $this = shift;

    # Make a query that should set topic=$test$this->sub_web
    $this->createNewFoswikiApp(
        user          => $this->app->cfg->data->{DefaultUserLogin},
        requestParams => { initializer => '', },
        engineParams  => {
            initialAttributes =>
              { path_info => "/" . $this->test_web . "/NonExistant" },
        },
    );

    my ($topicObject) =
      Foswiki::Func::readTopic( $this->test_web, $this->sub_web );
    $topicObject->text('');
    $topicObject->save();
    undef $topicObject;
    $this->assert(
        $this->app->store->topicExists( $this->test_web, $this->sub_web ) );

    my $text = "[[" . $this->sub_web . "]]";
    ($topicObject) = Foswiki::Func::readTopic( $this->test_web, 'NonExistant' );
    $text = $topicObject->renderTML($text);
    undef $topicObject;
    my $scripturl =
        $this->app->cfg->getScriptUrl( 0, 'view' ) . "/"
      . $this->test_web . "/"
      . $this->sub_web;
    my $sub_web = $this->sub_web;
    $this->assert_matches( qr!<a href="$scripturl">$sub_web</a>!, $text );

    return;
}

# Check expansion of [[TestWeb.$this->sub_web]] in TestWeb/NonExistant.
# It should expand to TestWeb/$this->sub_web
sub test_squab_full_path_with_topic {
    my $this = shift;

    # Make a query that should set topic=$test$this->sub_web
    $this->createNewFoswikiApp(
        user          => $this->app->cfg->data->{DefaultUserLogin},
        requestParams => { initializer => '', },
        engineParams  => {
            initialAttributes =>
              { path_info => "/" . $this->test_web . "/NonExistant", },
        },
    );

    my $scripturl =
        $this->app->cfg->getScriptUrl( 0, 'view' ) . "/"
      . $this->test_web . "/"
      . $this->sub_web;

    $this->createNewFoswikiApp(
        user          => $this->app->cfg->data->{DefaultUserLogin},
        requestParams => { initializer => '', },
        engineParams  => {
            initialAttributes =>
              { path_info => "/" . $this->test_web . "/NonExistant", },
        },
    );

    my ($topicObject) =
      Foswiki::Func::readTopic( $this->test_web, $this->sub_web );
    $topicObject->text('');
    $topicObject->save();
    undef $topicObject;
    $this->assert(
        $this->app->store->topicExists( $this->test_web, $this->sub_web ) );

    my $text = "[[" . $this->test_web . "." . $this->sub_web . "]]";
    ($topicObject) = Foswiki::Func::readTopic( $this->test_web, 'NonExistant' );
    $text = $topicObject->renderTML($text);
    undef $topicObject;

    my $test_web = $this->test_web;
    my $sub_web  = $this->sub_web;
    $this->assert_matches( qr!<a href="$scripturl">$test_web.$sub_web</a>!,
        $text );

    return;
}

# Check expansion of [[TestWeb.$this->sub_web.WebHome]] in TestWeb/NonExistant.
# It should expand to TestWeb/$this->sub_web/WebHome
sub test_squab_path_to_topic_in_subweb {
    my $this = shift;

    # Make a query that should set topic=$test$this->sub_web
    $this->createNewFoswikiApp(
        user          => $this->app->cfg->data->{DefaultUserLogin},
        requestParams => { initializer => '', },
        engineParams  => {
            initialAttributes =>
              { path_info => "/" . $this->test_web . "/NonExistant", },
        },
    );

    my ($topicObject) =
      Foswiki::Func::readTopic( $this->test_web, $this->sub_web );
    $topicObject->text('');
    $topicObject->save();
    undef $topicObject;
    $this->assert(
        $this->app->store->topicExists( $this->test_web, $this->sub_web ) );

    my $text = "[[" . $this->test_web . "." . $this->sub_web . ".WebHome]]";
    ($topicObject) = Foswiki::Func::readTopic( $this->test_web, 'NonExistant' );
    $text = $topicObject->renderTML($text);
    undef $topicObject;

    my $scripturl =
      Foswiki::Func::getScriptUrl( $this->test_web . "/" . $this->sub_web,
        $this->app->cfg->data->{HomeTopicName}, 'view' );
    ($scripturl) = $scripturl =~ m/https?:\/\/[^\/]+(\/.*)/;

    my $test_web = $this->test_web;
    my $sub_web  = $this->sub_web;
    $this->assert_matches(
qr!<a class=.foswikiNewLink. href=.*?/$test_web/$sub_web/WebHome\?topicparent=$test_web\.NonExistant!,
        $text
    );

    return;
}

=pod

---++ Pre nested web linking 

twiki used to remove /'s without replacement, and 

=cut

sub verify_PreNestedWebsLinking {
    my $this = shift;

    Foswiki::Func::saveTopic( $this->test_web, '6to4enronet', undef,
        "Some text" );
    Foswiki::Func::saveTopic( $this->test_web, 'Aou1aplpnet', undef,
        "Some text" );
    Foswiki::Func::saveTopic( $this->test_web, 'MemberFinance', undef,
        "Some text" );
    Foswiki::Func::saveTopic( $this->test_web, 'MyNNABugsfeatureRequests',
        undef, "Some text" );
    Foswiki::Func::saveTopic( $this->test_web, 'Transfermergerrestructure',
        undef, "Some text" );
    Foswiki::Func::saveTopic( $this->test_web, 'ArthsChecklist', undef,
        "Some text" );

    my $source = <<END_SOURCE;
SiteChanges
[[6to4.nro.net]]
[[Member/Finance]]
[[MyNNA bugs/feature requests]]
[[Transfer/merger/restructure]]
[[Arth's checklist]]
[[WebHome]]
[[WebPreferences]]
END_SOURCE

    my $expected = <<"END_EXPECTED";
[[System.SiteChanges][SiteChanges]]
[[6to4.nro.net]]
[[Member/Finance]]
[[MyNNA bugs/feature requests]]
[[Transfer/merger/restructure]]
[[Arth's checklist]]
[[System.WebHome][WebHome]]
[[WebPreferences]]
END_EXPECTED

    _trimSpaces($source);
    _trimSpaces($expected);

    $source = Foswiki::Func::expandCommonVariables($source);
    $source = Foswiki::Func::expandCommonVariables($source);
    $source =
      Foswiki::Func::renderText( $source, $this->test_web, "TestTopic" );

    #print " RENDERED = $source \n";
    $this->assert_str_not_equals( $expected, $source );

    #DO it without find elsewhere..
    #turned off.
    #turn off nested webs and add / into NameFilter
    $this->app->cfg->data->{FindElsewherePlugin}{CairoLegacyLinking} = 0;
    $this->app->cfg->data->{EnableHierarchicalWebs} = 0;
    $this->app->cfg->data->{NameFilter} = $this->app->cfg->data->{NameFilter} =
      '[\/\\s\\*?~^\\$@%`"\'&;|<>\\[\\]#\\x00-\\x1f]';
    $this->createNewFoswikiApp(
        requestParams => { initializer => '', },
        engineParams  => {
            initialAttributes =>
              { path_info => "/" . $this->test_web . "/TestTopic", },
        },
    );

    $source = <<END_SOURCE;
SiteChanges
[[6to4.enro.net]]
[[aou1.aplp.net]]
[[Member/Finance]]
[[MyNNA bugs/feature requests]]
[[Transfer/merger/restructure]]
[[Arth's checklist]]
[[WebHome]]
[[WebPreferences]]
[[does.not.exist]]
END_SOURCE

    $expected = <<"END_EXPECTED";
[[System.SiteChanges][SiteChanges]]
[[6to4enronet][6to4.enro.net]]
[[Aou1aplpnet][aou1.aplp.net]]
[[MemberFinance][Member/Finance]]
[[MyNNABugsfeatureRequests][MyNNA bugs/feature requests]]
[[Transfermergerrestructure][Transfer/merger/restructure]]
[[ArthsChecklist][Arth's checklist]]
[[System.WebHome][WebHome]]
[[WebPreferences]]
[[does.not.exist]]
END_EXPECTED

    _trimSpaces($source);
    _trimSpaces($expected);

    $source = Foswiki::Func::expandCommonVariables($source);
    $source = Foswiki::Func::expandCommonVariables($source);
    $source =
      Foswiki::Func::renderText( $source, $this->test_web, "TestTopic" );

    #print " RENDERED = $source \n";
    $this->assert_str_not_equals( $expected, $source );

}

sub _trimSpaces {

    #my $text = $_[0]

    $_[0] =~ s/^[[:space:]]+//s;    # trim at start
    $_[0] =~ s/[[:space:]]+$//s;    # trim at end
}

1;
