use warnings;
use strict;

package XML::Compile::Util;
use base 'Exporter';

my @constants  = qw/XMLNS SCHEMA1999 SCHEMA2000 SCHEMA2001 SCHEMA2001i/;
our @EXPORT    = qw/pack_type unpack_type/;
our @EXPORT_OK =
  ( qw/pack_id unpack_id odd_elements block_label type_of_node/
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
Returns the odd-numbered elements in the list.
=cut

sub odd_elements(@)
{   my $i = 0;
    map {$i++ % 2 ? $_ : ()} @_;
}

=function block_label KIND, LABEL
Particle blocks, like `sequence' and `choice', which have a maxOccurs
(maximum occurrence) which is 2 of more, are represented by an ARRAY
of HASHs.  The label with such a block is derived from its first element.
This function determines how.

The KIND of block is abbreviated, and prepended before the LABEL.  When
the LABEL already had a block abbreviation (which may be caused by nested
blocks), that will be stripped first.

An element KIND of block is found in substitution groups.  That label
will not change.

=examples labels for blocks with maxOccurs > 1
  seq_address      # sequence get seq_ prepended
  cho_gender       # choices get cho_ before them
  all_money        # an all block can also be repreated in spec >1.1
  gr_people        # group refers to a block of above type, but
                   #    that type is not reflected in the name
=cut

my %block_abbrev = qw/sequence seq_  choice cho_  all all_  group gr_/;
sub block_label($$)
{   my ($kind, $label) = @_;
    return $label if $kind eq 'element';

    $label =~ s/^(?:seq|cho|all|gr)_//;
    $block_abbrev{$kind} . (unpack_type $label)[1];
}

=function type_of_node NODE
Translate an XML::LibXML::Node into a packed type.
=cut

sub type_of_node($)
{   my $node = shift or return ();
    pack_type $node->namespaceURI, $node->localName;
}

1;
