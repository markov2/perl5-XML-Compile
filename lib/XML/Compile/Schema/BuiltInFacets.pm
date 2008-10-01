use warnings;
use strict;

package XML::Compile::Schema::BuiltInFacets;
use base 'Exporter';

our @EXPORT = qw/builtin_facet/;

use Log::Report     'xml-compile', syntax => 'SHORT';
use Math::BigInt;
use Math::BigFloat;
use XML::RegExp;

use constant DBL_MAX_DIG => 15;
use constant DBL_MAX_EXP => 307;

# depends on Perl's compile flags
use constant INT_MAX => int((sprintf"%u\n",-1)/2);
use constant INT_MIN => -1 - INT_MAX;

=chapter NAME

XML::Compile::Schema::BuiltInFacets - handling of built-in facet checks

=chapter SYNOPSIS

 # Not for end-users
 use XML::Compile::Schema::BuiltInFacets qw/%facets/;

=chapter DESCRIPTION

This package implements the facet checks.  Facets are used to
express restrictions on variable content which need to be checked
dynamically.

The content is not for end-users, but called by the schema translator.

=chapter FUNCTIONS

=function builtin_facet PATH, ARGS, TYPE, [VALUE]

=cut

my %facets =
 ( whiteSpace      => \&_whiteSpace
 , minInclusive    => \&_minInclusive
 , minExclusive    => \&_minExclusive
 , maxInclusive    => \&_maxInclusive
 , maxExclusive    => \&_maxExclusive
 , enumeration     => \&_enumeration
 , totalDigits     => \&_totalDigits
 , fractionDigits  => \&_fractionDigits
 , pattern         => \&_pattern
 , length          => \&_length
 , minLength       => \&_minLength
 , maxLength       => \&_maxLength
 , minScale        => undef   # ignore
 , maxScale        => undef   # ignore
 );

sub builtin_facet($$$;@)
{   my ($path, $args, $type, $value) = @_;
    exists $facets{$type}
        or panic "facet $type not implemented";

    my $def = $facets{$type} or return;
    $def->($path, $args, $value);
}

sub _whiteSpace($$$)
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

sub _minInclusive($$$)
{   my ($path, $args, $min) = @_;
    $min = _maybe_big $path, $args, $min;
    my $err  = $args->{err};
    sub { return $_[0] if $_[0] >= $min;
          error __x"too small inclusive {value}, min {min} at {where}"
              , value => $_[0], min => $min, where => $path;
        }
}

sub _minExclusive($$$)
{   my ($path, $args, $min) = @_;
    $min = _maybe_big $path, $args, $min;
    my $err  = $args->{err};
    sub { return $_[0] if $_[0] > $min;
          error __x"too small exclusive {value}, larger {min} at {where}"
              , value => $_[0], min => $min, where => $path;
        }
}

sub _maxInclusive($$$)
{   my ($path, $args, $max) = @_;
    $max = _maybe_big $path, $args, $max;
    my $err  = $args->{err};
    sub { return $_[0] if $_[0] <= $max;
          error __x"too large inclusive {value}, max {max} at {where}"
              , value => $_[0], max => $max, where => $path;
        }
}

sub _maxExclusive($$$)
{   my ($path, $args, $max) = @_;
    $max = _maybe_big $path, $args, $max;
    my $err  = $args->{err};
    sub { return $_[0] if $_[0] < $max;
          error __x"too large exclusive {value}, smaller {max} at {where}"
              , value => $_[0], max => $max, where => $path;
        }
}

sub _enumeration($$$)
{   my ($path, $args, $enums) = @_;
    my %enum = map { ($_ => 1) } @$enums;
    my $err  = $args->{err};
    sub { return $_[0] if exists $enum{$_[0]};
          error __x"invalid enumerate `{string}' at {where}"
              , string => $_[0], where => $path;
        };
}

sub _totalDigits($$$)
{   my ($path, undef, $nr) = @_;
    sub { return $_[0] if $nr >= ($_[0] =~ tr/0-9//);
          my $val = $_[0];
          return sprintf "%.${nr}f", $val
              if $val =~ m/^[+-]?0*(\d)[.eE]/ && length($1) < $nr;

          error __x"decimal too long, got {length} digits max {max} at {where}"
             , length => ($val =~ tr/0-9//), max => $nr, where => $path;
    };
}

sub _fractionDigits($$$)
{   my $nr = $_[2];
    sub { sprintf "%.${nr}f", $_[0] };
}

sub _length($$$)
{   my ($path, $args, $len) = @_;
    my $err = $args->{err};
    sub { return $_[0] if defined $_[0] && length($_[0])==$len;
          error __x"string `{string}' does not have required length {len} at {where}"
              , string => $_[0], len => $len, where => $path;
        };
}

sub _minLength($$$)
{   my ($path, $args, $len) = @_;
    my $err = $args->{err};
    sub { return $_[0] if defined $_[0] && length($_[0]) >=$len;
          error __x"string `{string}' does not have minimum length {len} at {where}"
              , string => $_[0], len => $len, where => $path;
        };
}

sub _maxLength($$$)
{   my ($path, $args, $len) = @_;
    my $err = $args->{err};
    sub { return $_[0] if defined $_[0] && length $_[0] <= $len;
          error __x"string `{string}' longer maximum length {len} at {where}"
              , string => $_[0], len => $len, where => $path;
        };
}

# Converts an XML pattern expresssion into a real Perl regular expression.
# Gladly, most of the pattern features are taken from Perl.  The current
# implementation of this function is dumb and incorrect.

sub _pattern($$$)
{   my ($path, $args, $pats) = @_;
    my @pats = @$pats or return ();

    foreach (@pats)
    {   s/\\i/[a-zA-Z_:]/g;      # simplyfied, not correct
        s/\\I/[^a-zA-Z_:]/g;     # idem
        s/\\c/$XML::RegExp::NameChar/g;
#       s/(?<!\\)\(/(?:/g;       # incorrect, performance
        s/\\p\{..\}/\\p{Is$1}/g;
        s/\\P\{..\}/\\P{Is$1}/g;
    }

    local $" = '|';
    my $pat = qr/^(?:@pats)$/;
    my $err = $args->{err};

    sub { return $_[0] if $_[0] =~ $pat;
          error __x"string `{string}' does not match pattern {pattern} at {where}"
              , string => $_[0], pattern => $pat, where => $path;
        };
}

1;
