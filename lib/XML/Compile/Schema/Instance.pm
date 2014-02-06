
use warnings;
use strict;

package XML::Compile::Schema::Instance;

use Log::Report 'xml-compile', syntax => 'SHORT';
use XML::Compile::Schema::Specs;
use XML::Compile::Util qw/pack_type unpack_type/;

my @defkinds = qw/element attribute simpleType complexType
                  attributeGroup group/;
my %defkinds = map +($_ => 1), @defkinds;

=chapter NAME

XML::Compile::Schema::Instance - Represents one schema

=chapter SYNOPSIS

 # Used internally by XML::Compile::Schema
 my $schema = XML::Compile::Schema::Instance->new($xml);

=chapter DESCRIPTION

This module collect information from one schema, and helps to
process it.

=chapter METHODS

=section Constructors

=method new $top, %options
Get's the top of an XML::LibXML tree, which must be a schema element.
The tree is parsed: the information collected.

=option  source STRING
=default source C<undef>
An indication where this information came from.

=option  filename FILENAME
=default filename C<undef>
When the source is some file, this is its name.

=option  element_form_default 'qualified'|'unqualified'
=default element_form_default <undef>
Overrule the default as found in the schema.  Many old schemas (like
WSDL11 and SOAP11) do not specify the default in the schema but only
in the text.

=option  attribute_form_default 'qualified'|'unqualified'
=default attribute_form_default <undef>

=option  target_namespace NAMESPACE
=default target_namespace <undef>
Overrule or set the target namespace.

=cut

sub new($@)
{   my $class = shift;
    (bless {}, $class)->init( {top => @_} );
}

sub init($)
{   my ($self, $args) = @_;
    my $top = $args->{top};
    defined $top && $top->isa('XML::LibXML::Node')
        or panic "instance is based on XML node";

    $self->{filename} = $args->{filename};
    $self->{source}   = $args->{source};
    $self->{$_}       = {} for @defkinds, 'sgs', 'import';
    $self->{include}  = [];

    $self->_collectTypes($top, $args);
    $self;
}

=section Accessors

=method targetNamespace
=method schemaNamespace
=method schemaInstance
=method source
=method filename
=method schema
=cut

sub targetNamespace { shift->{tns} }
sub schemaNamespace { shift->{xsd} }
sub schemaInstance  { shift->{xsi} }
sub source          { shift->{source} }
sub filename        { shift->{filename} }
sub schema          { shift->{schema} }

=method tnses
A schema can defined more than one target namespace, where recent
schema spec changes provide a targetNamespace attribute.
=cut

sub tnses() {keys %{shift->{tnses}}}

=method sgs
Returns a HASH with the base-type as key and an ARRAY of types
which extend it.
=cut

sub sgs() { shift->{sgs} }

=method type $uri
Returns the type definition with the specified name.
=cut

sub type($) { $_[0]->{types}{$_[1]} }

=method element $uri
Returns one global element definition.
=cut

sub element($) { $_[0]->{element}{$_[1]} }

=method elements
Returns a list of all globally defined element names.

=method attributes
Returns a lost of all globally defined attribute names.

=method attributeGroups
Returns a list of all defined attribute groups.

=method groups
Returns a list of all defined model groups.

=method simpleTypes
Returns a list with all simpleType names.

=method complexTypes
Returns a list with all complexType names.

=cut

sub elements()        { keys %{shift->{element}} }
sub attributes()      { keys %{shift->{attributes}} }
sub attributeGroups() { keys %{shift->{attributeGroup}} }
sub groups()          { keys %{shift->{group}} }
sub simpleTypes()     { keys %{shift->{simpleType}} }
sub complexTypes()    { keys %{shift->{complexType}} }

=method types
Returns a list of all simpleTypes and complexTypes
=cut

sub types()           { ($_[0]->simpleTypes, $_[0]->complexTypes) }

=section Index
=cut

my %skip_toplevel = map +($_ => 1), qw/annotation notation redefine/;

sub _collectTypes($$)
{   my ($self, $schema, $args) = @_;

    $schema->localName eq 'schema'
        or panic "requires schema element";

    my $xsd = $self->{xsd} = $schema->namespaceURI || '<none>';
    if(length $xsd)
    {   my $def = $self->{def}
          = XML::Compile::Schema::Specs->predefinedSchema($xsd)
            or error __x"schema namespace `{namespace}' not (yet) supported"
                  , namespace => $xsd;

        $self->{xsi} = $def->{uri_xsi};
    }
    my $tns = $self->{tns} = $args->{target_namespace}
      || $schema->getAttribute('targetNamespace')
      || '';

    $self->{efd} = $args->{element_form_default}
      || $schema->getAttribute('elementFormDefault')
      || 'unqualified';

    $self->{afd} = $args->{attribute_form_default}
      || $schema->getAttribute('attributeFormDefault')
      || 'unqualified';

    $self->{tnses} = {}; # added when used
    $self->{types} = {};
    $self->{schema} = $schema;

  NODE:
    foreach my $node ($schema->childNodes)
    {   next unless $node->isa('XML::LibXML::Element');
        my $local = $node->localName;
        my $myns  = $node->namespaceURI || '';
        $myns eq $xsd
            or error __x"schema element `{name}' not in schema namespace {ns} but {other}"
                 , name => $local, ns => $xsd, other => ($myns || '<none>');

        next
            if $skip_toplevel{$local};

        if($local eq 'import')
        {   my $namespace = $node->getAttribute('namespace')      || $tns;
            my $location  = $node->getAttribute('schemaLocation') || '';
            push @{$self->{import}{$namespace}}, $location;
            next NODE;
        }

        if($local eq 'include')
        {   my $location  = $node->getAttribute('schemaLocation')
                or error __x"include requires schemaLocation attribute at line {linenr}"
                   , linenr => $node->line_number;

            push @{$self->{include}}, $location;
            next NODE;
        }

        unless($defkinds{$local})
        {   mistake __x"ignoring unknown definition class {class}"
              , class => $local;
            next;
        }

        my $name  = $node->getAttribute('name')
            or error __x"schema component {local} without name at line {linenr}"
                 , local => $local, linenr => $node->line_number;

        my $tns   = $node->getAttribute('targetNamespace') || $tns;
        my $type  = pack_type $tns, $name;
        $self->{tnses}{$tns}++;
        $self->{$local}{$type} = $node;

        if(my $sg = $node->getAttribute('substitutionGroup'))
        {   my ($prefix, $l) = $sg =~ m/:/ ? split(/:/, $sg, 2) : ('',$sg);
            my $base = pack_type $node->lookupNamespaceURI($prefix), $l;
            push @{$self->{sgs}{$base}}, $type;
        }
    }

    $self;
}

=method includeLocations
Returns a list of all schemaLocations which where specified with include
statements.
=cut

sub includeLocations() { @{shift->{include}} }

=method imports
Returns a list with all namespaces which need to be imported.
=cut

sub imports() { keys %{shift->{import}} }

=method importLocations $ns
Returns a list of all schemaLocations specified with the import $ns
(one of the values returned by M<imports()>).
=cut

sub importLocations($)
{   my $locs = $_[0]->{import}{$_[1]};
    $locs ? @$locs : ();
}

=method printIndex [$fh], %options
Prints an overview over the defined objects within this schema to the
selected $fh.

=option  kinds KIND|ARRAY-of-KIND
=default kinds <all>
Which KIND of definitions would you like to see.  Pick from
C<element>, C<attribute>, C<simpleType>, C<complexType>, C<attributeGroup>,
and C<group>.

=option  list_abstract BOOLEAN
=default list_abstract <true>
Show abstract elements, or skip them (because they cannot be instantiated
anyway).
=cut

sub printIndex(;$)
{   my $self   = shift;
    my $fh     = @_ % 2 ? shift : select;
    my %args   = @_;

    $fh->print("namespace: ", $self->targetNamespace, "\n");
    if(defined(my $filename = $self->filename))
    {   $fh->print(" filename: $filename\n");
    }
    elsif(defined(my $source = $self->source))
    {   $fh->print("   source: $source\n");
    }

    my @kinds
      = ! defined $args{kinds}      ? @defkinds
      : ref $args{kinds} eq 'ARRAY' ? @{$args{kinds}}
      :                               $args{kinds};

    my $list_abstract
      = exists $args{list_abstract} ? $args{list_abstract} : 1;

    foreach my $kind (@kinds)
    {   my $table = $self->{$kind};
        keys %$table or next;
        $fh->print("  definitions of ${kind}s:\n") if @kinds > 1;

        foreach (sort keys %$table)
        {   my $info = $self->find($kind, $_);
            my ($ns, $name) = unpack_type $_;
            next if $info->{abstract} && ! $list_abstract;
            my $abstract = $info->{abstract} ? ' [abstract]' : '';
            my $final    = $info->{final}    ? ' [final]' : '';
            $fh->print("    $name$abstract$final\n");
        }
    }
}

=method find $kind, $fullname
Returns the definition for the object of $kind, with $fullname.
=example of find
  my $attr = $instance->find(attribute => '{myns}my_global_attr');
=cut

sub find($$)
{    my ($self, $kind, $full) = @_;
     my $node = $self->{$kind}{$full}
         or return;

     return $node    # translation of XML node into info is cached
         if ref $node eq 'HASH';

     my %info = (type => $kind, node => $node, full => $full);
     @info{'ns', 'name'} = unpack_type $full;

#    weaken($info->{schema});
     $self->{$kind}{$full} = \%info;

     my $abstract    = $node->getAttribute('abstract') || '';
     $info{abstract} = $abstract eq 'true' || $abstract eq '1';

     my $final       = $node->getAttribute('final') || '';
     $info{final}    =  $final eq 'true' || $final eq '1';

     my $local = $node->localName;
        if($local eq 'element')  { $info{efd} = $node->getAttribute('form') }
     elsif($local eq 'attribute'){ $info{afd} = $node->getAttribute('form') }
     $info{efd} ||= $self->{efd};   # both needed for nsContext
     $info{afd} ||= $self->{afd};
     \%info;
}

1;
