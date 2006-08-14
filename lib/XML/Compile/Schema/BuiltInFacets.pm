use warnings;
use strict;

package XML::Compile::Schema::BuiltInFacets;
use base 'Exporter';

our @EXPORT = qw/builtin_facet/;

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
 , totalFracDigits => \&_totalFracDigits
 , pattern         => \&_pattern
 , length          => \&_length
 , minLength       => \&_minLength
 , maxLength       => \&_maxLength
 );

sub builtin_facet($$$;@)
{   my ($path, $args, $type, $value) = @_;
    my $def = $facets{$type};
    unless(defined $def)
    {   warn "WARN: unknown facet $type in $path\n";
        return ();
    }

    $def->($path, $args, $value);
}

sub _whiteSpace($$$)
{   my ($path, undef, $ws) = @_;
      $ws eq 'replace'  ? \&_whitespace_replace
    : $ws eq 'collapse' ? \&_whitespace_collapse
    : $ws eq 'preserve' ? ()
    : die "ERROR: illegal whiteSpace facet '$ws' in $path\n";
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
        my $exp = s/[eE][+-]?(\d+)// ? $1 : 0;
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
          $err->($path, $_[0], "too small inclusive, min $min");
          $min;
        }
}

sub _minExclusive($$$)
{   my ($path, $args, $min) = @_;
    $min = _maybe_big $path, $args, $min;
    my $err  = $args->{err};
    sub { return $_[0] if $_[0] > $min;
          $err->($path, $_[0], "too small exclusive, larger $min");
          undef;
        }
}

sub _maxInclusive($$$)
{   my ($path, $args, $max) = @_;
    $max = _maybe_big $path, $args, $max;
    my $err  = $args->{err};
    sub { return $_[0] if $_[0] <= $max;
          $err->($path, $_[0], "too large inclusive, max $max");
          $max;
        }
}

sub _maxExclusive($$$)
{   my ($path, $args, $max) = @_;
    $max = _maybe_big $path, $args, $max;
    my $err  = $args->{err};
    sub { return $_[0] if $_[0] < $max;
          $err->($path, $_[0], "too large exclusive, smaller $max");
          undef;
        }
}

sub _enumeration($$$)
{   my ($path, $args, $enums) = @_;
    my %enum = map { ($_ => 1) } @$enums;
    my $err  = $args->{err};
    sub { return $_[0] if exists $enum{$_[0]};
          $err->($path, $_[0], "invalid enum");
        };
}

sub _totalDigits($$$)
{   my $nr = $_[2];
    sub { sprintf "%${nr}f", $_[0] };
}

sub _fractionDigits($$$)
{   my $nr = $_[2];
    sub { sprintf "%.${nr}f", $_[0] };
}

sub _totalFracDigits($$$)
{   my ($td,$fd) = @{$_[2]};
    sub { sprintf "%${td}.${fd}f", $_[0] };
}

sub _length($$$)
{   my ($path, $args, $len) = @_;
    my $err = $args->{err};
    sub { return $_[0] if defined $_[0] && length $_[0]==$len;
          $err->($path, $_[0], "required length $len");
            length($_[0]) < $len
          ? $_[0].('X' x ($len-length($_[0])))
          : substr($_[0], 0, $len)
        };
}

sub _minLength($$$)
{   my ($path, $args, $len) = @_;
    my $err = $args->{err};
    sub { return $_[0] if defined $_[0] && length $_[0]>=$len;
          $err->($path, $_[0], "required min length $len");
          $_[0].('X' x ($len-length($_[0])));
        };
}

sub _maxLength($$$)
{   my ($path, $args, $len) = @_;
    my $err = $args->{err};
    sub { return $_[0] if defined $_[0] && length $_[0] <= $len;
          $err->($path, $_[0], "max length $len");
          substr $_[0], 0, $len;
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
        s/(?<!\\)\(/(?:/g;       # incorrect, performance
        s/\\p\{..\}/\\p{Is$1}/g;
        s/\\P\{..\}/\\P{Is$1}/g;
    }

    local $" = '|';
    my $pat = qr/@pats/;
    my $err = $args->{err};

    sub { return $_[0] if $_[0] =~ $pat;
          $err->($path, $_[0], "does not match pattern $pat");
          ();
        };
}

1;
