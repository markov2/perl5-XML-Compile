
use warnings;
use strict;

package XML::Compile::Schema::NameSpaces;

use Log::Report 'xml-compile', syntax => 'SHORT';

use XML::Compile::Util qw/pack_type unpack_type pack_id unpack_id/;

=chapter NAME

XML::Compile::Schema::NameSpaces - Connect name-spaces from schemas

=chapter SYNOPSIS
 # Used internally by XML::Compile::Schema
 my $nss = XML::Compile::Schema::NameSpaces->new;
 $nss->add($schema);

=chapter DESCRIPTION

This module keeps overview on a set of namespaces, collected from various
schema files.  Per XML namespace, it will collect a list of fragments
which contain definitions for the namespace, each fragment comes from a
different source.  These fragments are searched in reverse order when
an element or type is looked up (the last definitions overrule the
older definitions).

=chapter METHODS

=section Constructors

=method new OPTIONS
=cut

sub new($@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{tns} = {};
    $self;
}

=section Accessors

=method list
Returns the list of name-space URIs defined.
=cut

sub list() { keys %{shift->{tns}} }

=method namespace URI
Returns a list of M<XML::Compile::Schema::Instance> objects which have
the URI as target namespace.
=cut

sub namespace($)
{   my $nss  = $_[0]->{tns}{$_[1]};
    $nss ? @$nss : ();
}

=method add SCHEMA, [SCHEMAS]
Add M<XML::Compile::Schema::Instance> objects to the internal
knowledge of this object.
=cut

sub add(@)
{   my $self = shift;
    foreach my $schema (@_)
    {   my $tns = $schema->targetNamespace;
        unshift @{$self->{tns}{$tns}}, $schema;
    }
    @_;
}

=method schemas URI
We need the name-space; when it is lacking then import must help, but that
must be called explictly.
=cut

sub schemas($) { $_[0]->namespace($_[1]) }

=method allSchemas
Returns a list of all known schema instances.
=cut

sub allSchemas()
{   my $self = shift;
    map {$self->schemas($_)} $self->list;
}

=method find KIND, ADDRESS|(URI,NAME)
Lookup the definition for the specified KIND of definition: the name
of a global element, global attribute, attributeGroup or model group.
The ADDRESS is constructed as C< {uri}name > or as seperate URI and NAME.
=cut

sub find($$;$)
{   my ($self, $kind) = (shift, shift);
    my ($ns, $name) = @_==1 ? (unpack_type $_[0]) : @_;
    my $label = pack_type $ns, $name; # re-pack unpacked for consistency

    defined $ns or return undef;

    foreach my $schema ($self->schemas($ns))
    {   my $def = $schema->find($kind, $label);
        return $def if defined $def;
    }

    undef;
}

=method findSgMembers ADDRESS|(URI,NAME)
Lookup the substitutionGroup alternatives for a specific element,
which is an ADDRESS of form C< {uri}name > or as seperate URI and NAME.
Returned is a list of parse nodes (HASHes)
=cut

sub findSgMembers($;$)
{   my $self = shift;
    my ($label, $ns, $name)
      = @_==1 ? ($_[0], unpack_type $_[0]) : (pack_type($_[0], $_[1]), @_);
    defined $ns or return undef;

    map {$_->substitutionGroupMembers($label)}
        $self->allSchemas;
}

=method findID ADDRESS|(URI,ID)
Lookup the definition for the specified id, which is constructed as
C< uri#id > or as seperate URI and ID.
=cut

sub findID($;$)
{   my $self = shift;
    my ($label, $ns, $id)
      = @_==1 ? ($_[0], unpack_id $_[0]) : (pack_id($_[0], $_[1]), @_);
    defined $ns or return undef;

    foreach my $schema ($self->schemas($ns))
    {   my $def = $schema->id($label);
        return $def if defined $def;
    }

    undef;
}

=method printIndex [FILEHANDLE], OPTIONS
Show all definitions from all namespaces, for debugging purposes, by
default the selected.  Additional OPTIONS are passed to 
M<XML::Compile::Schema::Instance::printIndex()>.

=option  namespace URI|ARRAY-of-URI
=default namespace <ALL>
Show only information about the indicate namespaces.

=examples
 my $nss = $schema->namespaces;
 $nss->printIndex(\*MYFILE);
 $nss->printIndex(namespace => "my namespace");

 # types defined in the wsdl schema
 use XML::Compile::SOAP::Util qw/WSDL11/;
 $nss->printIndex(\*STDERR, namespace => WSDL11);
=cut

sub printIndex(@)
{   my $self = shift;
    my $fh   = @_ % 2 ? shift : select;
    my %opts = @_;

    my $nss  = delete $opts{namespace} || [$self->list];
    foreach my $nsuri (ref $nss eq 'ARRAY' ? @$nss : $nss)
    {   $_->printIndex($fh, %opts) for $self->namespace($nsuri);
    }
}

1;
