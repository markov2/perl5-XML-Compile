use warnings;
use strict;

package XML::Compile::WSDL;
use base 'XML::Compile';

use Log::Report 'xml-compile', syntax => 'SHORT';
use List::Util  qw/first/;

use XML::Compile::Schema          ();
use XML::Compile::SOAP::Operation ();
use XML::Compile::Util            qw/pack_type/;

my $wsdl1 = 'http://schemas.xmlsoap.org/wsdl/';

=chapter NAME

XML::Compile::WSDL - handle SOAP messages via WSDL

=chapter SYNOPSIS

 # preparation
 my $wsdl    = XML::Compile::WSDL->new($xml);
 my $schemas = $wsdl->schemas;
 my $op      = $wsdl->operation('GetStockPrice');
 
=chapter DESCRIPTION

### This module is UNDER CONSTRUCTION.  It will only evolve with your
help.  Please contact the author when you have something to contribute.
On the moment, the development is primarily targeted to support the
CPAN6 development.  You can change that with money or time.  ###

An WSDL file defines a set of schemas and how to use the defined
types using SOAP connections.  The parsing is based on the WSDL
schema.  The WSDL definition can get constructed from multiple
XML trees, each added with M<addWSDL()>.

WSDL defines object with QNAMES: name-space qualified names.  When you
specify such a name, you have to explicitly mention the name-space IRI,
not the prefix as used in the WSDL file.  This is because prefixes may
change without notice.

The defined QNAMES are only unique within their CLASS.  Defined
CLASS types are: service, message, bindings, and portType.

=chapter METHODS

=section Constructors

=c_method new XML, OPTIONS
The XML is the WSDL file, which is anything accepted by M<dataToXML()>.
All options are also passed to create an internal M<XML::Compile::Schema>
object.  See M<XML::Compile::Schema::new()>

=option  wsdl_namespace IRI
=default wsdl_namespace C<undef>
Force to accept only WSDL descriptions which are in this namespace.  If
not specified, the name-space is enforced which is found in the first WSDL
document.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{schemas} = XML::Compile::Schema->new(undef, %$args);
    $self->{index}   = {};
    $self->{wsdl_ns} = $args->{wsdl_namespace};

    $self->addWSDL($args->{top});
    $self;
}

=section Accessors

=method schemas
Returns the M<XML::Compile::Schema> object which collects all type
information.
=cut

sub schemas() { shift->{schemas} }

=method wsdlNamespace [NAMESPACE]
Returns (optionally after setting) the namespace used by the WSDL
specification.  This is the namespace in which the C<definition>
document root element is defined.
=cut

sub wsdlNamespace(;$)
{   my $self = shift;
    @_ ? ($self->{wsdl_ns} = shift) : $self->{wsdl_ns};
}

=section Extension

=method addWSDL XMLDATA
Some XMLDATA, accepted by M<dataToXML()> is provided, which should represent
the top-level of a (partial) WSDL document.  The specification can be
spread over multiple files, which each have a C<definition> root element.
=cut

sub addWSDL($)
{   my ($self, $data) = @_;
    defined $data or return;
    my $node = $self->dataToXML($data)
        or return $self;

    $node    = $node->documentElement
        if $node->isa('XML::LibXML::Document');

    $node->localName eq 'definitions'
        or error __x"root element for WSDL is not 'definitions'";

    my $wsdlns  = $node->namespaceURI;
    my $corens  = $self->wsdlNamespace || $self->wsdlNamespace($wsdlns);

    $corens eq $wsdlns
        or error __x"wsdl in namespace {wsdlns}, where already using {ns}"
               , wsdlns => $wsdlns, ns => $corens;

    my $schemas = $self->schemas;
    $schemas->importDefinitions($wsdlns);  # to understand WSDL

    $wsdlns eq $wsdl1
        or error __x"don't known how to handle {wsdlns} WSDL files"
               , wsdlns => $wsdlns;

    my %hook_kind =
     ( type         => pack_type($wsdlns, 'tOperation')
     , after        => 'ELEMENT_ORDER'
     );

    my $reader  = $schemas->compile        # to parse the WSDL
     ( READER       => pack_type($wsdlns, 'definitions')
     , anyElement   => 'TAKE_ALL'
     , anyAttribute => 'TAKE_ALL'
     , hook         => \%hook_kind
     );

    my $spec = $reader->($node);
    my $tns  = $spec->{targetNamespace}
        or error __x"WSDL sets no targetNamespace";

    # there can be multiple <types>, which each a list of <schema>'s
    foreach my $type ( @{$spec->{types} || []} )
    {   foreach my $k (keys %$type)
        {   next unless $k =~ m/^\{[^}]*\}schema$/;
            $schemas->importDefinitions(@{$type->{$k}});
        }
    }

    # WSDL 1.1 par 2.1.1 says: WSDL defs all in own name-space
    my $index = $self->{index};
    my $toplevels = $spec->{import} || [];  # silly WSDL structure
    foreach my $toplevel (@$toplevels)
    {   my $which = (keys %$toplevel)[0];   # only one
        next unless $which =~ m/^(?:service|message|binding|portType)$/;
        my $def   = $toplevel->{$which};
        $index->{$which}{pack_type $tns, $def->{name}} = $def;
    }

   foreach my $service ( @{$spec->{service} || []} )
   {   foreach my $port ( @{$service->{port} || []} )
       {   $index->{port}{pack_type $tns, $port->{name}} = $port;
       }
   }

   $self;
}

=method importDefinitions XMLDATA, OPTIONS
Add schema information to the WSDL interface knowledge.  This should
not be needed, because WSDL definitions must be self-contained.
=cut

sub importDefinitions($@) { shift->schemas->importDefinitions(@_) }

=method namesFor CLASS
Returns the list of names available for a certain definition
CLASS in the WSDL.
=cut

sub namesFor($)
{   my ($self, $class) = @_;
    keys %{shift->index($class) || {}};
}

=method operation [NAME], OPTIONS
Collect all information for a certain operation.  Returned is an
M<XML::Compile::SOAP::Operation> object.

An operation is defined by a service name, a port, some bindings,
and an operation name, which can be specified explicitly or sometimes
left-out.

When not specified explicitly via OPTIONS, each of the CLASSes are only
permitted to have exactly one definition.  Otherwise, you must make a
choice explicitly.  There is a very good reason to be not too flexible
in this area: developers need to be aware when there are choices, where
some flexibility is required.

=requires service QNAME
Optional when exactly one service is defined.

=requires port NAME
Optional when the selected service has only one port.

=requires operation NAME
Optional when the parameter list starts with a NAME (which is an
alternative for this option).  Also optional when there is only
one operation defined within the portType.

=cut

sub operation(@)
{   my $self = shift;
    my $name = @_ % 2 ? shift : undef;
    my %args = @_;

    my $service   = $self->find(service => delete $args{service});

    my $port;
    my @ports     = @{$service->{port} || []};
    my @portnames = map {$_->{name}} @ports;
    if(my $portname = delete $args{port})
    {   $port = first {$_->{name} eq $portname} @ports;
        error __x"cannot find port `{portname}', pick from {ports}"
            , portname => $portname, ports => join("\n    ", '', @portnames)
           unless $port;
    }
    elsif(@ports==1)
    {   $port = shift @ports;
    }
    else
    {   error __x"specify port explicitly, pick from {portnames}"
            , portnames => join("\n    ", '', @portnames);
    }

    my $bindname  = $port->{binding}
        or error __x"no binding defined in port '{name}'"
               , name => $port->{name};

    my $binding   = $self->find(binding => $bindname);

    my $type      = $binding->{type}
        or error __x"no type defined with binding `{name}'"
               , name => $bindname;

    my $portType  = $self->find(portType => $type);
    my $types     = $portType->{operation}
        or error __x"no operations defined for portType `{name}'"
               , name => $type;

    my @port_ops  = map {$_->{name}} @$types;

    $name       ||= delete $args{operation};
    my $port_op;
    if(defined $name)
    {   $port_op = first {$_->{name} eq $name} @$types;
        error __x"no operation `{operation}' for portType {porttype}, pick from{ops}"
            , operation => $name
            , porttype => $type
            , ops => join("\n    ", '', @port_ops)
            unless $port_op;
    }
    elsif(@port_ops==1)
    {   $port_op = shift @port_ops;
    }
    else
    {   error __x"multiple operations in portType `{porttype}', pick from {ops}"
            , porttype => $type
            , ops => join("\n    ", '', @port_ops)
    }

    my @bindops = @{$binding->{operation} || []};
    my $bind_op = first {$_->{name} eq $name} @bindops;

    my $operation = XML::Compile::SOAP::Operation->new
     ( service        => $service
     , port           => $port
     , binding        => $binding
     , portType       => $portType
     , schemas        => $self->schemas
     , portOperation  => $port_op
     , bindOperation  => $bind_op
     );

    $operation;
}

=method prepare [NAME], OPTIONS
Creates temporarily an M<XML::Compile::SOAP::Operation> with M<operation()>,
and then calls C<prepare()> on that; a usual combination.
As OPTIONS, combine all possibilities for M<operation()> and
M<XML::Compile::SOAP::Operation::prepare()>.
=cut

sub prepare(@)
{   my $self = shift;
    unshift @_, 'operation' if @_ % 2;
    my $op   = $self->operation(@_) or return ();
    $op->prepare(@_);
}

=section Inspection

All of the following methods are usually NOT meant for end-users. End-users
should stick to the M<operation()> and M<call()> methods.

=method index [CLASS, [QNAME]]
With a CLASS and QNAME, it returns one WSDL definition HASH or undef.
Returns the index for the CLASS group of names as HASH.  When no CLASS is
specified, a HASH of HASHes is returned with the CLASSes on the top-level.
=cut

sub index(;$$)
{   my $index = shift->{index};
    @_ or return $index;

    my $class = $index->{ (shift) }
       or return ();

    @_ ? $class->{ (shift) } : $class;
}

=method find CLASS, [QNAME]
With a QNAME, the HASH which contains the parsed XML information
from the WSDL template for that CLASS-NAME combination is returned.
When the NAME is not found, an error is produced.

Without QNAME in SCALAR context, there may only be one such name
defined otherwise an error is produced.  In LIST context, all definitions
in CLASS are returned.
=cut

sub find($;$)
{   my ($self, $class, $name) = @_;
    my $group = $self->index($class)
        or error __x"no definitions for `{class}' found", class => $class;

    if(defined $name)
    {   return $group->{$name} if exists $group->{$name};
        error __x"no definition for `{name}' as {class}, pick from:{groups}"
            , name => $name, class => $class
            , groups => join("\n    ", '', sort keys %$group);
    }

    return values %$group
        if wantarray;

    return (values %$group)[0]
        if keys %$group==1;

    error __x"explicit selection required: pick one {class} from {groups}"
        , class => $class, groups => join("\n    ", '', sort keys %$group);
}

1;
