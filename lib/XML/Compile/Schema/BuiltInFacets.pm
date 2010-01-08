use warnings;
use strict;

package XML::Compile::Schema::BuiltInFacets;
use base 'Exporter';

our @EXPORT = qw/builtin_facet/;

use Log::Report     'xml-compile', syntax => 'SHORT';
use Math::BigInt;
use Math::BigFloat;
use XML::LibXML;  # for ::RegExp

use constant DBL_MAX_DIG => 15;
use constant DBL_MAX_EXP => 307;

# depends on Perl's compile flags
use constant INT_MAX => int((sprintf"%u\n",-1)/2);
use constant INT_MIN => -1 - INT_MAX;

=chapter NAME

XML::Compile::Schema::BuiltInFacets - handling of built-in facet checks

=chapter SYNOPSIS

 # Not for end-users
 use XML::Compile::Schema::BuiltInFacets qw/builtin_facet/

=chapter DESCRIPTION

This package implements the facet checks.  Facets are used to
express restrictions on variable content which need to be checked
dynamically.

The content is not for end-users, but called by the schema translator.

=chapter FUNCTIONS

=function builtin_facet PATH, ARGS, TYPE, [VALUE]

=cut

my %facets_simple =
 ( enumeration     => \&_enumeration
 , fractionDigits  => \&_s_fractionDigits
 , length          => \&_s_length
 , maxExclusive    => \&_s_maxExclusive
 , maxInclusive    => \&_s_maxInclusive
 , maxLength       => \&_s_maxLength
 , maxScale        => undef   # ignore
 , minExclusive    => \&_s_minExclusive
 , minInclusive    => \&_s_minInclusive
 , minLength       => \&_s_minLength
 , minScale        => undef   # ignore
 , pattern         => \&_pattern
 , totalDigits     => \&_s_totalDigits
 , whiteSpace      => \&_s_whiteSpace
 );

my %facets_list =
 ( enumeration     => \&_enumeration
 , length          => \&_l_length
 , maxLength       => \&_l_maxLength
 , minLength       => \&_l_minLength
 , pattern         => \&_pattern
 , whiteSpace      => \&_l_whiteSpace
 );

sub builtin_facet($$$$$)
{   my ($path, $args, $type, $value, $is_list) = @_;

    my $def = $is_list ? $facets_list{$type} : $facets_simple{$type};
      $def
    ? $def->($path, $args, $value)
    : error __x"facet {facet} not implemented at {where}"
        , facet => $type, where => $path;
}

sub _l_whiteSpace($$$)
{   my ($path, undef, $ws) = @_;
    $ws eq 'collapse'
        or error __x"list whiteSpace facet fixed to 'collapse', not '{ws}' in {path}"
          , ws => $ws, path => $path;
    ();
}

sub _s_whiteSpace($$$)
{   my ($path, undef, $ws) = @_;
      $ws eq 'replace'  ? \&_whitespace_replace
    : $ws eq 'collapse' ? \&_whitespace_collapse
    : $ws eq 'preserve' ? ()
    : error __x"illegal whiteSpace facet '{ws}' in {path}"
          , ws => $ws, path => $path;
}

sub _whitespace_replace($)
{   (my $value = shift) =~ s/[\t\r\n]/ /gs;
    $value;
}

sub _whitespace_collapse($)
{   my $value = shift;
    for($value)
    {   s/[\t\r\n ]+/ /gs;
        s/^ +//;
        s/ +$//;
    }
    $value;
}

sub _maybe_big($$$)
{   my ($path, $args, $value) = @_;
    return $value if $args->{sloppy_integers};

    # modules Math::Big* loaded by Schema::Spec when not sloppy

    $value =~ s/\s//g;
    if($value =~ m/[.eE]/)
    {   my $c   = $value;
        my $exp = $c =~ s/[eE][+-]?(\d+)// ? $1 : 0;
        for($c) { s/\.//; s/^[-+]// }
        return Math::BigFloat->new($value)
           if length($c) > DBL_MAX_DIG || $exp > DBL_MAX_EXP;
    }

    # compare ints as strings, because they will overflow!!
    if(substr($value, 0, 1) eq '-')
    {   return Math::BigInt->new($value)
           if length($value) > length(INT_MIN)
           || (length($value)==length(INT_MIN) && $value gt INT_MIN);
    }
    else
    {   return Math::BigInt->new($value)
           if length($value) > length(INT_MAX)
           || (length($value)==length(INT_MAX) && $value gt INT_MAX);
    }

    $value;
}

sub _s_minInclusive($$$)
{   my ($path, $args, $min) = @_;
    $min = _maybe_big $path, $args, $min;
    sub { return $_[0] if $_[0] >= $min;
        error __x"too small inclusive {value}, min {min} at {where}"
          , value => $_[0], min => $min, where => $path;
    };
}

sub _s_minExclusive($$$)
{   my ($path, $args, $min) = @_;
    $min = _maybe_big $path, $args, $min;
    sub { return $_[0] if $_[0] > $min;
        error __x"too small exclusive {value}, larger {min} at {where}"
          , value => $_[0], min => $min, where => $path;
    };
}

sub _s_maxInclusive($$$)
{   my ($path, $args, $max) = @_;
    $max = _maybe_big $path, $args, $max;
    sub { return $_[0] if $_[0] <= $max;
        error __x"too large inclusive {value}, max {max} at {where}"
          , value => $_[0], max => $max, where => $path;
    };
}

sub _s_maxExclusive($$$)
{   my ($path, $args, $max) = @_;
    $max = _maybe_big $path, $args, $max;
    sub { return $_[0] if $_[0] < $max;
        error __x"too large exclusive {value}, smaller {max} at {where}"
          , value => $_[0], max => $max, where => $path;
    };
}

sub _enumeration($$$)
{   my ($path, $args, $enums) = @_;
    my %enum = map { ($_ => 1) } @$enums;
    sub { return $_[0] if exists $enum{$_[0]};
        error __x"invalid enumerate `{string}' at {where}"
          , string => $_[0], where => $path;
    };
}

sub _s_totalDigits($$$)
{   my ($path, undef, $nr) = @_;
    sub { return $_[0] if $nr >= ($_[0] =~ tr/0-9//);
        my $val = $_[0];
        return sprintf "%.${nr}f", $val
            if $val =~ m/^[+-]?0*(\d)[.eE]/ && length($1) < $nr;

        error __x"decimal too long, got {length} digits max {max} at {where}"
          , length => ($val =~ tr/0-9//), max => $nr, where => $path;
    };
}

sub _s_fractionDigits($$$)
{   my $nr = $_[2];
    sub { sprintf "%.${nr}f", $_[0] };
}

sub _s_length($$$)
{   my ($path, $args, $len) = @_;
    sub { return $_[0] if defined $_[0] && length($_[0])==$len;
        error __x"string `{string}' does not have required length {len} at {where}"
          , string => $_[0], len => $len, where => $path;
    };
}

sub _l_length($$$)
{   my ($path, $args, $len) = @_;
    sub { return $_[0] if defined $_[0] && @{$_[0]}==$len;
        error __x"list `{list}' does not have required length {len} at {where}"
          , list => $_[0], len => $len, where => $path;
    };
}

sub _s_minLength($$$)
{   my ($path, $args, $len) = @_;
    sub { return $_[0] if defined $_[0] && length($_[0]) >=$len;
        error __x"string `{string}' does not have minimum length {len} at {where}"
          , string => $_[0], len => $len, where => $path;
    };
}

sub _l_minLength($$$)
{   my ($path, $args, $len) = @_;
    sub { return $_[0] if defined $_[0] && @{$_[0]} >=$len;
        error __x"list `{list}' does not have minimum length {len} at {where}"
          , list => $_[0], len => $len, where => $path;
    };
}

sub _s_maxLength($$$)
{   my ($path, $args, $len) = @_;
    sub { return $_[0] if defined $_[0] && length $_[0] <= $len;
        error __x"string `{string}' longer than maximum length {len} at {where}"
          , string => $_[0], len => $len, where => $path;
    };
}

sub _l_maxLength($$$)
{   my ($path, $args, $len) = @_;
    sub { return $_[0] if defined $_[0] && @{$_[0]} <= $len;
        error __x"list `{list}' longer than maximum length {len} at {where}"
          , list => $_[0], len => $len, where => $path;
    };
}

sub _pattern($$$)
{   my ($path, $args, $pats) = @_;
    @$pats or return ();
    my $regex    = @$pats==1 ? $pats->[0] : "(".join(')|(', @$pats).")";
    my $compiled = XML::LibXML::RegExp->new($regex);

    sub { return $_[0] if $compiled->matches($_[0]);
         error __x"string `{string}' does not match pattern `{pat}' at {where}"
           , string => $_[0], pat => $regex, where => $path;
    };
}

1;
