# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::Configure::UIs::Value
This is the UI object for a single configuration item. It must not be
confused with Foswiki::Configure::Value, which is the value object that
models a configuration item. There will be one corresponding
Foswiki::Configure::Value for each object of this class.

=cut

package Foswiki::Configure::UIs::Value;

use strict;
use warnings;
use Assert;

use Foswiki::Configure::CGI ();

use Foswiki::Configure::UIs::Item ();
our @ISA = ('Foswiki::Configure::UIs::Item');

=begin TML

---++ ObjectMethod renderHtml($valobj, $root, ...) -> ($html, \%properties)
   * =$valobj= - Foswiki::Configure::Value object in the model
   * =$root= - Foswiki::Configure::UIs::Root

Implements Foswiki::Configure::UIs::Item

Generates the appropriate HTML for getting a presenting the configure the
entry.

=cut

sub renderHtml {
    my ( $this, $valobj, $root ) = @_;

    my $output = '';

    return '' if $valobj->{hidden};

    my $type =
      Foswiki::Configure::TypeUI::load( $valobj->{typename}, $valobj->{keys} );

    my $keys     = $valobj->{keys};
    my $feedback = $valobj->{FEEDBACK};

    # Check with the type for any default options; these might add CHECK or
    # FEEDBACK data, default to EXPERT - etc.

    if ( $type->can('defaultOptions') ) {
        my $updated = $type->defaultOptions($valobj);
        return '' if ( $valobj->{HIDDEN} );
        $feedback = $valobj->{FEEDBACK};
        Carp::confess "$valobj $valobj->{keys} '$feedback' $type"
          unless !defined $feedback || ref($feedback) eq 'ARRAY';
    }
    Carp::confess "$valobj $valobj->{keys} '$feedback' $type"
      unless !defined $feedback || ref($feedback) eq 'ARRAY';

    my $isExpert  = $valobj->hasDeep('EXPERT');
    my $displayIf = $valobj->{DISPLAY_IF};
    my $enableIf  = $valobj->{ENABLE_IF};
    my $info      = $valobj->{desc};
    my $isUnused  = 0;
    my $isBroken  = 0;
    my $reporter = Foswiki::Configure::Reporter->new();

    my $checker = Foswiki::Configure::UI::loadChecker( $valobj );
    if ($checker) {
        eval { $checker->check_current_value($reporter); };
        if ($@) {
            $reporter->ERROR( "Checker ("
                              . ref($checker)
                              . ") for $keys failed: check for .spec errors:  <pre>$@</pre>" );
        }
        if ($reporter->errorCount() > 0) {

            # something wrong
            $isBroken = 1;
        }
    }

    # Hide rows if this is an EXPERT setting in non-experts mode, or
    # this is a hidden or unused value
    my @cssClasses = (qw/configureItemKeys/);
    push @cssClasses, 'configureExpert' if $isExpert;
    if ( $isUnused || !$isBroken && $valobj->{hidden} ) {
        push @cssClasses, 'foswikiHidden';
    }

    # Hidden type information used when passing to 'save'
    my $hiddenTypeOf =
      Foswiki::Configure::UI::hidden( 'TYPEOF:' . $keys, $valobj->{typename} );

    my $index = '';
    my $haslabel;    # label replaces {key}{s}
    if ( defined( my $label = $valobj->{LABEL} ) ) {
        $index .= $label;
        $haslabel = 1;
    }
    else {
        $index .= $keys;
    }
    $index .= " <span class='configureMandatory'>required</span>"
      if $valobj->{MANDATORY};

    if ( defined $feedback ) {
        my $buttons = "";
        my $bn      = 0;
        my $col     = 0;
        my $ac      = 0;
        my ( $tbl, %bn );
        $tbl ||= exists $_->{col} foreach (@$feedback);
        $buttons =
          ( $haslabel ? '' : '<br />' )
          . '<table class="configureFeedbackArray"><tbody>'
          if ($tbl);
        foreach my $fb (@$feedback) {
            $bn++;
            my $n = $fb->{button} || $bn;
            if ( $bn{$n} || $bn < 0 ) {
                $reporter->ERROR(
".spec duplicates feedback button $n for $keys; duplicate skipped"
                );
                next;
            }
            $bn{$n} = 1;
            my $invisible = '';
            my $pinfo     = '';
            my $fbl       = $fb->{label};
            if ( $fb->{pinfo} ) {
                $pinfo = qq{, '$fb->{pinfo}'};
            }
            if ( $fbl eq '~' ) {
                $invisible = qq{ style="display:none;"};
                $ac        = 1;
            }
            else {
                if ($tbl) {
                    my $fbc = $fb->{col} || $col + 1;
                    if ( $col == 0 || $fbc < $col ) {
                        $buttons .= '<tr>';
                        $col = 0;
                    }
                    $buttons .= '<td>' while ( $col++ < ( $fbc - 1 ) );
                    $fbc = $fb->{span};
                    $buttons .= '<td' . ( $fbc ? " colspan='$fbc'>" : '>' );
                }
                else {
                    $buttons .=
                      ( !$haslabel && $col % 3 == 0 ) ? "<br />" : ' ';
                }
                $col++;
            }
            $fbl =~
              s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&'*<=>@[_\|])/'&#'.ord($1).';'/ge
              unless ( $fb->{html} );
            my $fbc = $fb->{class};
            $fbc = ( defined $fbc ? ' $fbc' : '' );
            my $val = $fb->{value} || $fbl;
            my $title = $fb->{title};
            if ( defined $title ) {
                $title =~
s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&'*<=>@[_\|])/'&#'.ord($1).';'/ge;
                $title = qq{ title="$title"};
            }
            else {
                $title = '';
            }
            $buttons .=
qq{<button type="button" id="${keys}feedreq$n" value="$val" class="configureFeedbackButton$n $fbc" onclick="return doFeedback(this$pinfo);"$invisible$title>$fbl</button>};
            $buttons .=
qq{<span style='display:none' id="${keys}feedmsg$n"><span class="configureFeedbackWaitText">$fb->{wait}</span></span>}
              if ( $fb->{wait} );
        }
        $buttons .= '</tbody></table>' if ($tbl);
        $feedback = qq{<span class="foswikiJSRequired">$buttons</span>};
    }
    else {
        $feedback = '';
    }
    my ( $itemErrors, $itemWarnings ) =
      ( ( $valobj->{errorcount} || 0 ), ( $valobj->{warningcount} || 0 ) );
    $index .= Foswiki::Configure::UI::hidden(
        "${keys}errors",
        "$itemErrors $itemWarnings",
        !( $itemErrors + $itemWarnings )
    );
    push @cssClasses, 'configureDisplayForced'
      if ( $itemErrors || $itemWarnings );

    my $resetToDefaultLinkText = '';

    if ( $valobj->{typename} ne 'NULL' ) {

        # Since Feedback allows values to change without a screen
        # refresh, we always generate a ResetToDefault link.
        # This can result in "stored" and "default" values
        # being the same, but I don't think it matters...
        my $valueString = $valobj->{default};
        $valueString = '' unless defined $valueString;

        # URL encode parameter name and value
        my $safeKeys = $this->urlEncode($keys);

        my $defaultDisplayValue = $this->urlEncode($valueString);

        if (   $type->isa('Foswiki::Configure::TypeUIs::BOOLEAN')
            || $type->isa('Foswiki::Configure::TypeUIs::NUMBER') )
        {
            $defaultDisplayValue ||= '0';
        }

        #$valueString =~ s/\'/\\'/go;
        #$valueString =~ s/\n/\\n/go;
        $valueString = $this->urlEncode($valueString);

        $resetToDefaultLinkText .= <<HERE;
<a href='#' name="${keys}deflink" title='$defaultDisplayValue' class='$valobj->{typename} configureDefaultValueLink' onclick="return resetToDefaultValue(this,'$valobj->{typename}','$safeKeys','$valueString')"><span class="configureDefaultValueLinkLabel">&nbsp;</span><span class='configureDefaultValueLinkValue'>$defaultDisplayValue</span></a>
HERE

        $resetToDefaultLinkText =~ s/^[[:space:]]+//s;    # trim at start
        $resetToDefaultLinkText =~ s/[[:space:]]+$//s;    # trim at end
    }

    my $control      = '';
    my $enable       = '&nbsp;';
    my $currentValue = $root->{valuer}->currentValue($valobj);
    unless ( defined $currentValue ) {

        # Could be a corrupt spec file, or an item materialized
        # without a spec entry.  Assume the latter know what
        # they are doing.  (They won't have a symbol entry).
        # If a materialized item should be checked, see LoadSpec
        # for the format of a defined entry.

        if ( defined $valobj->{defined_at} ) {
            $control = $this->WARN(
"Item $valobj->{keys} declared at $valobj->{defined_at}->[0]:$valobj->{defined_at}->[1] may not have an undefined value."
                  . (
                    defined $valobj->{default}
                    ? "Default is $valobj->{default}"
                    : ''
                  )
                  . " Check for problems with LocalSite.cfg."
            );
            $currentValue = '';
        }
    }

    if ( $isUnused && !$isBroken ) {

        # Unused and not broken - just pass the value through a hidden
        $control .= Foswiki::Configure::UI::hidden( $keys, $currentValue );
        $resetToDefaultLinkText = '';
    }
    else {

        # Generate a prompter for the value.
        my $promptclass = $valobj->{typename} || '';
        $promptclass .= ' configureMandatory' if ( $valobj->{MANDATORY} );
        if ( $valobj->{MUST_ENABLE} ) {
            my $name = "${keys}enabled";
            $hiddenTypeOf .=
              Foswiki::Configure::UI::hidden( "TYPEOF:$name", 'BOOLEAN' );
            $enable =
"<input type=\"checkbox\" name=\"$name\" class=\"BOOLEAN configureItemEnable\"";

            # Enable iff there is a current value and it isn't the default
            $enable .= 'checked="checked"'
              if ( defined $currentValue
                && $currentValue ne eval $valobj->{default} );
            $enable .= qq{ onchange="return enableChanged(this,'$keys');">};
        }

        eval {
            $control .= $type->prompt( $valobj, $currentValue, $promptclass );
        };
        ASSERT( !$@, $@ ) if DEBUG;
    }

    my $helpText;
    my $helpTextLink = '';
    my $tip          = '';
    if ($info) {
        $tip = $root->{controls}->addTooltip($info);
        my $scriptName = Foswiki::Configure::CGI::getScriptName();
        my $image =
"<img src='${Foswiki::Configure::resourceURI}icon_info.png' alt='Show info' title='Show info' />";
        $helpTextLink =
"<span class='foswikiMakeVisible'><a href='#' onclick='return toggleInfo($tip);'>$image</a></span>";
        $helpText = CGI::td(
            {
                class   => 'configureItemRow',
                colspan => 2
            },
            $info
        );
    }

    my %props = ( 'data-keys' => $keys );
    $props{class} = join( ' ', @cssClasses ) if (@cssClasses);
    $props{'data-displayif'} = $displayIf if $displayIf;
    $props{'data-enableif'}  = $enableIf  if $enableIf;
    my $changeAction = $valobj->{CHANGE} || '';
    if ( $valobj->{MUST_ENABLE} ) {
        $changeAction = << 'ENABLEJS' . $changeAction;
if( ele.value.length ) {
    $('[name="' + configure.utils.quoteName(ele.name.replace(/\}$/,'_}')) + '"]').each(function() {
        if( !this.checked ) {
            this.checked = true;
        }
        return true;
    });
}
ENABLEJS
    }
    $props{'data-change'} = $changeAction if $changeAction;

    my $expander = '';
    $expander .= ' ' if ($helpTextLink);
    $expander .=
qq{<span id="${keys}expander" class="configureFeedbackExpander foswikiJSRequired">};
    $expander .=
qq{<a href='#' onclick="return feedback.toggleXpndr(this,'\Q${keys}status\E');" ><img src="${Foswiki::Configure::resourceURI}toggleopen.png" alt="Expand/condense feedback" title="Expand/condense feedback" /></a></span>};
    $helpTextLink .= $expander;

    $check =
"<div id=\"${keys}status\" class=\"configureFeedback configureFeedbackExpanded\" >" . $reporter->html() . "</div>";

    if ($helpText) {
        $output .= CGI::Tr(
            \%props,
            CGI::th("$index$feedback$hiddenTypeOf")
              . CGI::td(
                { colspan => 99, },
                CGI::table(
                    { class => 'configureItemTable' },
                    CGI::Tr(
                        {
                            id => "info_$tip",
                            class =>
'configureInfoText foswikiMakeHidden configureItemRow',
                        },
                        $helpText
                      )
                      . CGI::Tr(
                        { class => 'configureItemRow', },
                        CGI::td(
                            { class => 'configureItemEnable configureItemRow' },
                            $enable
                          )
                          . CGI::td( { class => 'configureItemRow' },
                            "$control&nbsp;$resetToDefaultLinkText".$reporter->html() )
                          . CGI::td(
                            { class => 'configureHelp configureItemRow' },
                            $helpTextLink
                          )
                      )
                )
              )
        ) . "\n";
    }
    else {
        $output .= CGI::Tr( \%props,
                CGI::th("$index$feedback$hiddenTypeOf")
              . CGI::td( { class => 'configureItemEnable' }, $enable )
              . CGI::td("$control&nbsp;$resetToDefaultLinkText".$reporter->html())
              . CGI::td( { class => 'configureHelp' }, $helpTextLink ) )
          . "\n";
    }
    return (
        $output,
        {
            expert => $isExpert,
            info   => ( $info ne '' ),
            broken => $isBroken,
            unused => $isUnused,
            hidden => $valobj->{hidden}
        }
    );
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
