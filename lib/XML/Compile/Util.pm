use warnings;
use strict;

package XML::Compile::Util;
use base 'Exporter';

our @EXPORT = qw/pack_type unpack_type pack_id unpack_id
  odd_elements/;

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
=function pack_type NAMESPACE, LOCALNAME
Translates the two arguments into one compact string representation of
the node type.
=example
 print pack_type 'http://my-ns', 'my-type';
 # shows:  {http://my-ns}my-type 
=cut

sub pack_type($$) {
   defined $_[0] && defined $_[1]
       or report PANIC => "pack_type with undef `$_[0]' or `$_[1]'";
   "{$_[0]}$_[1]"
}

=function unpack_type STRING
Returns a LIST of two elements: the name-space and the localname, as
included in the STRING.  That STRING must be compatible with the
result of M<pack_type()>.
=cut

sub unpack_type($) { $_[0] =~ m/^\{(.*?)\}(.*)$/ ? ($1, $2) : () }

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

=function odd_elements LIST
Returns the odd-numbered elements in the list.
=cut

sub odd_elements(@)
{   my $i = 0;
    map {$i++ % 2 ? $_ : ()} @_;
}

1;
