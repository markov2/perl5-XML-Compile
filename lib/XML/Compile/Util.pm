# This code is part of distribution XML-Compile.  Meta-POD processed with
# OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package XML::Compile::Util;
use base 'Exporter';

use warnings;
use strict;

my @constants  = qw/XMLNS SCHEMA1999 SCHEMA2000 SCHEMA2001 SCHEMA2001i/;
our @EXPORT    = qw/pack_type unpack_type/;
our @EXPORT_OK =
  ( qw/pack_id unpack_id odd_elements even_elements type_of_node
       escape duration2secs add_duration/
  , @constants
  );
our %EXPORT_TAGS = (constants => \@constants);

use constant
  { XMLNS       => 'http://www.w3.org/XML/1998/namespace'
  , SCHEMA1999  => 'http://www.w3.org/1999/XMLSchema'
  , SCHEMA2000  => 'http://www.w3.org/2000/10/XMLSchema'
  , SCHEMA2001  => 'http://www.w3.org/2001/XMLSchema'
  , SCHEMA2001i => 'http://www.w3.org/2001/XMLSchema-instance'
  };

use Log::Report 'xml-compile';
use POSIX  qw/mktime/;

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

=function pack_type [$ns], $localname
Translates the arguments into one compact string representation of
the node type.  When the $ns is not present, C<undef>, or an
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

=function unpack_type $string
Returns a LIST of two elements: the name-space and the localname, as
included in the $string.  That $string must be compatible with the
result of M<pack_type()>.  When no name-space is present, an empty
string is used.
=cut

sub unpack_type($) { $_[0] =~ m/^\{(.*?)\}(.*)$/ ? ($1, $2) : ('', $_[0]) }

=function pack_id $ns, $id
Translates the two arguments into one compact string representation of
the node id.
=example
 print pack_id 'http://my-ns', 'my-id';
 # shows:  http://my-ns#my-id
=cut

sub pack_id($$) { "$_[0]#$_[1]" }

=function unpack_id $string
Returns a LIST of two elements: the name-space and the id, as
included in the $string.  That $string must be compatible with the
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

=function type_of_node $node
Translate an XML::LibXML::Node into a packed type.
=cut

sub type_of_node($)
{   my $node = shift or return ();
    pack_type $node->namespaceURI, $node->localName;
}

=function duration2secs $duration
[1.44] Translate any format into seconds.  This is an example of
a valid duration: C<-PT1M30.5S>  Average month and year lengths
are used.  If you need more precise calculations, then use M<add_duration()>.
=cut

use constant SECOND =>   1;
use constant MINUTE =>  60     * SECOND;
use constant HOUR   =>  60     * MINUTE;
use constant DAY    =>  24     * HOUR;
use constant MONTH  =>  30.4   * DAY;
use constant YEAR   => 365.256 * DAY;

my $duration = qr/
  ^ (\-?) P (?:([0-9]+)Y)?  (?:([0-9]+)M)?  (?:([0-9]+)D)?
       (?:T (?:([0-9]+)H)?  (?:([0-9]+)M)?  (?:([0-9]+(?:\.[0-9]+)?)S)?
    )?$/x;

sub duration2secs($)
{   my $stamp = shift or return undef;

    $stamp =~ $duration
        or error __x"illegal duration format: {d}", d => $stamp;

    ($1 eq '-' ? -1 : 1)
  * ( ($2 // 0) * YEAR
    + ($3 // 0) * MONTH
    + ($4 // 0) * DAY
    + ($5 // 0) * HOUR
    + ($6 // 0) * MINUTE
    + ($7 // 0) * SECOND
    );
}

=function add_duration $duration, [$time]
[1.44] Add the $duration to the $time (defaults to 'now')  This is an
expensive operation: in many cases the M<duration2secs()> produces
useful results as well.

=example
   my $now      = time;
   my $deadline = add_duration 'P1M', $now;  # deadline in 1 month
=cut

sub add_duration($;$)
{   my $stamp = shift or return;
    my ($secs, $min, $hour, $mday, $mon, $year) = gmtime(shift // time);

    $stamp =~ $duration
        or error __x"illegal duration format: {d}", d => $stamp;

    my $sign = $1 eq '-' ? -1 : 1;
    mktime
        $secs + $sign*($7//0)
      , $min  + $sign*($6//0)
      , $hour + $sign*($5//0)
      , $mday + $sign*($4//0)
      , $mon  + $sign*($3//0)
      , $year + $sign*($2//0)
}

1;
