use warnings;
use strict;

package XML::Compile::Schema::BuiltInTypes;
use base 'Exporter';

our @EXPORT = qw/%builtin_types/;

our %builtin_types;

use Log::Report     'xml-compile', syntax => 'SHORT';
use POSIX           qw/strftime/;
use Math::BigInt;
use Math::BigFloat;
use MIME::Base64;

use XML::Compile::Util qw/pack_type unpack_type/;

=chapter NAME

XML::Compile::Schema::BuiltInTypes - Define handling of built-in data-types

=chapter SYNOPSIS

 # Not for end-users
 use XML::Compile::Schema::BuiltInTypes qw/%builtin_types/;

=chapter DESCRIPTION

Different schema specifications specify different available types,
but there is a lot over overlap.  The M<XML::Compile::Schema::Specs>
module defines the availability, but here the types are implemented.

This implementation certainly does not try to be minimal in size: using
the restriction rules and inheritance structure defined in the schema
specification would be too slow.

=chapter FUNCTIONS

The functions named in this chapter are all used at compile-time
by the translator.  At that moment, they will be placed in the
kind-of opcode tree which will process the data at run-time.
You B<cannot call> these functions yourself.

=section Any

=cut

# The XML reader calls
#     check(parse(value))  or check_read(parse(value))

# The XML writer calls
#     check(format(value)) or check_write(format(value))

# Parse has a second argument, only for QNAME: the node
# Format has a second argument for QNAME as well.

sub identity  { $_[0] }

# already validated, unless that is disabled.
sub str2int   { $_[0] + 0 }

# sprintf returns '0' if non-int, with warning. We need a validation error
sub int2str   { $_[0] =~ m/^\s*[0-9]+\s*$/ ? sprintf("%ld", $_[0]) : $_[0] }

sub str       { "$_[0]" }
sub _replace  { $_[0] =~ s/[\t\r\n]/ /g; $_[0]}
sub _collapse { local $_ = $_[0]; s/[\t\r\n]+/ /g; s/^ +//; s/ +$//; $_}

=function anySimpleType
=function anyType
Both any*Type built-ins can contain any kind of data.  Perl decides how
to represent the passed values.
=cut

# format not useful, because xsi:type not supported
$builtin_types{anySimpleType} =
$builtin_types{anyType} =
 { example => 'anything'
 , parse   => sub {shift}
 };

=function error
=cut
$builtin_types{error}   = {example => '[some error structure]'};

=section Ungrouped types

=function boolean
Contains C<true>, C<false>, C<1> (is true), or C<0> (is false).
When the writer sees a value equal to 'true' or 'false', those are
used.  Otherwise, the trueth value is evaluated into '0' or '1'.

The reader will return '0' (also when the XML contains the string
'false', to simplify the Perl code) or '1'.
=cut

$builtin_types{boolean} =
 { parse   => sub { $_[0] =~ m/^\s*false|0\s*/i ? 0 : 1 }
 , format  => sub { $_[0] eq 'false' || $_[0] eq 'true' ? $_[0]
                  : $_[0] ? 1 : 0 }
 , check   => sub { $_[0] =~ m/^\s*(?:false|true|0|1)\s*$/i }
 , example => 'true'
 };

=function pattern
=cut

$builtin_types{pattern} =
 { example => '*.exe'
 };

=section Big Integers

Schema's define integer types which are derived from the C<decimal>
type.  These values can grow enormously large, and therefore can only be
handled correctly using M<Math::BigInt>.  When the translator is
built with the C<sloppy_integers> option, this will simplify (speed-up)
the produced code considerably: all integers then shall be between
-2G and +2G.

=function integer
An integer with an undertermined (but possibly large) number of
digits.
=cut

sub bigint
{   $_[0] =~ s/\s+//g;
    my $v = Math::BigInt->new($_[0]);
    error __x"Value `{val}' is not a (big) integer", val => $v if $v->is_nan;
    $v;
}

$builtin_types{integer} =
 { parse   => \&bigint
 , check   => sub { $_[0] =~ m/^\s*[-+]?\s*\d[\s\d]*$/ }
 , example => 42
 };

=function negativeInteger
=cut

$builtin_types{negativeInteger} =
 { parse   => \&bigint
 , check   => sub { $_[0] =~ m/^\s*\-\s*\d[\s\d]*$/ }
 , example => '-1'
 };

=function nonNegativeInteger
=cut

$builtin_types{nonNegativeInteger} =
 { parse   => \&bigint
 , check   => sub { $_[0] =~ m/^\s*(?:\+\s*)?\d[\s\d]*$/ }
 , example => '17'
 };

=function positiveInteger
=cut

$builtin_types{positiveInteger} =
 { parse   => \&bigint
 , check   => sub { $_[0] =~ m/^\s*(?:\+\s*)?\d[\s\d]*$/ && $_[0] =~ m/[1-9]/ }
 , example => '+3'
 };

=function nonPositiveInteger
=cut

$builtin_types{nonPositiveInteger} =
 { parse   => \&bigint
 , check   => sub { $_[0] =~ m/^\s*(?:\-\s*)?\d[\s\d]*$/
                 || $_[0] =~ m/^\s*(?:\+\s*)0[0\s]*$/ }
 , example => '-42'
 };

=function long
A little bit shorter than an integer, but still up-to 19 digits.
=cut

$builtin_types{long} =
 { parse   => \&bigint
 , check   =>
     sub { $_[0] =~ m/^\s*[-+]?\s*\d[\s\d]*$/ && ($_[0] =~ tr/0-9//) < 20 }
 , example => '-100'
 };

=function unsignedLong
Value up-to 20 digits.
=cut

$builtin_types{unsignedLong} =
 { parse   => \&bigint
 , check   => sub {$_[0] =~ m/^\s*\+?\s*\d[\s\d]*$/ && ($_[0] =~ tr/0-9//) < 21}
 , example => '100'
 };

=function unsignedInt
Just too long to fit in Perl's ints.
=cut

$builtin_types{unsignedInt} =
 { parse   => \&bigint
 , check   => sub {$_[0] =~ m/^\s*\+?\s*\d[\s\d]*$/ && ($_[0] =~ tr/0-9//) <10}
 , example => '42'
 };

# Used when 'sloppy_integers' was set: the size of the values
# is illegally limited to the size of Perl's 32-bit signed integers.

$builtin_types{non_pos_int} =
 { parse   => \&str2int
 , format  => \&int2str
 , check   => sub {$_[0] =~ m/^\s*[+-]?\s*\d[\d\s]*$/ && $_[0] <= 0}
 , example => '-12'
 };

$builtin_types{positive_int} =
 { parse   => \&str2int
 , format  => \&int2str
 , check   => sub {$_[0] =~ m/^\s*(?:\+\s*)?\d[\d\s]*$/ }
 , example => '+42'
 };

$builtin_types{negative_int} =
 { parse   => \&str2int
 , format  => \&int2str
 , check   => sub {$_[0] =~ m/^\s*\-\s*\d[\d\s]*$/ }
 , example => '-12'
 };

$builtin_types{unsigned_int} =
 { parse   => \&str2int
 , format  => \&int2str
 , check   => sub {$_[0] =~ m/^\s*(?:\+\s*)?\d[\d\s]*$/ && $_[0] >= 0}
 , example => '42'
 };

=section Integers

=function int
=cut

$builtin_types{int} =
 { parse   => \&str2int
 , format  => \&int2str
 , check   => sub {$_[0] =~ m/^\s*[+-]?\d+\s*$/}
 , example => '42'
 };

=function short
Signed 16-bits value.
=cut

$builtin_types{short} =
 { parse   => \&str2int
 , format  => \&int2str
 , check   =>
    sub { $_[0] =~ m/^\s*[+-]?\d+\s*$/ && $_[0] >= -32768 && $_[0] <= 32767 }
 , example => '-7'
 };

=function unsigned Short
unsigned 16-bits value.
=cut

$builtin_types{unsignedShort} =
 { parse  => \&str2int
 , format => \&int2str
 , check  =>
    sub { $_[0] =~ m/^\s*[+-]?\d+\s*$/ && $_[0] >= 0 && $_[0] <= 65535 }
 , example => '7'
 };

=function byte
Signed 8-bits value.
=cut

$builtin_types{byte} =
 { parse   => \&str2int
 , format  => \&int2str
 , check   => sub {$_[0] =~ m/^\s*[+-]?\d+\s*$/ && $_[0] >= -128 && $_[0] <=127}
 , example => '-2'
 };

=function unsignedByte
Unsigned 8-bits value.
=cut

$builtin_types{unsignedByte} =
 { parse   => \&str2int
 , format  => \&int2str
 , check   => sub {$_[0] =~ m/^\s*[+-]?\d+\s*$/ && $_[0] >= 0 && $_[0] <= 255}
 , example => '2'
 };

=section Floating-point

=function decimal
Decimals are painful: they can be very large, much larger than Perl's
internal floats.  The value is therefore kept as string.
Use M<Math::BigFloat> when you need calculations.  You can also pass such
object here.
=cut

$builtin_types{decimal} =
 { parse   => sub {$_[0] =~ s/\s+//g; Math::BigFloat->new($_[0]) }
 , check   => sub {$_[0] =~ m#^(\+|\-)?([0-9]+(\.[0-9]*)?|\.[0-9]+)$#}
 , example => '3.1415'
 };

=function precissionDecimal
Floating point value that closely corresponds to the floating-point
decimal datatypes described by IEEE/ANSI754.

=function float
A small floating-point value "m x 2**e" where m is an integer whose absolute
value is less than 224, and e is an integer between −149 and 104, inclusive.

The implementation does not limited the float in size, but maps it onto an
precissionDecimal (M<Math::BigFloat>) unless C<sloppy_float> is set.

=function double
A floating-point value "m x 2**e", where m is an integer whose absolute
value is less than 253, and e is an integer between −1074 and 971, inclusive.

The implementation does not limited the double in size, but maps it onto an
precissionDecimal (M<Math::BigFloat>) unless C<sloppy_float> is set.

=cut

sub str2num
{   my $s = shift;
    $s =~ s/\s//g;

      $s =~ m/[^0-9]/ ? Math::BigFloat->new($s eq 'NaN' ? $s : lc $s) # INF->inf
    : length $s < 9   ? $s+0
    :                   Math::BigInt->new($s);
}

sub num2str
{   my $f = shift;
      !ref $f         ? $f
    : !(UNIVERSAL::isa($f,'Math::BigInt') || UNIVERSAL::isa($f,'Math::BigFloat'))
    ? eval {use warnings FATAL => 'all'; $f + 0.0}
    : $f->is_nan      ? 'NaN'
    :                   uc $f->bstr;  # [+-]inf -> [+-]INF,  e->E doesn't matter
}

sub numcheck($)
{   $_[0] =~
      m# [+-]? (?: [0-9]+(?:\.[0-9]*)?|\.[0-9]+) (?:[Ee][+-]?[0-9]+)?
       | [+-]? INF
       | NaN #x
}

$builtin_types{precissionDecimal} =
$builtin_types{float}  =
$builtin_types{double} =
 { parse   => \&str2num
 , format  => \&num2str
 , check   => \&numcheck
 , example => '3.1415'
 };

$builtin_types{sloppy_float} =
 { check => sub {
      my $v = eval {use warnings FATAL => 'all'; $_[0] + 0.0};
      $@ ? undef : 1;
    }
 , example => '3.1415'
 };

=section Encoding

=function base64Binary
In the hash, it will be kept as binary data.  In XML, it will be
base64 encoded.
=cut

$builtin_types{base64Binary} =
 { parse   => sub { eval { decode_base64 $_[0] } }
 , format  => sub { eval { encode_base64 $_[0] } }
 , check   => sub { !$@ }
 , example => 'VGVzdA=='
 };

=function hexBinary
In the hash, it will be kept as binary data.  In XML, it will be
hex encoded, two hex digits per byte.
=cut

# (Use of) an XS implementation would be nice
$builtin_types{hexBinary} =
 { parse   =>
     sub { $_[0] =~ s/\s+//g; $_[0] =~ s/([0-9a-fA-F]{2})/chr hex $1/ge; $_[0]}
 , format  =>
     sub { join '',map {sprintf "%02X", ord $_} unpack "C*", $_[0]}
 , check   =>
     sub { $_[0] !~ m/[^0-9a-fA-F\s]/ && (($_[0] =~ tr/0-9a-fA-F//) %2)==0}
 , example => 'F00F'
 };

=section Dates

=function date
A day, represented in localtime as C<YYYY-MM-DD> or C<YYYY-MM-DD[-+]HH:mm>.
When a decimal value is passed, it is interpreted as C<time> value in UTC,
and will be formatted as required.  When reading, the date string will
not be parsed.
=cut

my $yearFrag     = qr/ \-? (?: [1-9]\d{3,} | 0\d\d\d ) /x;
my $monthFrag    = qr/ 0[1-9] | 1[0-2] /x;
my $dayFrag      = qr/ 0[1-9] | [12]\d | 3[01] /x;
my $hourFrag     = qr/ [01]\d | 2[0-3] /x;
my $minuteFrag   = qr/ [0-5]\d /x;
my $secondFrag   = qr/ [0-5]\d (?: \.\d+)? /x;
my $endOfDayFrag = qr/24\:00\:00 (?: \.\d+)? /x;
my $timezoneFrag = qr/Z | [+-] (?: 0\d | 1[0-4] ) \: $minuteFrag/x;
my $timeFrag     = qr/ (?: $hourFrag \: $minuteFrag \: $secondFrag )
                     | $endOfDayFrag
                     /x;

my $date = qr/^ $yearFrag \- $monthFrag \- $dayFrag $timezoneFrag? $/x;

$builtin_types{date} =
 { parse   => \&_collapse
 , format  => sub { $_[0] =~ /\D/ ? $_[0] : strftime("%Y-%m-%d", gmtime $_[0])}
 , check   => sub { (my $val = $_[0]) =~ s/\s+//g; $val =~ $date }
 , example => '2006-10-06'
 };

=function time
An moment in time, as can happen every day.
=cut

my $time = qr /^ $timeFrag $timezoneFrag? $/x;

$builtin_types{time} =
 { parse   => \&_collapse
 , format  => sub { return $_[0] if $_[0] =~ /[^0-9.]/;
      my $subsec = $_[0] =~ /(\.\d+)/ ? $1 : '';
      strftime "%T$subsec", gmtime $_[0] }
 , check   => sub { (my $val = $_[0]) =~ s/\s+//g; $val =~ $time }
 , example => '11:12:13'
 };

=function dateTime
A moment, represented as "date T time tz", where date is C<YYYY-MM-DD>,
time is C<HH:MM:SS>, and time-zone tz is either C<-HH:mm>, C<+HH:mm>,
or C<Z> for UTC.  The time-zone is optional, but can better be used
because the default is not defined in the standard.

When a decimal value is passed, it is interpreted as C<time> value in UTC,
and will be formatted as required.  When reading, the date string will
not be parsed.
=cut

my $dateTime = qr/^ $yearFrag \- $monthFrag \- $dayFrag
                    T $timeFrag $timezoneFrag? $/x;

$builtin_types{dateTime} =
 { parse   => \&_collapse
 , format  => sub { return $_[0] if $_[0] =~ /[^0-9.]/;
       my $subsec = $_[0] =~ /(\.\d+)/ ? $1 : '';
       strftime "%Y-%m-%dT%H:%M:%S${subsec}Z", gmtime $_[0] }
 , check   => sub { (my $val = $_[0]) =~ s/\s+//g; $val =~ $dateTime }
 , example => '2006-10-06T00:23:02Z'
 };

=function gDay
Format C<---12> or C<---12+09:00> (12 days, optional time-zone)
=cut

my $gDay = qr/^ \- \- \- $dayFrag $timezoneFrag? $/x;
$builtin_types{gDay} =
 { parse   => \&_collapse
 , check   => sub { (my $val = $_[0]) =~ s/\s+//g; $val =~ $gDay }
 , example => '---12+09:00'
 };

=function gMonth
Format C<--09> or C<--09+07:00> (9 months, optional time-zone)
=cut

my $gMonth = qr/^ \- \- $monthFrag $timezoneFrag? $/x;
$builtin_types{gMonth} =
 { parse   => \&_collapse
 , check   => sub { (my $val = $_[0]) =~ s/\s+//g; $val =~ $gMonth }
 , example => '--09+07:00'
 };

=function gMonthDay
Format C<--09-12> or C<--09-12+07:00> (9 months 12 days, optional time-zone)
=cut

my $gMonthDay = qr/^ \- \- $monthFrag \- $dayFrag $timezoneFrag? /x;
$builtin_types{gMonthDay} =
 { parse   => \&_collapse
 , check   => sub { (my $val = $_[0]) =~ s/\s+//g; $val =~ $gMonthDay }
 , example => '--09-12+07:00'
 };

=function gYear
Format C<2006> or C<2006+07:00> (year 2006, optional time-zone)
=cut

my $gYear = qr/^ $yearFrag $timezoneFrag? $/x;
$builtin_types{gYear} =
 { parse   => \&_collapse
 , check   => sub { (my $val = $_[0]) =~ s/\s+//g; $val =~ $gYear }
 , example => '2006+07:00'
 };

=function gYearMonth
Format C<2006-11> or C<2006-11+07:00> (november 2006, optional time-zone)
=cut

my $gYearMonth = qr/^ $yearFrag \- $monthFrag $timezoneFrag? $/x;
$builtin_types{gYearMonth} =
 { parse   => \&_collapse
 , check   => sub { (my $val = $_[0]) =~ s/\s+//g; $val =~ $gYearMonth }
 , example => '2006-11+07:00'
 };

=section Duration

=function duration
Format C<-PnYnMnDTnHnMnS>, where optional starting C<-> means negative.
The C<P> is obligatory, and the C<T> indicates start of a time part.
All other C<n[YMDHMS]> are optional.
=cut

$builtin_types{duration} =
 { parse   => \&_collapse
 , check   => sub { my $val = $_[0]; $val =~ s/\s+//g;
      $val =~ m/^\-?P(?:\d+Y)?(?:\d+M)?(?:\d+D)?
          (?:T(?:\d+H)?(?:\d+M)?(?:\d+(?:\.\d+)?S)?)?$/x }

 , example => 'P9M2DT3H5M'
 };

=function dayTimeDuration
Format C<-PnDTnHnMnS>, where optional starting C<-> means negative.
The C<P> is obligatory, and the C<T> indicates start of a time part.
All other C<n[DHMS]> are optional.
=cut

$builtin_types{dayTimeDuration} =
 { parse  => \&_collapse
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
     m/^\-?P(?:\d+D)?(?:T(?:\d+H)?(?:\d+M)?(?:\d+(?:\.\d+)?S)?)?$/ }
 , example => 'P2DT3H5M10S'
 };

=function yearMonthDuration
Format C<-PnYnMn>, where optional starting C<-> means negative.
The C<P> is obligatory, the C<n[YM]> are optional.
=cut

$builtin_types{yearMonthDuration} =
 { parse  => \&_collapse
 , check  => sub { my $val = $_[0]; $val =~ s/\s+//g; $val =~
     m/^\-?P(?:\d+Y)?(?:\d+M)?$/ }
 , example => 'P40Y5M'
 };

=section Strings

=function string
(Usually utf8) string.
=cut

$builtin_types{string} =
 { example => 'example'
 };

=function normalizedString
String where all sequence of white-spaces (including new-lines) are
interpreted as one blank.  Blanks at beginning and the end of the
string are ignored.
=cut

$builtin_types{normalizedString} =
 { parse   => \&_replace
 , example => 'example'
 };

=function language
An RFC3066 language indicator.
=cut

$builtin_types{language} =
 { parse   => \&_collapse
 , check   => sub { my $v = $_[0]; $v =~ s/\s+//g; $v =~
       m/^[a-zA-Z]{1,8}(?:\-[a-zA-Z0-9]{1,8})*$/ }
 , example => 'nl-NL'
 };

=function ID, IDREF, IDREFS
A label, reference to a label, or set of references.

PARTIAL IMPLEMENTATION: the validity of used characters is not checked.
=cut

sub _valid_ncname($)
{  (my $name = $_[0]) =~ s/\s//;
   $name =~ m/^[a-zA-Z_](?:[\w.-]*)$/;
}

# better checks needed
#  NCName matches pattern [\i-[:]][\c-[:]]*
sub _ncname($) {sub { $_[0] !~ m/\:/ }}

my $ids = 0;
$builtin_types{ID} =
 { parse   => \&_collapse
 , check   => \&_ncname
 , example => 'id_'.$ids++
 };

$builtin_types{IDREF} =
 { parse   => \&_collapse
 , check   => \&_ncname
 , example => 'id-ref'
 };

=function NCName, ENTITY, ENTITIES
A name which contains no colons (a non-colonized name).
=cut

$builtin_types{NCName} =
$builtin_types{ENTITY} =
 { parse   => \&_collapse
 , check   => \&_ncname
 , example => 'label'
 };

$builtin_types{IDREFS} =
$builtin_types{ENTITIES} =
 { parse   => sub { [ split ' ', shift ] }
 , format  => sub { my $v = shift; ref $v eq 'ARRAY' ? join(' ',@$v) : $v }
 , check   => sub { $_[0] !~ m/\:/ }
 , example => 'labels'
 , is_list => 1
 };

=function Name
=cut

$builtin_types{Name} =
 { parse   => \&_collapse
 , example => 'name'
 };

=function token, NMTOKEN, NMTOKENS
=cut

$builtin_types{token} =
 { parse   => \&_collapse
 , example => 'token'
 };

# check required!  \c
$builtin_types{NMTOKEN} =
 { parse   => sub { $_[0] =~ s/\s+//g; $_[0] }
 , example => 'nmtoken'
 };

$builtin_types{NMTOKENS} =
 { parse   => sub { [ split ' ', shift ] }
 , format  => sub { my $v = shift; ref $v eq 'ARRAY' ? join(' ',@$v) : $v }
 , example => 'nmtokens'
 , is_list => 1
 };

=section URI

=function anyURI
You may pass a string or, for instance, an M<URI> object which will be
stringified into an URI.  When read, the data will not automatically
be translated into an URI object: it may not be used that way.
=cut

# relative uri's are also correct, so even empty strings...  it
# cannot be checked without context.
#    use Regexp::Common   qw/URI/;
#    check   => sub { $_[0] =~ $RE{URI} }

$builtin_types{anyURI} =
  { parse   => \&_collapse
  , example => 'http://example.com'
  };

=function QName
A qualified type name: a type name with optional prefix.  The prefix notation
C<prefix:type> will be translated into the C<{$ns}type> notation.

For writers, this translation can only happen when the C<$ns> is also
in use on some other place in the message: the name-space declaration
can not be added at run-time.  In other cases, you will get a run-time
error.  Play with M<XML::Compile::Schema::compile(prefixes)>,
predefining evenything what may be used, setting the C<used> count to C<1>.
=cut

$builtin_types{QName} =
 { parse   =>
     sub { my ($qname, $node) = @_;
           $qname =~ s/\s//g;
           my $prefix = $qname =~ s/^([^:]*)\:// ? $1 : '';

           $node  = $node->node if $node->isa('XML::Compile::Iterator');
           my $ns = $node->lookupNamespaceURI($prefix) || '';
           pack_type $ns, $qname;
         }
 , format  =>
    sub { my ($type, $trans) = @_;
          my ($ns, $local) = unpack_type $type;
          length $ns or return $local;

          my $def = $trans->{$ns};
          # let's hope that the namespace will get used somewhere else as
          # well, to make it into the xmlns.
          defined $def && exists $def->{used}
              or error __x"QName formatting only works if the namespace is used for an element, not found {ns} for {local}", ns => $ns, local => $local;

          length $def->{prefix} ? "$def->{prefix}:$local" : $local;
        }
 , example => 'myns:local'
 };

=function NOTATION
NOT IMPLEMENTED, so treated as string.
=cut

$builtin_types{NOTATION} = {};

=section only in 1999 and 2000/10 schemas

=function binary
Perl strings can contain any byte, also nul-strings, so can
contain any sequence of bits.  Limited to byte length.
=cut

$builtin_types{binary} = { example => 'binary string' };

=function timeDuration
'Old' name for M<duration()>.
=cut

$builtin_types{timeDuration} = $builtin_types{duration};

=function uriReference
Probably the same rules as M<anyURI()>.
=cut

$builtin_types{uriReference} = $builtin_types{anyURI};

# These constants where removed from the spec in 2001. Probably
# no-one is using these (anymore)
# century       = period   => 'P100Y'
# recurringDate = duration => 'P24H', period => 'P1Y'
# recurringDay  = duration => 'P24H', period => 'P1M'
# timeInstant   = duration => 'P0Y',  period => 'P0Y'
# timePeriod    = duration => 'P0Y'
# year          = period => 'P1Y'
# recurringDuration = ??

# only in 2000/10 schemas
$builtin_types{CDATA} =
 { parse   => \&_replace
 , example => 'CDATA'
 };

1;
