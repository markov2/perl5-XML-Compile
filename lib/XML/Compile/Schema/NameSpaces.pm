
use warnings;
use strict;

package XML::Compile::Schema::NameSpaces;

use Log::Report 'xml-compile', syntax => 'SHORT';

use XML::Compile::Util
  qw/pack_type unpack_type pack_id unpack_id SCHEMA2001/;

use XML::Compile::Schema::BuiltInTypes qw/%builtin_types/;

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

=method new %options
=cut

sub new($@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{tns} = {};
    $self->{sgs} = {};
    $self->{use} = [];
    $self;
}

=section Accessors

=method list
Returns the list of name-space URIs defined.
=cut

sub list() { keys %{shift->{tns}} }

=method namespace $uri
Returns a list of M<XML::Compile::Schema::Instance> objects which have
the $uri as target namespace.
=cut

sub namespace($)
{   my $nss  = $_[0]->{tns}{$_[1]};
    $nss ? @$nss : ();
}

=method add $schema, [$schemas]
Add M<XML::Compile::Schema::Instance> objects to the internal
knowledge of this object.
=cut

sub add(@)
{   my $self = shift;
    foreach my $instance (@_)
    {   # With the "new" targetNamespace attribute on any attribute, one
        # schema may have contribute to multiple tns's.  Also, I have
        # encounted schema's without elements, but <import>
        my @tnses = $instance->tnses;
        @tnses or @tnses = '(none)';

        # newest definitions overrule earlier.
        unshift @{$self->{tns}{$_}}, $instance
            for @tnses;

        # inventory where to find definitions which belong to some
        # substitutionGroup.
        while(my($base,$ext) = each %{$instance->sgs})
        {   $self->{sgs}{$base}{$_} ||= $instance for @$ext;
        }
    }
    @_;
}

=method use $object
Use any other M<XML::Compile::Schema> extension as fallback, if the
M<find()> does not succeed for the current object.  Searches for
definitions do not recurse into the used object.

Returns the list of all used OBJECTS.
This method implements M<XML::Compile::Schema::useSchema()>.

=cut

sub use($)
{   my $self = shift;
    push @{$self->{use}}, @_;
    @{$self->{use}};
}

=method schemas $uri
We need the name-space; when it is lacking then import must help, but that
must be called explicitly.
=cut

sub schemas($) { $_[0]->namespace($_[1]) }

=method allSchemas
Returns a list of all known schema instances.
=cut

sub allSchemas()
{   my $self = shift;
    map {$self->schemas($_)} $self->list;
}

=method find $kind, $address|<$uri,$name>, %options
Lookup the definition for the specified $kind of definition: the name
of a global element, global attribute, attributeGroup or model group.
The $address is constructed as C< {uri}name > or as separate $uri and $name.

=option  include_used BOOLEAN
=default include_used <true>
=cut

sub find($$;$)
{   my ($self, $kind) = (shift, shift);
    my ($ns, $name) = (@_%2==1) ? (unpack_type shift) : (shift, shift);
    my %opts = @_;

    defined $ns or return undef;
    my $label = pack_type $ns, $name; # re-pack unpacked for consistency

    foreach my $schema ($self->schemas($ns))
    {   my $def = $schema->find($kind, $label);
        return $def if defined $def;
    }

    my $used = exists $opts{include_used} ? $opts{include_used} : 1;
    $used or return undef;

    foreach my $use ( @{$self->{use}} )
    {   my $def = $use->namespaces->find($kind, $label, include_used => 0);
        return $def if defined $def;
    }

    undef;
}

=method doesExtend $exttype, $basetype
Returns true when $exttype extends $basetype.
=cut

sub doesExtend($$)
{   my ($self, $ext, $base) = @_;
    return 1 if $ext eq $base;
    return 0 if $ext =~ m/^unnamed /;

    my ($node, $super, $subnode);
    if(my $st = $self->find(simpleType => $ext))
    {   # pure simple type
        $node = $st->{node};
        if(($subnode) = $node->getChildrenByLocalName('restriction'))
        {   $super = $subnode->getAttribute('base');
        }
        # list an union currently ignored
    }
    elsif(my $ct = $self->find(complexType => $ext))
    {   $node = $ct->{node};
        # getChildrenByLocalName returns list, we know size one
        if(my($sc) = $node->getChildrenByLocalName('simpleContent'))
        {   # tagged
            if(($subnode) = $sc->getChildrenByLocalName('extension'))
            {   $super = $subnode->getAttribute('base');
            }
            elsif(($subnode) = $sc->getChildrenByLocalName('restriction'))
            {   $super = $subnode->getAttribute('base');
            }
        }
        elsif(my($cc) = $node->getChildrenByLocalName('complexContent'))
        {   # real complex
            if(($subnode) = $cc->getChildrenByLocalName('extension'))
            {   $super = $subnode->getAttribute('base');
            }
            elsif(($subnode) = $cc->getChildrenByLocalName('restriction'))
            {   $super = $subnode->getAttribute('base');
            }
        }
    }
    else
    {   # build-in
        my ($ns, $local) = unpack_type $ext;
        $ns eq SCHEMA2001 && $builtin_types{$local}
            or error __x"cannot find {type} as simpleType or complexType"
                 , type => $ext;
        my ($bns, $blocal) = unpack_type $base;
        $ns eq $bns
            or return 0;

        while(my $e = $builtin_types{$local}{extends})
        {   return 1 if $e eq $blocal;
            $local = $e;
        }
    }

    $super
        or return 0;

    my ($prefix, $local) = $super =~ m/:/ ? split(/:/,$super,2) : ('',$super);
    my $supertype = pack_type $subnode->lookupNamespaceURI($prefix), $local;

    $base eq $supertype ? 1 : $self->doesExtend($supertype, $base);
}

=method findTypeExtensions $type
This method can be quite expensive, with large and nested schemas.
=cut

sub findTypeExtensions($)
{   my ($self, $type) = @_;

    my %ext;
    if($self->find(simpleType => $type))
    {   $self->doesExtend($_, $type) && $ext{$_}++
            for map $_->simpleTypes, $self->allSchemas;
    }
    elsif($self->find(complexType => $type))
    {   $self->doesExtend($_, $type) && $ext{$_}++
            for map $_->complexTypes, $self->allSchemas;
    }
    else
    {   error __x"cannot find base-type {type} for extensions", type => $type;
    }
    sort keys %ext;
}

sub autoexpand_xsi_type($)
{   my ($self, $type) = @_;
    my @ext = $self->findTypeExtensions($type);
    trace "discovered xsi:type choices for $type:\n  ". join("\n  ", @ext);
    \@ext;
}

=method findSgMembers $class, $type
Lookup the substitutionGroup alternatives for a specific element, which
is an $type (element full name) of form C< {uri}name > or as separate
URI and NAME.  Returned is an ARRAY of HASHes, each describing one type
(as returned by M<find()>)
=cut

sub findSgMembers($$)
{   my ($self, $class, $base) = @_;
    my $s = $self->{sgs}{$base}
        or return;

    my @sgs;
    while(my($ext, $instance) = each %$s)
    {   push @sgs, $instance->find($class => $ext)
          , $self->findSgMembers($class, $ext);
    }
    @sgs;
}

=method findID $address|<$uri,$id>
Lookup the definition for the specified id, which is constructed as
C< uri#id > or as separate $uri and $id.
=cut

sub findID($;$)
{   my $self = shift;
    my ($label, $ns, $id)
      = @_==1 ? ($_[0], unpack_id $_[0]) : (pack_id($_[0], $_[1]), @_);
    defined $ns or return undef;

    my $xpc = XML::LibXML::XPathContext->new;
    $xpc->registerNs(a => $ns);

    my @nodes;
    foreach my $fragment ($self->schemas($ns))
    {   @nodes = $xpc->findnodes("/*/a:*#$id", $fragment->schema)
	    or next;

	return $nodes[0]
	    if @nodes==1;

        error "multiple elements with the same id {id} in {source}"
	  , id => $label
	  , source => ($fragment->filename || $fragment->source);
    }

    undef;
}

=method printIndex [$fh], %options
Show all definitions from all namespaces, for debugging purposes, by
default the selected.  Additional %options are passed to 
M<XML::Compile::Schema::Instance::printIndex()>.

=option  namespace URI|ARRAY-of-URI
=default namespace <ALL>
Show only information about the indicate namespaces.

=option  include_used BOOLEAN
=default include_used <true>
Show also the index from all the schema objects which are defined
to be usable as well; which were included via M<use()>.

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

    my $show_used = exists $opts{include_used} ? $opts{include_used} : 1;
    foreach my $use ($self->use)
    {   $use->printIndex(%opts, include_used => 0);
    }

    $self;
}

=method importIndex %options
[1.41] Returns a HASH with namespaces which are declared in all currently
known schema's, pointing to ARRAYs of the locations where the import should
come from.

In reality, the locations mentioned are often wrong. But when you think
you want to load all schema's dynamically at start-up (no, you do not
want it but it is a SOAP paradigma) then you get that info easily with
this method.
=cut

sub importIndex(%)
{   my ($self, %args) = @_;
    my %import;
    foreach my $fragment (map $self->schemas($_), $self->list)
    {   foreach my $import ($fragment->imports)
        {   $import{$import}{$_}++ for $fragment->importLocations($import);
        }
    }
    foreach my $ns (keys %import)
    {   $import{$ns} = [ grep length, keys %{$import{$ns}} ];
    }
    \%import;
}

1;
