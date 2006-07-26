
use warnings;
use strict;

package XML::Compile;

use XML::LibXML;
use Carp;

=chapter NAME

XML::Compile - Compilation based XML processing

=chapter SYNOPSIS

 # See XML::Compile::Schema

=chapter DESCRIPTION

Many applications which process XML do that based on a nice specification,
expressed in an XML Schema.  XML::Compile reads and writes XML
data with the help of schema's.  On the Perl side, it uses a tree of
nested hashes with the same structure.

Where other Perl modules, like M<SOAP::WSDL> help you using these schema's
with a lot of XPath searches, this module takes a different approach:
in stead of a run-time processing of the specification, it will first
compile the expected structure into real Perl, and then use that to
process the data.

There are many perl modules which do the same: translate between XML
and hashes.  However, there are a few serious differences:  because
the schema is used here, we make sure we only handle correct data.
Furthermore, data-types like Integer do accept huge values as the
specification prescribes.  Also more complex data-types like C<list>
and C<union> are correctly supported.

=chapter METHODS

=section Constructors

=method new TOP, OPTIONS

The TOP is a M<XML::LibXML::Document> (a direct result from parsing
activities) or a M<XML::LibXML::Node> (a sub-tree).  In any case,
a product of the XML::LibXML module (based on libxml2).

If you have compiled/collected all the information you need,
then simply terminate the compiler object: that will clean-up
the XML::LibXML objects.

=cut

sub new(@)
{   my ($class, $top) = (shift, shift);
    (bless {}, $class)->init( {top => $top, @_} );
}

sub init($)
{   my ($self, $args) = @_;

    my $top = $args->{top}
       or croak "ERROR: XML definition not specified";

    $self->{XC_top}
      = ref $top && $top->isa('XML::LibXML::Node') ? $top
      : $self->parse(\$top);

    $self;
}

# Extend this later with other input mechamisms.
sub parse($)
{   my ($thing, $data) = @_;
    my $xml = XML::LibXML->new->parse_string($$data);
    defined $xml ? $xml->documentElement : undef;
}

=section Accessors

=method top
Returns the XML::LibXML object tree which needs to be compiled.

=cut

sub top() {shift->{XC_top}}

=section Filters

=method walkTree NODE, CODE
Walks the whole tree from NODE downwards, calling the CODE reference
for each NODE found.  When the routine returns false, the child
nodes will be skipped.

=cut

sub walkTree($$)
{   my ($self, $node, $code) = @_;
    if($code->($node))
    {   $self->walkTree($_, $code)
            foreach $node->getChildNodes;
    }
}

=section Compilers

=cut

1;
