
use warnings;
use strict;

package XML::Compile::Schema::Instance;

use Log::Report 'xml-compile', syntax => 'SHORT';
use XML::Compile::Schema::Specs;
use XML::Compile::Util qw/pack_type/;

use Scalar::Util       qw/weaken/;

my @defkinds = qw/element attribute simpleType complexType
                  attributeGroup group/;
my %defkinds = map { ($_ => 1) } @defkinds;

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

=method new TOP, OPTIONS
Get's the top of an XML::LibXML tree, which must be a schema element.
The tree is parsed: the information collected.

=option  source STRING
=default source C<undef>
An indication where this information came from.

=option  filename FILENAME
=default filename C<undef>
When the source is some file, this is its name.
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

    $self->_collectTypes($top);
    $self;
}

=section Accessors

=method targetNamespace
=method schemaNamespace
=method schemaInstance
=method source
=method filename
=cut

sub targetNamespace { shift->{tns} }
sub schemaNamespace { shift->{xsd} }
sub schemaInstance  { shift->{xsi} }
sub source          { shift->{source} }
sub filename        { shift->{filename} }

=method type URI
Returns the type definition with the specified name.
=cut

sub type($) { $_[0]->{types}{$_[1]} }

=method element URI
Returns one global element definition.
=cut

sub element($) { $_[0]->{elements}{$_[1]} }

=method id STRING
Returns one global element, selected by ID.
=cut

sub id($) { $_[0]->{ids}{$_[1]} }

=method ids
Returns a list of all found ids.

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

sub ids()             { keys %{shift->{ids}} }
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

=method substitutionGroups
Returns a list of all named substitutionGroups.
=cut

sub substitutionGroups() { keys %{shift->{sgs}} }

=method substitutionGroupMembers ELEMENT
The expanded ELEMENT name is used to collect a set of alternatives which
are in this substitutionGroup (super-class like alternatives). 
=cut

sub substitutionGroupMembers($)
{   my $sgs = shift->{sgs}      or return ();
    my $sg  = $sgs->{ (shift) } or return ();
    @$sg;
}

=section Index
=cut

my %skip_toplevel = map { ($_ => 1) } qw/annotation notation redefine/;

sub _collectTypes($)
{   my ($self, $schema) = @_;

    $schema->localName eq 'schema'
        or panic "requires schema element";

    my $xsd = $self->{xsd} = $schema->namespaceURI || '';
    if(length $xsd)
    {   my $def = $self->{def}
          = XML::Compile::Schema::Specs->predefinedSchema($xsd)
            or error __x"schema namespace `{namespace}' not (yet) supported"
                  , namespace => $xsd;

        $self->{xsi} = $def->{uri_xsi};
    }
    my $tns = $self->{tns} = $schema->getAttribute('targetNamespace') || '';

    my $efd = $self->{efd}
      = $schema->getAttribute('elementFormDefault')   || 'unqualified';

    my $afd = $self->{afd}
      = $schema->getAttribute('attributeFormDefault') || 'unqualified';

    $self->{types} = {};
    $self->{ids}   = {};

  NODE:
    foreach my $node ($schema->childNodes)
    {   next unless $node->isa('XML::LibXML::Element');
        my $local = $node->localName;

        next if $skip_toplevel{$local};

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

        my $tag   = $node->getAttribute('name');
        my $ref;
        unless(defined $tag && length $tag)
        {   $ref = $tag = $node->getAttribute('ref')
               or error __x"schema component {local} without name or ref at line {linenr}"
                    , local => $local, linenr => $node->line_number;

            $tag =~ s/.*?\://;
        }

        my $nns = $node->namespaceURI || '';
        error __x"schema component `{name}' must be in namespace {ns}"
          , name => $tag, ns => $xsd
              if $xsd && $nns ne $xsd;

        my $id    = $schema->getAttribute('id');

        my ($prefix, $name)
         = index($tag, ':') >= 0 ? split(/\:/,$tag,2) : ('', $tag);

        # prefix existence enforced by xml parser
        my $ns    = length $prefix ? $node->lookupNamespaceURI($prefix) : $tns;
        my $label = pack_type $ns, $name;

        my $sg;
        if(my $subst = $node->getAttribute('substitutionGroup'))
        {    my ($sgpref, $sgname)
              = index($subst, ':') >= 0 ? split(/\:/,$subst,2) : ('', $subst);
             my $sgns = length $sgpref ? $node->lookupNamespaceURI($sgpref) : $tns;
             defined $sgns
                or error __x"no namespace for {what} in substitutionGroup {group}"
                       , what => (length $sgpref ? "'$sgpref'" : 'target')
                       , group => $tag;
             $sg = pack_type $sgns, $sgname;
        }

        my $abstract = $node->getAttribute('abstract') || 'false';

        unless($defkinds{$local})
        {   mistake __x"ignoring unknown definition-type {local}", type => $local;
            next;
        }

        my $info  = $self->{$local}{$label} =
          { type => $local, id => $id,   node => $node
          , full => pack_type($ns, $name)
          , ns   => $ns,  name => $name, prefix => $prefix
          , afd  => $afd, efd  => $efd,  schema => $self
          , ref  => $ref, sg   => $sg
          , abstract => ($abstract eq 'true' || $abstract eq '1')
          };
        weaken($info->{schema});

        # Id's can also be set on nested items, but these are ignored
        # for now...
        $self->{ids}{"$ns#$id"} = $info
           if defined $id;

        push @{$self->{sgs}{$sg}}, $info
           if defined $sg;
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

=method importLocations NAMESPACE
Returns a list of all schemaLocations specified with the import NAMESPACE
(one of the values returned by M<imports()>).
=cut

sub importLocations($)
{   my $locs = $_[0]->{import}{$_[1]};
    $locs ? @$locs : ();
}

=method printIndex [FILEHANDLE], OPTIONS
Prints an overview over the defined objects within this schema to the
selected FILEHANDLE.

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

    my $list_abstract = exists $args{list_abstract} ? $args{list_abstract} : 1;

    foreach my $kind (@kinds)
    {   my $table = $self->{$kind};
        keys %$table or next;
        $fh->print("  definitions of ${kind}s:\n") if @kinds > 1;
        foreach (sort {$a->{name} cmp $b->{name}} values %$table)
        {   next if $_->{abstract} && ! $list_abstract;
            my $abstract = $_->{abstract} ? ' [abstract]' : '';
            $fh->print("    $_->{name}$abstract\n");
        }
    }
}

=method find KIND, LOCALNAME
Returns the definition for the object of KIND, with LOCALNAME.
=example of find
 my $attr = $instance->find(attribute => 'myns#my_global_attr');
=cut

sub find($$) { $_[0]->{$_[1]}{$_[2]} }

1;
