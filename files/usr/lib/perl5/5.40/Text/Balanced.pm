

package Text::Balanced;


use 5.008001;
use strict;
use Exporter ();

use vars qw { $VERSION @ISA %EXPORT_TAGS };
BEGIN {
    $VERSION     = '2.06';
    @ISA         = 'Exporter';
    %EXPORT_TAGS = (
        ALL => [ qw{
            &extract_delimited
            &extract_bracketed
            &extract_quotelike
            &extract_codeblock
            &extract_variable
            &extract_tagged
            &extract_multiple
            &gen_delimited_pat
            &gen_extract_tagged
            &delimited_pat
        } ],
    );
}

Exporter::export_ok_tags('ALL');

our $RE_PREREGEX_PAT = qr#(
    [!=]~
    | split|grep|map
    | not|and|or|xor
)#x;
our $RE_EXPR_PAT = qr#(
    (?:\*\*|&&|\|\||<<|>>|//|[-+*x%^&|.])=?
    | /(?:[^/])
    | =(?!>)
    | return
    | [\(\[]
)#x;
our $RE_NUM = qr/\s*[+\-.0-9][+\-.0-9e]*/i; # numerical constant

our %ref2slashvalid; # is quotelike /.../ pattern valid here for given textref?
our %ref2qmarkvalid; # is quotelike ?...? pattern valid here for given textref?


sub _failmsg {
    my ($message, $pos) = @_;
    $@ = bless {
        error => $message,
        pos   => $pos,
    }, 'Text::Balanced::ErrorMsg';
}

sub _fail {
    my ($wantarray, $textref, $message, $pos) = @_;
    _failmsg $message, $pos if $message;
    return (undef, $$textref, undef) if $wantarray;
    return;
}

sub _succeed {
    $@ = undef;
    my ($wantarray,$textref) = splice @_, 0, 2;
    my ($extrapos, $extralen) = @_ > 18
        ? splice(@_, -2, 2)
        : (0, 0);
    my ($startlen, $oppos) = @_[5,6];
    my $remainderpos = $_[2];
    if ( $wantarray ) {
        my @res;
        while (my ($from, $len) = splice @_, 0, 2) {
            push @res, substr($$textref, $from, $len);
        }
        if ( $extralen ) { # CORRECT FILLET
            my $extra = substr($res[0], $extrapos-$oppos, $extralen, "\n");
            $res[1] = "$extra$res[1]";
            eval { substr($$textref,$remainderpos,0) = $extra;
                   substr($$textref,$extrapos,$extralen,"\n")} ;
                    #REARRANGE HERE DOC AND FILLET IF POSSIBLE
            pos($$textref) = $remainderpos-$extralen+1; # RESET \G
        } else {
            pos($$textref) = $remainderpos;             # RESET \G
        }
        return @res;
    } else {
        my $match = substr($$textref,$_[0],$_[1]);
        substr($match,$extrapos-$_[0]-$startlen,$extralen,"") if $extralen;
        my $extra = $extralen
            ? substr($$textref, $extrapos, $extralen)."\n" : "";
        eval {substr($$textref,$_[4],$_[1]+$_[5])=$extra} ;     #CHOP OUT PREFIX & MATCH, IF POSSIBLE
        pos($$textref) = $_[4];                         # RESET \G
        return $match;
    }
}


sub gen_delimited_pat($;$)  # ($delimiters;$escapes)
{
    my ($dels, $escs) = @_;
    return "" unless $dels =~ /\S/;
    $escs = '\\' unless $escs;
    $escs .= substr($escs,-1) x (length($dels)-length($escs));
    my @pat = ();
    my $i;
    for ($i=0; $i<length $dels; $i++)
    {
        my $del = quotemeta substr($dels,$i,1);
        my $esc = quotemeta substr($escs,$i,1);
        if ($del eq $esc)
        {
            push @pat, "$del(?:[^$del]*(?:(?:$del$del)[^$del]*)*)$del";
        }
        else
        {
            push @pat, "$del(?:[^$esc$del]*(?:$esc.[^$esc$del]*)*)$del";
        }
    }
    my $pat = join '|', @pat;
    return "(?:$pat)";
}

*delimited_pat = \&gen_delimited_pat;


sub extract_delimited (;$$$$)
{
    my $textref = defined $_[0] ? \$_[0] : \$_;
    $ref2slashvalid{$textref} = 1, $ref2qmarkvalid{$textref} = 0 if !pos($$textref); # reset
    my $wantarray = wantarray;
    my $del  = defined $_[1] ? $_[1] : qq{\'\"\`};
    my $pre  = defined $_[2] ? $_[2] : '\s*';
    my $esc  = defined $_[3] ? $_[3] : qq{\\};
    my $pat = gen_delimited_pat($del, $esc);
    my $startpos = pos $$textref || 0;
    return _fail($wantarray, $textref, "Not a delimited pattern", 0)
        unless $$textref =~ m/\G($pre)($pat)/gc;
    my $prelen = length($1);
    my $matchpos = $startpos+$prelen;
    my $endpos = pos $$textref;
    return _succeed $wantarray, $textref,
                    $matchpos, $endpos-$matchpos,               # MATCH
                    $endpos,   length($$textref)-$endpos,       # REMAINDER
                    $startpos, $prelen;                         # PREFIX
}

my %eb_delim_cache;
sub _eb_delims {
    my ($ldel_orig) = @_;
    return @{ $eb_delim_cache{$ldel_orig} } if $eb_delim_cache{$ldel_orig};
    my $qdel = "";
    my $quotelike;
    my $ldel = $ldel_orig;
    $ldel =~ s/'//g and $qdel .= q{'};
    $ldel =~ s/"//g and $qdel .= q{"};
    $ldel =~ s/`//g and $qdel .= q{`};
    $ldel =~ s/q//g and $quotelike = 1;
    $ldel =~ tr/[](){}<>\0-\377/[[(({{<</ds;
    my $rdel = $ldel;
    return @{ $eb_delim_cache{$ldel_orig} = [] } unless $rdel =~ tr/[({</])}>/;
    my $posbug = pos;
    $ldel = join('|', map { quotemeta $_ } split('', $ldel));
    $rdel = join('|', map { quotemeta $_ } split('', $rdel));
    pos = $posbug;
    @{ $eb_delim_cache{$ldel_orig} = [
        qr/\G($ldel)/, $qdel && qr/\G([$qdel])/, $quotelike, qr/\G($rdel)/
    ] };
}
sub extract_bracketed (;$$$)
{
    my $textref = defined $_[0] ? \$_[0] : \$_;
    $ref2slashvalid{$textref} = 1, $ref2qmarkvalid{$textref} = 0 if !pos($$textref); # reset
    my $ldel = defined $_[1] ? $_[1] : '{([<';
    my $pre  = defined $_[2] ? qr/\G$_[2]/ : qr/\G\s*/;
    my $wantarray = wantarray;
    my @ret = _eb_delims($ldel);
    unless (@ret)
    {
        return _fail $wantarray, $textref,
                     "Did not find a suitable bracket in delimiter: \"$_[1]\"",
                     0;
    }

    my $startpos = pos $$textref || 0;
    my @match = _match_bracketed($textref, $pre, @ret);

    return _fail ($wantarray, $textref) unless @match;

    return _succeed ( $wantarray, $textref,
                      $match[2], $match[5]+2,           # MATCH
                      @match[8,9],                      # REMAINDER
                      @match[0,1],                      # PREFIX
                    );
}

sub _match_bracketed    # $textref, $pre, $ldel, $qdel, $quotelike, $rdel
{
    my ($textref, $pre, $ldel, $qdel, $quotelike, $rdel) = @_;
    my ($startpos, $ldelpos, $endpos) = (pos $$textref = pos $$textref||0);
    unless ($$textref =~ m/$pre/gc)
    {
        _failmsg "Did not find prefix: /$pre/", $startpos;
        return;
    }

    $ldelpos = pos $$textref;

    unless ($$textref =~ m/$ldel/gc)
    {
        _failmsg "Did not find opening bracket after prefix: \"$pre\"",
                 pos $$textref;
        pos $$textref = $startpos;
        return;
    }

    my @nesting = ( $1 );
    my $textlen = length $$textref;
    while (pos $$textref < $textlen)
    {
        next if $$textref =~ m/\G\\./gcs;

        if ($$textref =~ m/$ldel/gc)
        {
            push @nesting, $1;
        }
        elsif ($$textref =~ m/$rdel/gc)
        {
            my ($found, $brackettype) = ($1, $1);
            if ($#nesting < 0)
            {
                _failmsg "Unmatched closing bracket: \"$found\"",
                         pos $$textref;
                pos $$textref = $startpos;
                return;
            }
            my $expected = pop(@nesting);
            $expected =~ tr/({[</)}]>/;
            if ($expected ne $brackettype)
            {
                _failmsg qq{Mismatched closing bracket: expected "$expected" but found "$found"},
                         pos $$textref;
                pos $$textref = $startpos;
                return;
            }
            last if $#nesting < 0;
        }
        elsif ($qdel && $$textref =~ m/$qdel/gc)
        {
            $$textref =~ m/\G[^\\$1]*(?:\\.[^\\$1]*)*(\Q$1\E)/gsc and next;
            _failmsg "Unmatched embedded quote ($1)",
                     pos $$textref;
            pos $$textref = $startpos;
            return;
        }
        elsif ($quotelike && _match_quotelike($textref,qr/\G()/,$ref2slashvalid{$textref},$ref2qmarkvalid{$textref}))
        {
            $ref2slashvalid{$textref} = $ref2qmarkvalid{$textref} = 1; # back-compat
            next;
        }

        else { $$textref =~ m/\G(?:[a-zA-Z0-9]+|.)/gcs }
    }
    if ($#nesting>=0)
    {
        _failmsg "Unmatched opening bracket(s): "
                     . join("..",@nesting)."..",
                 pos $$textref;
        pos $$textref = $startpos;
        return;
    }

    $endpos = pos $$textref;

    return (
        $startpos,  $ldelpos-$startpos,         # PREFIX
        $ldelpos,   1,                          # OPENING BRACKET
        $ldelpos+1, $endpos-$ldelpos-2,         # CONTENTS
        $endpos-1,  1,                          # CLOSING BRACKET
        $endpos,    length($$textref)-$endpos,  # REMAINDER
    );
}

sub _revbracket($)
{
    my $brack = reverse $_[0];
    $brack =~ tr/[({</])}>/;
    return $brack;
}

my $XMLNAME = q{[a-zA-Z_:][a-zA-Z0-9_:.-]*};

my $et_default_ldel = '<\w+(?:' . gen_delimited_pat(q{'"}) . '|[^>])*>';
sub extract_tagged (;$$$$$) # ($text, $opentag, $closetag, $pre, \%options)
{
    my $textref = defined $_[0] ? \$_[0] : \$_;
    $ref2slashvalid{$textref} = 1, $ref2qmarkvalid{$textref} = 0 if !pos($$textref); # reset
    my $ldel    = $_[1];
    my $rdel    = $_[2];
    my $pre     = defined $_[3] ? qr/\G$_[3]/ : qr/\G\s*/;
    my %options = defined $_[4] ? %{$_[4]} : ();
    my $omode   = defined $options{fail} ? $options{fail} : '';
    my $bad     = ref($options{reject}) eq 'ARRAY' ? join('|', @{$options{reject}})
                : defined($options{reject})        ? $options{reject}
                :                                    ''
                ;
    my $ignore  = ref($options{ignore}) eq 'ARRAY' ? join('|', @{$options{ignore}})
                : defined($options{ignore})        ? $options{ignore}
                :                                    ''
                ;

    $ldel = $et_default_ldel if !defined $ldel;
    $@ = undef;

    my @match = _match_tagged($textref, $pre, $ldel, $rdel, $omode, $bad, $ignore);

    return _fail(wantarray, $textref) unless @match;
    return _succeed wantarray, $textref,
            $match[2], $match[3]+$match[5]+$match[7],    # MATCH
            @match[8..9,0..1,2..7];                      # REM, PRE, BITS
}

sub _match_tagged       # ($$$$$$$)
{
    my ($textref, $pre, $ldel, $rdel, $omode, $bad, $ignore) = @_;
    my $rdelspec;

    my ($startpos, $opentagpos, $textpos, $parapos, $closetagpos, $endpos) = ( pos($$textref) = pos($$textref)||0 );

    unless ($$textref =~ m/$pre/gc)
    {
        _failmsg "Did not find prefix: /$pre/", pos $$textref;
        goto failed;
    }

    $opentagpos = pos($$textref);

    unless ($$textref =~ m/\G$ldel/gc)
    {
        _failmsg "Did not find opening tag: /$ldel/", pos $$textref;
        goto failed;
    }

    $textpos = pos($$textref);

    if (!defined $rdel)
    {
        $rdelspec = substr($$textref, $-[0], $+[0] - $-[0]);
        unless ($rdelspec =~ s/\A([[(<{]+)($XMLNAME).*/ quotemeta "$1\/$2". _revbracket($1) /oes)
        {
            _failmsg "Unable to construct closing tag to match: $rdel",
                     pos $$textref;
            goto failed;
        }
    }
    else
    {
        ## no critic (BuiltinFunctions::ProhibitStringyEval)
        $rdelspec = eval "qq{$rdel}" || do {
            my $del;
            for (qw,~ ! ^ & * ) _ + - = } ] : " ; ' > . ? / | ',)
                { next if $rdel =~ /\Q$_/; $del = $_; last }
            unless ($del) {
                use Carp;
                croak "Can't interpolate right delimiter $rdel"
            }
            eval "qq$del$rdel$del";
        };
    }

    while (pos($$textref) < length($$textref))
    {
        next if $$textref =~ m/\G\\./gc;

        if ($$textref =~ m/\G(\n[ \t]*\n)/gc )
        {
            $parapos = pos($$textref) - length($1)
                unless defined $parapos;
        }
        elsif ($$textref =~ m/\G($rdelspec)/gc )
        {
            $closetagpos = pos($$textref)-length($1);
            goto matched;
        }
        elsif ($ignore && $$textref =~ m/\G(?:$ignore)/gc)
        {
            next;
        }
        elsif ($bad && $$textref =~ m/\G($bad)/gcs)
        {
            pos($$textref) -= length($1);       # CUT OFF WHATEVER CAUSED THE SHORTNESS
            goto short if ($omode eq 'PARA' || $omode eq 'MAX');
            _failmsg "Found invalid nested tag: $1", pos $$textref;
            goto failed;
        }
        elsif ($$textref =~ m/\G($ldel)/gc)
        {
            my $tag = $1;
            pos($$textref) -= length($tag);     # REWIND TO NESTED TAG
            unless (_match_tagged(@_))  # MATCH NESTED TAG
            {
                goto short if $omode eq 'PARA' || $omode eq 'MAX';
                _failmsg "Found unbalanced nested tag: $tag",
                         pos $$textref;
                goto failed;
            }
        }
        else { $$textref =~ m/./gcs }
    }

short:
    $closetagpos = pos($$textref);
    goto matched if $omode eq 'MAX';
    goto failed unless $omode eq 'PARA';

    if (defined $parapos) { pos($$textref) = $parapos }
    else                  { $parapos = pos($$textref) }

    return (
        $startpos,    $opentagpos-$startpos,            # PREFIX
        $opentagpos,  $textpos-$opentagpos,             # OPENING TAG
        $textpos,     $parapos-$textpos,                # TEXT
        $parapos,     0,                                # NO CLOSING TAG
        $parapos,     length($$textref)-$parapos,       # REMAINDER
    );

matched:
    $endpos = pos($$textref);
    return (
        $startpos,    $opentagpos-$startpos,            # PREFIX
        $opentagpos,  $textpos-$opentagpos,             # OPENING TAG
        $textpos,     $closetagpos-$textpos,            # TEXT
        $closetagpos, $endpos-$closetagpos,             # CLOSING TAG
        $endpos,      length($$textref)-$endpos,        # REMAINDER
    );

failed:
    _failmsg "Did not find closing tag", pos $$textref unless $@;
    pos($$textref) = $startpos;
    return;
}

sub extract_variable (;$$)
{
    my $textref = defined $_[0] ? \$_[0] : \$_;
    return ("","","") unless defined $$textref;
    $ref2slashvalid{$textref} = 1, $ref2qmarkvalid{$textref} = 0 if !pos($$textref); # reset
    my $pre  = defined $_[1] ? qr/\G$_[1]/ : qr/\G\s*/;

    my @match = _match_variable($textref,$pre);

    return _fail wantarray, $textref unless @match;

    return _succeed wantarray, $textref,
                    @match[2..3,4..5,0..1];        # MATCH, REMAINDER, PREFIX
}

sub _match_variable
{
    my ($textref, $pre) = @_;
    my $startpos = pos($$textref) = pos($$textref)||0;
    unless ($$textref =~ m/$pre/gc)
    {
        _failmsg "Did not find prefix: /$pre/", pos $$textref;
        return;
    }
    my $varpos = pos($$textref);
    unless ($$textref =~ m{\G\$\s*(?!::)(\d+|[][&`'+*./|,";%=~:?!\@<>()-]|\^[a-z]?)}gci)
    {
        unless ($$textref =~ m/\G((\$#?|[*\@\%]|\\&)+)/gc)
        {
            _failmsg "Did not find leading dereferencer", pos $$textref;
            pos $$textref = $startpos;
            return;
        }
        my $deref = $1;

        unless ($$textref =~ m/\G\s*(?:::|')?(?:[_a-z]\w*(?:::|'))*[_a-z]\w*/gci
            or _match_codeblock($textref, qr/\G()/, '\{', qr/\G\s*(\})/, '\{', '\}', 0, 1)
            or $deref eq '$#' or $deref eq '$$'
            or pos($$textref) == length $$textref )
        {
            _failmsg "Bad identifier after dereferencer", pos $$textref;
            pos $$textref = $startpos;
            return;
        }
    }

    while (1)
    {
        next if $$textref =~ m/\G\s*(?:->)?\s*[{]\w+[}]/gc;
        next if _match_codeblock($textref,
                                 qr/\G\s*->\s*(?:[_a-zA-Z]\w+\s*)?/,
                                 qr/[({[]/, qr/\G\s*([)}\]])/,
                                 qr/[({[]/, qr/[)}\]]/, 0, 1);
        next if _match_codeblock($textref,
                                 qr/\G\s*/, qr/[{[]/, qr/\G\s*([}\]])/,
                                 qr/[{[]/, qr/[}\]]/, 0, 1);
        next if _match_variable($textref,qr/\G\s*->\s*/);
        next if $$textref =~ m/\G\s*->\s*\w+(?![{([])/gc;
        last;
    }
    $ref2slashvalid{$textref} = $ref2qmarkvalid{$textref} = 0;

    my $endpos = pos($$textref);
    return ($startpos, $varpos-$startpos,
            $varpos,   $endpos-$varpos,
            $endpos,   length($$textref)-$endpos
    );
}

my %ec_delim_cache;
sub _ec_delims {
    my ($ldel_inner, $ldel_outer) = @_;
    return @{ $ec_delim_cache{$ldel_outer}{$ldel_inner} }
        if $ec_delim_cache{$ldel_outer}{$ldel_inner};
    my $rdel_inner = $ldel_inner;
    my $rdel_outer = $ldel_outer;
    my $posbug = pos;
    for ($ldel_inner, $ldel_outer) { tr/[]()<>{}\0-\377/[[((<<{{/ds }
    for ($rdel_inner, $rdel_outer) { tr/[]()<>{}\0-\377/]]))>>}}/ds }
    for ($ldel_inner, $ldel_outer, $rdel_inner, $rdel_outer)
    {
        $_ = '('.join('|',map { quotemeta $_ } split('',$_)).')'
    }
    pos = $posbug;
    @{ $ec_delim_cache{$ldel_outer}{$ldel_inner} = [
        $ldel_outer, qr/\G\s*($rdel_outer)/, $ldel_inner, $rdel_inner
    ] };
}
sub extract_codeblock (;$$$$$)
{
    my $textref = defined $_[0] ? \$_[0] : \$_;
    $ref2slashvalid{$textref} = 1, $ref2qmarkvalid{$textref} = 0 if !pos($$textref); # reset
    my $wantarray = wantarray;
    my $ldel_inner = defined $_[1] ? $_[1] : '{';
    my $pre = !defined $_[2] ? qr/\G\s*/ : qr/\G$_[2]/;
    my $ldel_outer = defined $_[3] ? $_[3] : $ldel_inner;
    my $rd         = $_[4];
    my @delims = _ec_delims($ldel_inner, $ldel_outer);

    my @match = _match_codeblock($textref, $pre, @delims, $rd, 1);
    return _fail($wantarray, $textref) unless @match;
    return _succeed($wantarray, $textref,
                    @match[2..3,4..5,0..1]    # MATCH, REMAINDER, PREFIX
    );
}

sub _match_codeblock
{
    my ($textref, $pre, $ldel_outer, $rdel_outer, $ldel_inner, $rdel_inner, $rd, $no_backcompat) = @_;
    $rdel_outer = qr/\G\s*($rdel_outer)/ if !$no_backcompat; # Switch calls this func directly
    my $startpos = pos($$textref) = pos($$textref) || 0;
    unless ($$textref =~ m/$pre/gc)
    {
        _failmsg qq{Did not match prefix /$pre/ at"} .
                     substr($$textref,pos($$textref),20) .
                     q{..."},
                 pos $$textref;
        return;
    }
    my $codepos = pos($$textref);
    unless ($$textref =~ m/\G($ldel_outer)/gc)  # OUTERMOST DELIMITER
    {
        _failmsg qq{Did not find expected opening bracket at "} .
                     substr($$textref,pos($$textref),20) .
                     q{..."},
                 pos $$textref;
        pos $$textref = $startpos;
        return;
    }
    my $closing = $1;
       $closing =~ tr/([<{/)]>}/;
    my $matched;
    $ref2slashvalid{$textref} = 1, $ref2qmarkvalid{$textref} = 0
      if !pos($$textref) or !defined $ref2slashvalid{$textref}; # default, or reset
    while (pos($$textref) < length($$textref))
    {
        if ($rd && $$textref =~ m#\G(\Q(?)\E|\Q(s?)\E|\Q(s)\E)#gc)
        {
            $ref2slashvalid{$textref} = $ref2qmarkvalid{$textref} = 0;
            next;
        }

        if ($$textref =~ m/\G\s*#.*/gc)
        {
            next;
        }

        if ($$textref =~ m/$rdel_outer/gc)
        {
            unless ($matched = ($closing && $1 eq $closing) )
            {
                next if $1 eq '>';      # MIGHT BE A "LESS THAN"
                _failmsg q{Mismatched closing bracket at "} .
                             substr($$textref,pos($$textref),20) .
                             qq{...". Expected '$closing'},
                         pos $$textref;
            }
            last;
        }

        if (_match_variable($textref,qr/\G\s*/) ||
            _match_quotelike($textref,qr/\G\s*/,$ref2slashvalid{$textref},$ref2qmarkvalid{$textref}) )
        {
            $ref2slashvalid{$textref} = $ref2qmarkvalid{$textref} = 0;
            next;
        }

        if ($$textref =~ m#\G\s*(?!$ldel_inner)(?:$RE_PREREGEX_PAT|$RE_EXPR_PAT)#gc)
        {
            $ref2slashvalid{$textref} = $ref2qmarkvalid{$textref} = 1;
            next;
        }

        if ( _match_codeblock($textref, qr/\G\s*/, $ldel_inner, qr/\G\s*($rdel_inner)/, $ldel_inner, $rdel_inner, $rd, 1) )
        {
            $ref2slashvalid{$textref} = $ref2qmarkvalid{$textref} = 1;
            next;
        }

        if ($$textref =~ m/\G\s*$ldel_outer/gc)
        {
            _failmsg q{Improperly nested codeblock at "} .
                         substr($$textref,pos($$textref),20) .
                         q{..."},
                     pos $$textref;
            last;
        }

        $ref2slashvalid{$textref} = $ref2qmarkvalid{$textref} = 0;
        $$textref =~ m/\G\s*(\w+|[-=>]>|.|\Z)/gc;
    }
    continue { $@ = undef }

    unless ($matched)
    {
        _failmsg 'No match found for opening bracket', pos $$textref
                unless $@;
        return;
    }

    $ref2slashvalid{$textref} = $ref2qmarkvalid{$textref} = undef;
    my $endpos = pos($$textref);
    return ( $startpos, $codepos-$startpos,
             $codepos, $endpos-$codepos,
             $endpos,  length($$textref)-$endpos,
    );
}


my %mods   = (
    'none' => '[cgimsox]*',
    'm'    => '[cgimsox]*',
    's'    => '[cegimsox]*',
    'tr'   => '[cds]*',
    'y'    => '[cds]*',
    'qq'   => '',
    'qx'   => '',
    'qw'   => '',
    'qr'   => '[imsx]*',
    'q'    => '',
);

sub extract_quotelike (;$$)
{
    my $textref = $_[0] ? \$_[0] : \$_;
    $ref2slashvalid{$textref} = 1, $ref2qmarkvalid{$textref} = 0 if !pos($$textref); # reset
    my $wantarray = wantarray;
    my $pre  = defined $_[1] ? qr/\G$_[1]/ : qr/\G\s*/;

    my @match = _match_quotelike($textref,$pre,$ref2slashvalid{$textref},$ref2qmarkvalid{$textref});
    return _fail($wantarray, $textref) unless @match;
    return _succeed($wantarray, $textref,
                    $match[2], $match[18]-$match[2],    # MATCH
                    @match[18,19],                      # REMAINDER
                    @match[0,1],                        # PREFIX
                    @match[2..17],                      # THE BITS
                    @match[20,21],                      # ANY FILLET?
    );
};

my %maybe_quote = map +($_=>1), qw(" ' `);
sub _match_quotelike
{
    my ($textref, $pre, $allow_slash_match, $allow_qmark_match) = @_;
    $ref2slashvalid{$textref} = 1, $ref2qmarkvalid{$textref} = 0
      if !pos($$textref) or !defined $ref2slashvalid{$textref}; # default, or reset

    my ($textlen,$startpos,
        $preld1pos,$ld1pos,$str1pos,$rd1pos,
        $preld2pos,$ld2pos,$str2pos,$rd2pos,
        $modpos) = ( length($$textref), pos($$textref) = pos($$textref) || 0 );

    unless ($$textref =~ m/$pre/gc)
    {
        _failmsg qq{Did not find prefix /$pre/ at "} .
                     substr($$textref, pos($$textref), 20) .
                     q{..."},
                 pos $$textref;
        return;
    }
    my $oppos = pos($$textref);
    my $initial = substr($$textref,$oppos,1);
    if ($initial && $maybe_quote{$initial}
                 || $allow_slash_match && $initial eq '/'
                 || $allow_qmark_match && $initial eq '?')
    {
        unless ($$textref =~ m/\G \Q$initial\E [^\\$initial]* (\\.[^\\$initial]*)* \Q$initial\E /gcsx)
        {
            _failmsg qq{Did not find closing delimiter to match '$initial' at "} .
                         substr($$textref, $oppos, 20) .
                         q{..."},
                     pos $$textref;
            pos $$textref = $startpos;
            return;
        }
        $modpos= pos($$textref);
        $rd1pos = $modpos-1;

        if ($initial eq '/' || $initial eq '?')
        {
            $$textref =~ m/\G$mods{none}/gc
        }

        my $endpos = pos($$textref);
        $ref2qmarkvalid{$textref} = $ref2slashvalid{$textref} = 0;
        return (
            $startpos,  $oppos-$startpos,       # PREFIX
            $oppos,     0,                      # NO OPERATOR
            $oppos,     1,                      # LEFT DEL
            $oppos+1,   $rd1pos-$oppos-1,       # STR/PAT
            $rd1pos,    1,                      # RIGHT DEL
            $modpos,    0,                      # NO 2ND LDEL
            $modpos,    0,                      # NO 2ND STR
            $modpos,    0,                      # NO 2ND RDEL
            $modpos,    $endpos-$modpos,        # MODIFIERS
            $endpos,    $textlen-$endpos,       # REMAINDER
        );
    }

    unless ($$textref =~ m{\G(\b(?:m|s|qq|qx|qw|q|qr|tr|y)\b(?=\s*\S)|<<(?=[a-zA-Z]|\s*['"`;,]))}gc)
    {
        _failmsg q{No quotelike operator found after prefix at "} .
                     substr($$textref, pos($$textref), 20) .
                     q{..."},
                 pos $$textref;
        pos $$textref = $startpos;
        return;
    }

    my $op = $1;
    $preld1pos = pos($$textref);
    if ($op eq '<<') {
        $ld1pos = pos($$textref);
        my $label;
        if ($$textref =~ m{\G([A-Za-z_]\w*)}gc) {
            $label = $1;
        }
        elsif ($$textref =~ m{ \G ' ([^'\\]* (?:\\.[^'\\]*)*) '
                             | \G " ([^"\\]* (?:\\.[^"\\]*)*) "
                             | \G ` ([^`\\]* (?:\\.[^`\\]*)*) `
                             }gcsx) {
            $label = $+;
        }
        else {
            $label = "";
        }
        my $extrapos = pos($$textref);
        $$textref =~ m{.*\n}gc;
        $str1pos = pos($$textref)--;
        unless ($$textref =~ m{.*?\n(?=\Q$label\E\n)}gc) {
            _failmsg qq{Missing here doc terminator ('$label') after "} .
                         substr($$textref, $startpos, 20) .
                         q{..."},
                     pos $$textref;
            pos $$textref = $startpos;
            return;
        }
        $rd1pos = pos($$textref);
        $$textref =~ m{\Q$label\E\n}gc;
        $ld2pos = pos($$textref);
        $ref2qmarkvalid{$textref} = $ref2slashvalid{$textref} = 0;
        return (
            $startpos,  $oppos-$startpos,       # PREFIX
            $oppos,     length($op),            # OPERATOR
            $ld1pos,    $extrapos-$ld1pos,      # LEFT DEL
            $str1pos,   $rd1pos-$str1pos,       # STR/PAT
            $rd1pos,    $ld2pos-$rd1pos,        # RIGHT DEL
            $ld2pos,    0,                      # NO 2ND LDEL
            $ld2pos,    0,                      # NO 2ND STR
            $ld2pos,    0,                      # NO 2ND RDEL
            $ld2pos,    0,                      # NO MODIFIERS
            $ld2pos,    $textlen-$ld2pos,       # REMAINDER
            $extrapos,  $str1pos-$extrapos,     # FILLETED BIT
        );
    }

    $$textref =~ m/\G\s*/gc;
    $ld1pos = pos($$textref);
    $str1pos = $ld1pos+1;

    if ($$textref !~ m/\G(\S)/gc)   # SHOULD USE LOOKAHEAD
    {
        _failmsg "No block delimiter found after quotelike $op",
                 pos $$textref;
        pos $$textref = $startpos;
        return;
    }
    elsif (substr($$textref, $ld1pos, 2) eq '=>')
    {
        _failmsg "quotelike $op was actually quoted by '=>'",
                 pos $$textref;
        pos $$textref = $startpos;
        return;
    }
    pos($$textref) = $ld1pos;   # HAVE TO DO THIS BECAUSE LOOKAHEAD BROKEN
    my ($ldel1, $rdel1) = ("\Q$1","\Q$1");
    if ($ldel1 =~ /[[(<{]/)
    {
        $rdel1 =~ tr/[({</])}>/;
        defined(_match_bracketed($textref,qr/\G/,qr/\G($ldel1)/,"","",qr/\G($rdel1)/))
            || do { pos $$textref = $startpos; return };
        $ld2pos = pos($$textref);
        $rd1pos = $ld2pos-1;
    }
    else
    {
        $$textref =~ /\G$ldel1[^\\$ldel1]*(\\.[^\\$ldel1]*)*$ldel1/gcs
            || do { pos $$textref = $startpos; return };
        $ld2pos = $rd1pos = pos($$textref)-1;
    }

    my $second_arg = $op =~ /s|tr|y/ ? 1 : 0;
    if ($second_arg)
    {
        my ($ldel2, $rdel2);
        if ($ldel1 =~ /[[(<{]/)
        {
            unless ($$textref =~ /\G\s*(\S)/gc) # SHOULD USE LOOKAHEAD
            {
                _failmsg "Missing second block for quotelike $op",
                         pos $$textref;
                pos $$textref = $startpos;
                return;
            }
            $ldel2 = $rdel2 = "\Q$1";
            $rdel2 =~ tr/[({</])}>/;
        }
        else
        {
            $ldel2 = $rdel2 = $ldel1;
        }
        $str2pos = $ld2pos+1;

        if ($ldel2 =~ /[[(<{]/)
        {
            pos($$textref)--;   # OVERCOME BROKEN LOOKAHEAD
            defined(_match_bracketed($textref,qr/\G/,qr/\G($ldel2)/,"","",qr/\G($rdel2)/))
                || do { pos $$textref = $startpos; return };
        }
        else
        {
            $$textref =~ /[^\\$ldel2]*(\\.[^\\$ldel2]*)*$ldel2/gcs
                || do { pos $$textref = $startpos; return };
        }
        $rd2pos = pos($$textref)-1;
    }
    else
    {
        $ld2pos = $str2pos = $rd2pos = $rd1pos;
    }

    $modpos = pos $$textref;

    $$textref =~ m/\G($mods{$op})/gc;
    my $endpos = pos $$textref;
    $ref2qmarkvalid{$textref} = $ref2slashvalid{$textref} = undef;

    return (
        $startpos,      $oppos-$startpos,       # PREFIX
        $oppos,         length($op),            # OPERATOR
        $ld1pos,        1,                      # LEFT DEL
        $str1pos,       $rd1pos-$str1pos,       # STR/PAT
        $rd1pos,        1,                      # RIGHT DEL
        $ld2pos,        $second_arg,            # 2ND LDEL (MAYBE)
        $str2pos,       $rd2pos-$str2pos,       # 2ND STR (MAYBE)
        $rd2pos,        $second_arg,            # 2ND RDEL (MAYBE)
        $modpos,        $endpos-$modpos,        # MODIFIERS
        $endpos,        $textlen-$endpos,       # REMAINDER
    );
}

my $def_func = [
    sub { extract_variable($_[0], '') },
    sub { extract_quotelike($_[0],'') },
    sub { extract_codeblock($_[0],'{}','') },
];
my %ref_not_regex = map +($_=>1), qw(CODE Text::Balanced::Extractor);

sub _update_patvalid {
    my ($textref, $text) = @_;
    if ($ref2slashvalid{$textref} && $text =~ m/(?:$RE_NUM|[\)\]])\s*$/)
    {
        $ref2slashvalid{$textref} = $ref2qmarkvalid{$textref} = 0;
    } elsif (!$ref2slashvalid{$textref} && $text =~ m/$RE_PREREGEX_PAT\s*$/)
    {
        $ref2slashvalid{$textref} = $ref2qmarkvalid{$textref} = 1;
    } elsif (!$ref2slashvalid{$textref} && $text =~ m/$RE_EXPR_PAT\s*$/)
    {
        $ref2slashvalid{$textref} = 1;
        $ref2qmarkvalid{$textref} = 0;
    }
}
sub extract_multiple (;$$$$)    # ($text, $functions_ref, $max_fields, $ignoreunknown)
{
    my $textref = defined($_[0]) ? \$_[0] : \$_;
    $ref2slashvalid{$textref} = 1, $ref2qmarkvalid{$textref} = 0 if !pos($$textref); # reset
    my $posbug = pos;
    my ($lastpos, $firstpos);
    my @fields = ();

    #for ($$textref)
    {
        my @func = defined $_[1] ? @{$_[1]} : @{$def_func};
        my $max  = defined $_[2] && $_[2]>0 ? $_[2] : 1_000_000_000;
        my $igunk = $_[3];

        pos $$textref ||= 0;

        unless (wantarray)
        {
            use Carp;
            carp "extract_multiple reset maximal count to 1 in scalar context"
                    if $^W && defined($_[2]) && $max > 1;
            $max = 1
        }

        my @class;
        foreach my $func ( @func )
        {
            push @class, undef;
            ($class[-1], $func) = %$func if ref($func) eq 'HASH';
            $func = qr/\G$func/ if !$ref_not_regex{ref $func};
        }

        my $unkpos;
        FIELD: while (pos($$textref) < length($$textref))
        {
            foreach my $i ( 0..$#func )
            {
                my ($field, $pref);
                my ($class, $func) = ($class[$i], $func[$i]);
                $lastpos = pos $$textref;
                if (ref($func) eq 'CODE')
                    { ($field,undef,$pref) = $func->($$textref) }
                elsif (ref($func) eq 'Text::Balanced::Extractor')
                    { $field = $func->extract($$textref) }
                elsif( $$textref =~ m/$func[$i]/gc )
                    { $field = defined($1)
                        ? $1
                        : substr($$textref, $-[0], $+[0] - $-[0])
                    }
                $pref ||= "";
                if (defined($field) && length($field))
                {
                    if (!$igunk) {
                        $unkpos = $lastpos
                            if length($pref) && !defined($unkpos);
                        if (defined $unkpos)
                        {
                            push @fields, substr($$textref, $unkpos, $lastpos-$unkpos).$pref;
                            $firstpos = $unkpos unless defined $firstpos;
                            undef $unkpos;
                            last FIELD if @fields == $max;
                        }
                    }
                    push @fields, $class ? bless(\$field, $class) : $field;
                    _update_patvalid($textref, $fields[-1]);
                    $firstpos = $lastpos unless defined $firstpos;
                    $lastpos = pos $$textref;
                    last FIELD if @fields == $max;
                    next FIELD;
                }
            }
            if ($$textref =~ /\G(.)/gcs)
            {
                $unkpos = pos($$textref)-1
                    unless $igunk || defined $unkpos;
                _update_patvalid($textref, substr $$textref, $unkpos, pos($$textref)-$unkpos);
            }
        }

        if (defined $unkpos)
        {
            push @fields, substr($$textref, $unkpos);
            $firstpos = $unkpos unless defined $firstpos;
            $lastpos = length $$textref;
        }
        last;
    }

    pos $$textref = $lastpos;
    return @fields if wantarray;

    $firstpos ||= 0;
    eval { substr($$textref,$firstpos,$lastpos-$firstpos)="";
           pos $$textref = $firstpos };
    return $fields[0];
}

sub gen_extract_tagged # ($opentag, $closetag, $pre, \%options)
{
    my $ldel    = $_[0];
    my $rdel    = $_[1];
    my $pre     = defined $_[2] ? qr/\G$_[2]/ : qr/\G\s*/;
    my %options = defined $_[3] ? %{$_[3]} : ();
    my $omode   = defined $options{fail} ? $options{fail} : '';
    my $bad     = ref($options{reject}) eq 'ARRAY' ? join('|', @{$options{reject}})
                : defined($options{reject})        ? $options{reject}
                :                                    ''
                ;
    my $ignore  = ref($options{ignore}) eq 'ARRAY' ? join('|', @{$options{ignore}})
                : defined($options{ignore})        ? $options{ignore}
                :                                    ''
                ;

    $ldel = $et_default_ldel if !defined $ldel;

    my $posbug = pos;
    for ($ldel, $bad, $ignore) { $_ = qr/$_/ if $_ }
    pos = $posbug;

    my $closure = sub
    {
        my $textref = defined $_[0] ? \$_[0] : \$_;
        my @match = _match_tagged($textref, $pre, $ldel, $rdel, $omode, $bad, $ignore);

        return _fail(wantarray, $textref) unless @match;
        return _succeed wantarray, $textref,
                        $match[2], $match[3]+$match[5]+$match[7],   # MATCH
                        @match[8..9,0..1,2..7];                     # REM, PRE, BITS
    };

    bless $closure, 'Text::Balanced::Extractor';
}

package Text::Balanced::Extractor;

sub extract($$) # ($self, $text)
{
    &{$_[0]}($_[1]);
}

package Text::Balanced::ErrorMsg;

use overload
    '""' => sub { "$_[0]->{error}, detected at offset $_[0]->{pos}" },
    fallback => 1;

1;

__END__

