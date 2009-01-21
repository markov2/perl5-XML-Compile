use warnings;
use strict;

package XML::Compile::Util;
use base 'Exporter';

my @constants  = qw/XMLNS SCHEMA1999 SCHEMA2000 SCHEMA2001 SCHEMA2001i/;
our @EXPORT    = qw/pack_type unpack_type/;
our @EXPORT_OK =
  ( qw/pack_id unpack_id odd_elements even_elements type_of_node escape/
  , @constants
  );
our %EXPORT_TAGS = (constants => \@constants);

use constant XMLNS       => 'http://www.w3.org/XML/1998/namespace';
use constant SCHEMA1999  => 'http://www.w3.org/1999/XMLSchema';
use constant SCHEMA2000  => 'http://www.w3.org/2000/10/XMLSchema';
use constant SCHEMA2001  => 'http://www.w3.org/2001/XMLSchema';
use constant SCHEMA2001i => 'http://www.w3.org/2001/XMLSchema-instance';

use Log::Report 'xml-compile';

=chapter NAME

XML::Compile::Util - Utility routines for XML::Compile components

=chapter SYNOPSIS
 use XML::Compile::Util;
 my $node_type = pack_type $ns, $localname;
 my ($ns, $localname) = unpack_type $node_type;

=chapter DESCRIPTION
The functions provided by this package are used by various XML::Compile
components, which on their own may be unrelated.

=chapter FUNCTIONS

=section Constants

The following URIs are exported as constants, to avoid typing
in the same long URIs each time again: XMLNS, SCHEMA1999,
SCHEMA2000, SCHEMA2001, and SCHEMA2001i.

=section Packing

=function pack_type [NAMESPACE], LOCALNAME
Translates the arguments into one compact string representation of
the node type.  When the NAMESPACE is not present, C<undef>, or an
empty string, then no namespace is presumed, and no curly braces
part made.

=example
 print pack_type 'http://my-ns', 'my-type';
 # shows:  {http://my-ns}my-type 

 print pack_type 'my-type';
 print pack_type undef, 'my-type';
 print pack_type '', 'my-type';
 # all three show:   my-type

=cut

sub pack_type($;$)
{      @_==1 ? $_[0]
    : !defined $_[0] || !length $_[0] ? $_[1]
    : "{$_[0]}$_[1]"
}

=function unpack_type STRING
Returns a LIST of two elements: the name-space and the localname, as
included in the STRING.  That STRING must be compatible with the
result of M<pack_type()>.  When no name-space is present, an empty
string is used.
=cut

sub unpack_type($) { $_[0] =~ m/^\{(.*?)\}(.*)$/ ? ($1, $2) : ('', $_[0]) }

=function pack_id NAMESPACE, ID
Translates the two arguments into one compact string representation of
the node id.
=example
 print pack_id 'http://my-ns', 'my-id';
 # shows:  http://my-ns#my-id
=cut

sub pack_id($$) { "$_[0]#$_[1]" }

=function unpack_type STRING
Returns a LIST of two elements: the name-space and the id, as
included in the STRING.  That STRING must be compatible with the
result of M<pack_id()>.
=cut

sub unpack_id($) { split /\#/, $_[0], 2 }

=section Other

=function odd_elements LIST
Returns the odd-numbered elements from the LIST.

=function even_elements LIST
Returns the even-numbered elements from the LIST.
=cut

sub odd_elements(@)  { my $i = 0; map {$i++ % 2 ? $_ : ()} @_ }
sub even_elements(@) { my $i = 0; map {$i++ % 2 ? () : $_} @_ }

=function type_of_node NODE
Translate an XML::LibXML::Node into a packed type.
=cut

sub type_of_node($)
{   my $node = shift or return ();
    pack_type $node->namespaceURI, $node->localName;
}

1;
