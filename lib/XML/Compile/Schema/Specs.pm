
use warnings;
use strict;

package XML::Compile::Schema::Specs;

use Log::Report 'xml-compile', syntax => 'SHORT';

use XML::Compile::Schema::BuiltInTypes   qw/%builtin_types/;
use XML::Compile::Util qw/SCHEMA1999 SCHEMA2000 SCHEMA2001 unpack_type/;

=chapter NAME

XML::Compile::Schema::Specs - Predefined Schema Information

=chapter SYNOPSIS

 # not for end-users
 use XML::Compile::Schema::Specs;

=chapter DESCRIPTION
This package defines the various schema-specifications.

=chapter METHODS

=cut

### Who will extend this?
# everything which is not caught by a special will need to pass through
# the official meta-scheme: the scheme of the scheme.  These lists are
# used to restrict the namespace to the specified, hiding all helper
# types.

my @builtin_common = qw/
 boolean
 byte
 date
 decimal
 double
 duration
 ENTITIES
 ENTITY
 float
 ID
 IDREF
 IDREFS
 int
 integer
 language
 long
 Name
 NCName
 negativeInteger
 NMTOKEN
 NMTOKENS
 nonNegativeInteger
 nonPositiveInteger
 NOTATION
 positiveInteger
 QName
 short
 string
 time
 token
 unsignedByte
 unsignedInt
 unsignedLong
 unsignedShort
 yearMonthDuration
 /;

my @builtin_extra_1999 = qw/
 binary
 recurringDate
 recurringDay
 recurringDuration
 timeDuration
 timeInstant
 timePeriod
 uriReference
 year
 /;

my @builtin_extra_2000 = (@builtin_extra_1999, qw/
 anyType
 CDATA
 / );

my @builtin_extra_2001  = qw/
 anySimpleType
 anyType
 anyURI
 base64binary
 dateTime
 dayTimeDuration
 gDay
 gMonth
 gMonthDay
 gYear
 gYearMonth
 hexBinary
 normalizedString
 precissionDecimal
 /;

my %builtin_public_1999 = map { ($_ => $_) }
   @builtin_common, @builtin_extra_1999;

my %builtin_public_2000 = map { ($_ => $_) }
   @builtin_common, @builtin_extra_2000;

my %builtin_public_2001 = map { ($_ => $_) }
   @builtin_common, @builtin_extra_2001;

my %sloppy_int_version =
 ( decimal            => 'double'
 , integer            => 'int'
 , long               => 'int'
 , nonNegativeInteger => 'unsigned_int'
 , nonPositiveInteger => 'non_pos_int'
 , positiveInteger    => 'positive_int'
 , negativeInteger    => 'negative_int'
 , unsignedLong       => 'unsigned_int'
 , unsignedInt        => 'unsigned_int'
 );

my %schema_1999 =
 ( uri_xsd => SCHEMA1999
 , uri_xsi => SCHEMA1999.'-instance'

 , builtin_public => \%builtin_public_1999
 );

my %schema_2000 =
 ( uri_xsd => SCHEMA2000
 , uri_xsi => SCHEMA2000.'-instance'

 , builtin_public => \%builtin_public_2000
 );

my %schema_2001 =
 ( uri_xsd  => SCHEMA2001
 , uri_xsi  => SCHEMA2001 .'-instance'

 , builtin_public => \%builtin_public_2001
 );

my %schemas = map { ($_->{uri_xsd} => $_) }
 \%schema_1999, \%schema_2000, \%schema_2001;

=c_method predefinedSchemas
Returns the uri of all predefined schemas.
=cut

sub predefinedSchemas() { keys %schemas }

=c_method predefinedSchema URI
Return a HASH which contains the schema information for the specified
URI (or undef if it doesn't exist).
=cut

sub predefinedSchema($) { defined $_[1] ? $schemas{$_[1]} : () }

=c_method builtInType (NODE|undef), EXPANDED | (URI,LOCAL), OPTIONS
Provide an EXPANDED (full) type name or an namespace URI and a LOCAL node
name.  Returned is a HASH with process information or C<undef> if not
found.

=option  sloppy_integers BOOLEAN
=default sloppy_integers <false>
the <decimal> and <integer> types must accept huge integers, which
require C<Math::Big*> objects to process.  But often, Perl's normal
signed 32bit integers suffice... which is good for performance, but not
standard compliant.
=cut

sub builtInType($$;$@)
{   my ($class, $node, $ns) = (shift, shift, shift);
    my $name = @_ % 1 ? shift : undef;
    ($ns, $name) = unpack_type $ns
        unless defined $name;

    my $schema = $schemas{$ns}
        or return ();

    my %args = @_;

    return $builtin_types{$sloppy_int_version{$name}}
        if $args{sloppy_integers} && exists $sloppy_int_version{$name};

    # only official names are exported this way
    my $public = $schema->{builtin_public}{$name};
    defined $public ? $builtin_types{$public} : ();
}

1;
