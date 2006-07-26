use warnings;
use strict;

package XML::Compile::Schema::BuiltInTypes;
use base 'Exporter';

our @EXPORT = qw/%builtin_types/;

our %builtin_types;

use Regexp::Common   qw/URI/;
use MIME::Base64;
use POSIX            qw/strftime/;

# use XML::RegExp;  ### can we use this?

=chapter NAME

XML::Compile::Schema::BuiltInTypes - Define handling of built-in data-types

=chapter SYNOPSIS

 # Not for end-users
 use XML::Compile::Schema::BuiltInTypes qw/%builtin_types/;

=chapter DESCRIPTION

Different schema specifications specify different available types,
but there is a lot over overlap.  The M<XML::Compile::Schema::Specs>
module defines the availability, but here the types are implemented.

The implementation certainly does not try to be minimal (using the
restriction rules as set in the schema specification), because that
would be too slow.

=section Any

=over 4

=cut

# The XML reader calls
#     check(parse(value))  or check_read(parse(value))
# The XML writer calls
#     check(format(value)) or check_write(format(value))

sub identity { $_[0] };
sub str2int  { use warnings FATAL => 'all'; eval {$_[0] + 0} };
sub int2str  { use warnings FATAL => 'all'; eval {sprintf "%ld", $_[0]} };
sub num2str  { use warnings FATAL => 'all'; eval {sprintf "%lf", $_[0]} };
sub str      { "$_[0]" };
sub collapse { $_[0] =~ s/\s+//g; $_[0]}
sub preserve { for($_[0]) {s/\s+/ /g; s/^ //; s/ $//}; $_[0]}
sub bigint   { $_[0] =~ s/\s+//g; my $v = Math::BigInt->new($_[0]);
               $v->is_nan ? undef : $v }
sub bigfloat { $_[0] =~ s/\s+//g; my $v = Math::BigFloat->new($_[0]);
               $v->is_nan ? undef : $v }

=item anySimpleType
=item anyType
Both any*Type built-ins can contain any kind of data.  Perl decides how
to represent the passed values.
=cut

$builtin_types{anySimpleType} =
$builtin_types{anyType}       = { };

=back

=section Single

=over 4

=item boolean
Contains C<true>, C<false>, C<1> (is true), or C<0> (is false).  Unchecked,
the actual value is used.  Otherwise, C<0> and C<1> are preferred for the
hash value and C<true> and C<false> in XML.
=cut

$builtin_types{boolean} =
 { parse  => \&collapse
 , format => sub { $_[0] eq 'false' || $_[0] eq 'true' ? $_[0] : !!$_[0] }
 , check  => sub { $_[0] =~ m/^(false|true|0|1)$/ }
 };

=back

=section Big Integers
Schema's define integer types which are derived from the C<decimal>
type.  These values can grow enormously large, and therefore can only be
handled correctly using M<Math::BigInt>.  When the translator is
built with the C<sloppy_integers> option, this will simplify (speed-up)
the produced code considerably: all integers then shall be between
-2G and +2G.

=over 4 

=item integer
An integer with an undertermined, but maximally huge number of
digits.
=cut

$builtin_types{integer} =
 { parse => \&bigint
 , check => sub { $_[0] =~ m/^\s*[-+]?\s*\d[\s\d]*$/ }
 };

=item negativeInteger
=cut

$builtin_types{negativeInteger} =
 { parse => \&bigint
 , check => sub { $_[0] =~ m/^\s*\-\s*\d[\s\d]*$/ }
 };

=item nonNegativeInteger
=cut

$builtin_types{nonNegativeInteger} =
 { parse => \&bigint
 , check => sub { $_[0] =~ m/^\s*(?:\+\s*)?\d[\s\d]*$/ }
 };

=item positiveInteger
=cut

$builtin_types{positiveInteger} =
 { parse => \&bigint
 , check => sub { $_[0] =~ m/^\s*(?:\+\s*)?\d[\s\d]*$/ && m/[1-9]/ }
 };

=item nonPositiveInteger
=cut

$builtin_types{nonPositiveInteger} =
 { parse => \&bigint
 , check => sub { $_[0] =~ m/^\s*(?:\-\s*)?\d[\s\d]*$/
               || $_[0] =~ m/^\s*(?:\+\s*)0[0\s]*$/ }
 };

=item long
A little bit shorter than an integer, but still up-to 19 digits.
=cut

$builtin_types{long} =
 { parse => \&bigint
 , check =>
     sub { $_[0] =~ m/^\s*[-+]?\s*\d[\s\d]*$/ && ($_[0] =~ tr/0-9//) < 20 }
 };

=item unsignedLong
Value up-to 20 digits.
=cut

$builtin_types{unsignedLong} =
 { parse => \&bigint
 , check => sub {$_[0] =~ m/^\s*\+?\s*\d[\s\d]*$/ && ($_[0] =~ tr/0-9//) < 21}
 };

=item unsignedInt
Just too long to fit in Perl's ints.
=cut

$builtin_types{unsignedInt} =
 { parse => \&bigint
 , check => sub {$_[0] =~ m/^\s*\+?\s*\d[\s\d]*$/ && ($_[0] =~ tr/0-9//) < 10}
 };

# Used when 'sloppy_integers' was set: the size of the values
# is illegally limited to the size of Perl's 32-bit signed integers.

$builtin_types{non_pos_int} =
 { parse  => \&str2int
 , format => \&int2str
 , check  => sub {$_[0] =~ m/^\s*[+-]?\s*\d[\d\s]*$/ && $_[0] <= 0}
 };

$builtin_types{positive_int} =
 { parse  => \&str2int
 , format => \&int2str
 , check  => sub {$_[0] =~ m/^\s*(?:\+\s*)?\d[\d\s]*$/ }
 };

$builtin_types{negative_int} =
 { parse  => \&str2int
 , format => \&int2str
 , check  => sub {$_[0] =~ m/^\s*\-\s*\d[\d\s]*$/ }
 };

$builtin_types{unsigned_int} =
 { parse  => \&str2int
 , format => \&int2str
 , check  => sub {$_[0] =~ m/^\s*(?:\+\s*)?\d[\d\s]*$/ && $_[0] >= 0}
 };

=back

=section Integers

=over 4

=item int
=cut

$builtin_types{int} =
 { parse  => \&str2int
 , format => \&int2str
 , check  => sub {$_[0] =~ m/^\s*[+-]?\d+\s*$/}
 };

=item short
Signed 16-bits value.
=cut

$builtin_types{short} =
 { parse  => \&str2int
 , format => \&int2str
 , check  =>
    sub { $_[0] =~ m/^\s*[+-]?\d+\s*$/ && $_[0] >= -32768 && $_[0] <= 32767 }
 };

=item unsigned Short
unsigned 16-bits value.
=cut

$builtin_types{unsignedShort} =
 { parse  => \&str2int
 , format => \&int2str
 , check  =>
    sub { $_[0] =~ m/^\s*[+-]?\d+\s*$/ && $_[0] >= 0 && $_[0] <= 65535 }
 };

=item byte
Signed 8-bits value.
=cut

$builtin_types{byte} =
 { parse  => \&str2int
 , format => \&int2str
 , check  => sub {$_[0] =~ m/^\s*[+-]?\d+\s*$/ && $_[0] >= -128 && $_[0] <=127}
 };

=item unsignedByte
Unsigned 8-bits value.
=cut

$builtin_types{unsignedByte} =
 { parse  => \&str2int
 , format => \&int2str
 , check  => sub {$_[0] =~ m/^\s*[+-]?\d+\s*$/ && $_[0] >= 0 && $_[0] <=255}
 };

=item precissionDecimal
PARTIAL IMPLEMENTATION.  Special values INF and NaN not handled.
=cut

$builtin_types{precissionDecimal} = $builtin_types{int};

=back

=section Floating-point
PARTIAL IMPLEMENTATION: INF, NaN not handled.  The C<float> is not limited
in size, but mapped on double.

=over 4

=item decimal
Decimals are painful: they can be very large, much larger than Perl's
internal floats.  The value is therefore kept as string.
Use M<Math::BigFloat> when you need calculations.  You can also pass such
object here.
=cut

$builtin_types{decimal} =
 { parse  => \&bigfloat
 , check  => sub { my $x = eval {$_[0] + 0.0}; !$@ }
 };

=item float
A small floating-point value.

=item double
A floating-point value.

=cut

$builtin_types{float} =
$builtin_types{double} =
 { parse  => \&str2num
 , format => \&num2str
 , check  => sub { my $val = eval {$_[0] + 0.0}; !$@ }
 };

=back

=section Binary

=over 4

=item base64binary
In the hash, it will be kept as binary data.  In XML, it will be
base64 encoded.
=cut

$builtin_types{base64binary} =
 { parse  => sub { eval { decode_base64 $_[0] } }
 , format => sub { eval { encode_base64 $_[0] } }
 , check  => sub { !$@ }
 };

=item hexBinary
In the hash, it will be kept as binary data.  In XML, it will be
hex encoded, two hex digits per byte.
=cut

# (Use of) an XS implementation would be nice
$builtin_types{hexBinary} =
 { parse  =>
     sub { $_[0] =~ s/\s+//g; $_[0] =~ s/([0-9a-fA-F]{2})/chr hex $1/ge; $_[0]}
 , format => sub { join '',map {sprintf "%02X", ord $_} unpack "C*", $_[0]}
 , check  =>
     sub { $_[0] !~ m/[^0-9a-fA-F\s]/ && (($_[0] =~ tr/0-9a-fA-F//) %2)==0}
 };

=back

=section Dates

=over 4

=item date
A day, represented in localtime as C<YYYY-MM-DD> or C<YYYY-MM-DD[-+]HH:mm>.
When a decimal value is passed, it is interpreted as C<time> value in UTC,
and will be formatted as required.  When reading, the date string will
not be parsed.
=cut

$builtin_types{date} =
 { parse  => \&collapse
 , format => sub { $_[0] =~ /\D/ ? $_[0] : strftime("%Y-%m-%d", gmtime $_[0]) }
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
  /^[12]\d{3}                # year
    \-(?:0?[1-9]|1[0-2])     # month
    \-(?:0?[1-9]|[12][0-9]|3[01]) # day
    (?:[+-]\d\d?\:\d\d)?     # time-zone
    $/x }
 };

=item dateTime
A moment, represented in localtime as "date T time tz", where date is
C<YYYY-MM-DD>, time is C<HH:MM:SS> and optional, and time-zone tz
is either C<-HH:mm>, C<+HH:mm>, or C<Z> for UTC.

When a decimal value is passed, it is interpreted as C<time> value in UTC,
and will be formatted as required.  When reading, the date string will
not be parsed.
=cut

$builtin_types{dateTime} =
 { parse  => \&collapse
 , format => sub { $_[0] =~ /\D/ ? $_[0]
     : strftime("%Y-%m-%dT%H:%S%MZ", gmtime($_[0])) }
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
  /^[12]\d{3}                # year
    \-(?:0?[1-9]|1[0-2])     # month
    \-(?:0?[1-9]|[12][0-9]|3[01]) # day
    T
    (?:(?:[01]?[0-9]|2[0-3]) # hours
       \:(?:[0-5]?[0-9])     # minutes
       \:(?:[0-5]?[0-9])     # seconds
    )?
    (?:[+-]\d\d?\:\d\d|Z)?   # time-zone
    $/x ? $1 : 0 }
 };

=item gDay
Format C<---12> or C<---12+9:00> (12 days, optional time-zone)
=cut

$builtin_types{gDay} =
 { parse  => \&collapse
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
      m/^\-\-\-\d+(?:[-+]\d+\:[0-5]\d)?$/ ? 1 : 0 }
 };

=item gMonth
Format C<--9> or C<--9+7:00> (9 months, optional time-zone)
=cut

$builtin_types{gMonth} =
 { parse  => \&collapse
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
      m/^\-\-\d+(?:[-+]\d+\:[0-5]\d)?$/ ? 1 : 0 }
 };

=item gMonthDay
Format C<--9-12> or C<--9-12+7:00> (9 months 12 days, optional time-zone)
=cut

$builtin_types{gMonthDay} =
 { parse  => \&collapse
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
      m/^\-\-\d+\-\d+(?:[-+]\d+\:[0-5]\d)?$/ ? 1 : 0 }
 };

=item gYear
Format C<2006> or C<2006+7:00> (year 2006, optional time-zone)
=cut

$builtin_types{gYear} =
 { parse  => \&collapse
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
      m/^\d+(?:[-+]\d+\:[0-5]\d)?$/ ? 1 : 0 }
 };

=item gYearMonth
Format C<2006-11> or C<2006-11+7:00> (november 2006, optional time-zone)
=cut

$builtin_types{gYearMonth} =
 { parse  => \&collapse
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
      m/^\d+\-(?:0?[1-9]|1[0-2])(?:[-+]\d+\:[0-5]\d)?$/ ? 1 : 0 }
 };

=back

=section Duration

=over 4

=item duration
Format C<-PnYnMnDTnHnMnS>, where optional starting C<-> means negative.
The C<P> is obligatory, and the C<T> indicates start of a time part.
All other C<n[YMDHMS]> are optional.
=cut

$builtin_types{duration} =
 { parse  => \&collapse
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
     m/^\-?P(?:\d+Y)?(?:\d+M)?(?:\d+D)?
        (?:T(?:\d+H)?(?:\d+M)?(?:\d+(?:\.\d+)?)S)?$/x }
 };

=item dayTimeDuration
Format C<-PDTnHnMnS>, where optional starting C<-> means negative.
The C<P> is obligatory, and the C<T> indicates start of a time part.
All other C<n[DHMS]> are optional.
=cut

$builtin_types{dayTimeDuration} =
 { parse  => \&collapse
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
     m/^\-?P(?:\d+D)?(?:T(?:\d+H)?(?:\d+M)?(?:\d+(?:\.\d+)?)S)?$/ }
 };

=item yearMonthDuration
Format C<-PnYnMn>, where optional starting C<-> means negative.
The C<P> is obligatory, the C<n[YM]> are optional.
=cut

$builtin_types{yearMonthDuration} =
 { parse  => \&collapse
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
     m/^\-?P(?:\d+Y)?(?:\d+M)?$/ }
 };

=back

=section Strings

=over 4

=item string
(Usually utf8) string.
=cut

$builtin_types{string} = {};

=item normalizedString
String where all sequence of white-spaces (including new-lines) are
interpreted as one blank.  Blanks at beginning and the end of the
string are ignored.
=cut

$builtin_types{normalizedString} =
 { parse => \&preserve
 };

=item language
An RFC3066 language indicator.
=cut

$builtin_types{language} =
 { parse => \&collapse
 , check => sub { my $v = $_[0]; $v =~ s/\s+//g; $v =~
       m/^[a-zA-Z]{1,8}(?:\-[a-zA-Z0-9]{1,8})*$/ }
 };

=item ID, IDREF, IDREFS
A label, reference to a label, or set of references.

PARTIAL IMPLEMENTATION: the validity of used characters is not checked.
=cut

sub _valid_ncname($)
{  (my $name = $_[0]) =~ s/\s//;
   $name =~ m/^[a-zA-Z_](?:[\w.-]*)$/;
}

$builtin_types{ID} =
$builtin_types{IDREF} =
$builtin_types{NCName} =
$builtin_types{ENTITY} =
 { parse  => \&collapse
 , check  => sub { $_[0] !~ m/\:/ }
 };

$builtin_types{IDREFS} =
$builtin_types{ENTITIES} =
 { parse  => \&preserve
 , check  => sub { $_[0] !~ m/\:/ }
 };

=item NCName, ENTITY, ENTITIES
A name which contains no colons (a non-colonized name).

=item Name
=cut

$builtin_types{Name} =
$builtin_types{token} =
$builtin_types{NMTOKEN} =
 { parse  => \&collapse
 };

=item token, NMTOKEN, NMTOKENS
=cut

$builtin_types{NMTOKENS} =
 { parse  => \&preserve
 };

=back

=section URI

=over 4

=item anyURI
You may pass a string or, for instance, an M<URI> object which will be
stringified into an URI.  When read, the data will not automatically
be translated into an URI object: it may not be used that way.
=cut

$builtin_types{anyURI} =
 { parse  => \&collapse
 , check  => sub { $_[0] =~ $RE{URI} }
 };

=item QName
A qualified type name: a type name with optional prefix.
=cut

sub _valid_qname($)
{   my @ncnames = split /\:/, $_[0];
    return 0 if @ncnames > 2;
    _valid_ncname($_) || return 0 for @ncnames;
    1;
}

$builtin_types{QName} =
 { check  => \&_valid_qname
 };

=item NOTATION
NOT IMPLEMENTED, so treated as string.
=cut

$builtin_types{NOTATION} = {};

=back

=cut

1;


