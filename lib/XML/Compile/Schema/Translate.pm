use warnings;
use strict;

package XML::Compile::Schema::Translate;

# Errors are either in class 'usage': called with request
#                         or 'schema': syntax error in schema

use Log::Report 'xml-compile', syntax => 'SHORT';
use List::Util  'first';

use XML::Compile::Schema::Specs;
use XML::Compile::Schema::BuiltInFacets;
use XML::Compile::Schema::BuiltInTypes qw/%builtin_types/;
use XML::Compile::Util                 qw/pack_type unpack_type type_of_node/;
use XML::Compile::Iterator             ();

# Elements from the schema to ignore: remember, we are collecting data
# from the schema, but only use selective items to produce processors.
# All the sub-elements of these will be ignored automatically
# Don't known whether we ever need the notation... maybe
my $assertions      = qr/assert|report/;
my $id_constraints  = qr/unique|key|keyref/;
my $ignore_elements = qr/^(?:notation|annotation|$id_constraints|$assertions)$/;

my $particle_blocks = qr/^(?:sequence|choice|all|group)$/;
my $attribute_defs  = qr/^(?:attribute|attributeGroup|anyAttribute)$/;

=chapter NAME

XML::Compile::Schema::Translate - create an XML data parser

=chapter SYNOPSIS

 # for internal use only
 my $code = XML::Compile::Schema::Translate->compileTree(...);

=chapter DESCRIPTION

This module converts a schema type definition into a code
reference which can be used to interpret a schema.  The sole public
function in this package is M<compileTree()>, and is called by
M<XML::Compile::Schema::compile()>, which does a lot of set-ups.
Please do not try to use this package directly!

The code in this package interprets schemas; it understands, for
instance, how complexType definitions work.  Then, when the
schema syntax is decoded, it will knot the pieces together into
one CODE reference which can be used in the main user program.

=section Unsupported features

This implementation is work in progress, but by far most structures in
W3C schemas are implemented (and tested!).

Missing are
 schema noNamespaceSchemaLocation
 any ##local
 anyAttribute ##local

Some things do not work in schemas anyway: C<import>, C<include>.  They
only work if everyone always has a working connection to internet.  You
have to require them manually.  Include also does work, because it does not
use namespaces.  (see M<XML::Compile::Schema::importDefinitions()>)

Ignored, because not for our purpose is the search optimization
information: C<key, unique, keyref, selector, field>, and de schema
documentation: C<notation, annotation>.  Compile the schema schema itself
to interpret the message if you need them.

A few nuts are still to crack:
 any* processContents always interpreted as lax
 schema version
 openContent
 attribute limitiations (facets) on dates
 full understanding of patterns (now limited)
 final is not protected
 QName writer namespace to prefix translation

Of course, the latter list is all fixed in next release ;-)
See chapter L</DETAILS> for more on how the tune the translator.

=chapter METHODS

=c_method compileTree ELEMENT|ATTRIBUTE|TYPE, OPTIONS
Do not call this function yourself, but use
M<XML::Compile::Schema::compile()> (or wrappers around that).

This function returns a CODE reference, which can translate
between Perl datastructures and XML, based on a schema.  Before
this method is called is the schema already translated into
a table of types.

=requires nss L<XML::Compile::Schema::NameSpaces>
=requires bricks CLASS
=requires hooks ARRAY
=requires action 'READER'|'WRITER'

=cut

sub compileTree($@)
{   my ($class, $item, %args) = @_;

    my $path   = $item;
    my $self   = bless \%args, $class;

    ref $item
        and panic "expecting an item as point to start at $path";

    $self->{bricks}
        or panic "no bricks to build";

    $self->{nss}
        or panic "no namespace tables";

    $self->{hooks}
        or panic "no hooks list defined";

    $self->{action}
        or panic "action type is needed";

    if(my $def = $self->namespaces->findID($item))
    {   my $node = $def->{node};
        my $name = $node->localName;
        $item    = $def->{full};
    }

    my $produce = $self->topLevel($path, $item);

      $self->{include_namespaces}
    ? $self->make(wrapper_ns => $path, $produce, $self->{output_namespaces})
    : $produce;
}

sub assertType($$$$)
{   my ($self, $where, $field, $type, $value) = @_;
    my $checker = $builtin_types{$type}{check}
        or die "PANIC: invalid assert type $type";

    return if $checker->($value);

    error __x"field {field} contains '{value}' which is not a valid {type} at {where}"
        , field => $field, value => $value, type => $type, where => $where
        , class => 'usage';

}

sub extendAttrs($@)
{   my ($self, $in, %add) = @_;

    # new attrs overrule
    unshift @{$in->{attrs}},     @{$add{attrs}}     if $add{attrs};
    unshift @{$in->{attrs_any}}, @{$add{attrs_any}} if $add{attrs_any};
    $in;
}

sub isTrue($) { $_[1] eq '1' || $_[1] eq 'true' }

sub namespaces() { $_[0]->{nss} }

sub make($@)
{   my ($self, $component, $where, @args) = @_;
    no strict 'refs';
    "$self->{bricks}::$component"->($where, $self, @args);
}

sub topLevel($$)
{   my ($self, $path, $fullname) = @_;

    # built-in types have to be handled differently.
    my $internal = XML::Compile::Schema::Specs->builtInType
      (undef, $fullname, sloppy_integers => $self->{sloppy_integers});

    if($internal)
    {   my $builtin = $self->make(builtin => $fullname, undef
            , $fullname, $internal, $self->{check_values});
        my $builder = $self->{action} eq 'WRITER'
          ? sub { $_[0]->createTextNode($builtin->(@_)) }
          : $builtin;
        return $self->make('element_wrapper', $path, $builder);
    }

    my $nss  = $self->namespaces;
    my $top  = $nss->find(element   => $fullname)
            || $nss->find(attribute => $fullname)
       or error __x(( $fullname eq $path
                    ? N__"cannot find element or attribute `{name}'"
                    : N__"cannot find element or attribute `{name}' at {where}"
                    ), name => $fullname, where => $path, class => 'usage');

    my $node = $top->{node};

    my $elems_qual = $top->{efd} eq 'qualified';
    if(exists $self->{elements_qualified})
    {   my $qual = $self->{elements_qualified} || 0;

           if($qual eq 'ALL')  { $elems_qual = 1 }
        elsif($qual eq 'NONE') { $elems_qual = 0 }
        elsif($qual eq 'TOP')
        {   unless($elems_qual)
            {   # explitly overrule the name-space qualification of the
                # top-level element, which is dirty but people shouldn't
                # use unqualified schemas anyway!!!
                $node->removeAttribute('form');   # when in schema
                $node->setAttribute(form => 'qualified');
                delete $self->{elements_qualified};
                $elems_qual = 0;
            }
        }
        else {$elems_qual = $qual}
    }

    local $self->{elems_qual} = $elems_qual;
    local $self->{tns}        = $top->{ns};
    my $schemans = $node->namespaceURI;

    my $tree = XML::Compile::Iterator->new
      ( $node
      , $path
      , sub { my $n = shift;
                 $n->isa('XML::LibXML::Element')
              && $n->namespaceURI eq $schemans
              && $n->localName !~ $ignore_elements
            }
      );

    delete $self->{nest};  # reset recursion administration

    my $name = $node->localName;
    my $make
      = $name eq 'element'   ? $self->element($tree)
      : $name eq 'attribute' ? $self->attributeOne($tree)
      : error __x"top-level {full} is not an element or attribute but {name} at {where}"
            , full => $fullname, name => $name, where => $tree->path
            , class => 'usage';

    my $wrapper = $name eq 'element' ? 'element_wrapper' : 'attribute_wrapper';
    $self->make($wrapper, $path, $make);
}

sub typeByName($$)
{   my ($self, $tree, $typename) = @_;

    #
    # First try to catch build-ins
    #

    my $node  = $tree->node;
    my $code  = XML::Compile::Schema::Specs->builtInType
       ($node, $typename, sloppy_integers => $self->{sloppy_integers});

    if($code)
    {   my $where = $typename;
        my $st = $self->make
          (builtin=> $where, $node, $typename , $code, $self->{check_values});

        return +{ st => $st };
    }

    #
    # Then try own schemas
    #

    my $top    = $self->namespaces->find(complexType => $typename)
              || $self->namespaces->find(simpleType  => $typename)
       or error __x"cannot find type {type} at {where}"
            , type => $typename, where => $tree->path, class => 'usage';

    my $elems_qual
     = exists $self->{elements_qualified} ? $self->{elements_qualified}
     : $top->{efd} eq 'qualified';

    my $attrs_qual
     = exists $self->{attributes_qualified} ? $self->{attributes_qualified}
     : $top->{afd} eq 'qualified';

    # global settings for whole of sub-tree processing
    local $self->{elems_qual} = $elems_qual;
    local $self->{attrs_qual} = $attrs_qual;
    local $self->{tns}        = $top->{ns};

    my $typedef  = $top->{type};
    my $typeimpl = $tree->descend($top->{node});

      $typedef eq 'simpleType'  ? $self->simpleType($typeimpl)
    : $typedef eq 'complexType' ? $self->complexType($typeimpl)
    : error __x"expecting simple- or complexType, not '{type}' at {where}"
          , type => $typedef, where => $tree->path, class => 'schema';
}

sub simpleType($;$)
{   my ($self, $tree, $in_list) = @_;

    $tree->nrChildren==1
       or error __x"simpleType must have exactly one child at {where}"
            , where => $tree->path, class => 'schema';

    my $child = $tree->firstChild;
    my $name  = $child->localName;
    my $nest  = $tree->descend($child);

    # Full content:
    #    annotation?
    #  , (restriction | list | union)

    my $type
    = $name eq 'restriction' ? $self->simpleRestriction($nest, $in_list)
    : $name eq 'list'        ? $self->simpleList($nest)
    : $name eq 'union'       ? $self->simpleUnion($nest)
    : error __x"simpleType contains '{local}', must be restriction, list, or union at {where}"
          , local => $name, where => $tree->path, class => 'schema';

    delete @$type{'attrs','attrs_any'};  # spec says ignore attrs
    $type;
}

sub simpleList($)
{   my ($self, $tree) = @_;

    # attributes: id, itemType = QName
    # content: annotation?, simpleType?

    my $per_item;
    my $node  = $tree->node;
    my $where = $tree->path . '#list';

    if(my $type = $node->getAttribute('itemType'))
    {   $tree->nrChildren==0
            or error __x"list with both itemType and content at {where}"
                 , where => $where, class => 'schema';

        $self->assertType($where, itemType => QName => $type);
        my $typename = $self->rel2abs($where, $node, $type);
        $per_item    = $self->typeByName($tree, $typename);
    }
    else
    {   $tree->nrChildren==1
            or error __x"list expects one simpleType child at {where}"
                 , where => $where, class => 'schema';

        $tree->currentLocal eq 'simpleType'
            or error __x"list can only have a simpleType child at {where}"
                 , where => $where, class => 'schema';

        $per_item    = $self->simpleType($tree->descend, 1);
    }

    my $st = $per_item->{st}
        or panic "list did not produce a simple type at $where";

    $per_item->{st} = $self->make(list => $where, $st);
    $per_item->{is_list} = 1;
    $per_item;
}

sub simpleUnion($)
{   my ($self, $tree) = @_;

    # attributes: id, memberTypes = List of QName
    # content: annotation?, simpleType*

    my $node  = $tree->node;
    my $where = $tree->path . '#union';

    # Normal error handling switched off, and check_values must be on
    # When check_values is off, we may decide later to treat that as
    # string, which is faster but not 100% safe, where int 2 may be
    # formatted as float 1.999

    local $self->{check_values} = 1;

    my @types;
    if(my $members = $node->getAttribute('memberTypes'))
    {   foreach my $union (split " ", $members)
        {   $self->assertType($where, memberTypes => QName => $union);
            my $typename = $self->rel2abs($where, $node, $union);
            my $type = $self->typeByName($tree, $typename);
            my $st   = $type->{st}
                or error __x"union only of simpleTypes, but {type} is complex at {where}"
                     , type => $typename, where => $where, class => 'schema';

            push @types, $st;
        }
    }

    foreach my $child ($tree->childs)
    {   my $name = $child->localName;
        $name eq 'simpleType'
            or error __x"only simpleType's within union, found {local} at {where}"
                 , local => $name, where => $where, class => 'schema';

        my $ctype = $self->simpleType($tree->descend($child), 0);
        push @types, $ctype->{st};
    }

    my $do = $self->make(union => $where, @types);
    { st => $do, is_union => 1 };
}

sub simpleRestriction($$)
{   my ($self, $tree, $in_list) = @_;

    # attributes: id, base = QName
    # content: annotation?, simpleType?, facet*

    my $node  = $tree->node;
    my $where = $tree->path . '#sres';

    my $base;
    if(my $basename = $node->getAttribute('base'))
    {   $self->assertType($where, base => QName => $basename);
        my $typename = $self->rel2abs($where, $node, $basename);
        $base        = $self->typeByName($tree, $typename);
    }
    else
    {   my $simple   = $tree->firstChild
            or error __x"no base in simple-restriction, so simpleType required at {where}"
                   , where => $where, class => 'schema';

        $simple->localName eq 'simpleType'
            or error __x"simpleType expected, because there is no base attribute at {where}"
                   , where => $where, class => 'schema';

        $base = $self->simpleType($tree->descend($simple, 'st'));
        $tree->nextChild;
    }

    my $st = $base->{st}
        or error __x"simple-restriction is not a simpleType at {where}"
               , where => $where, class => 'schema';

    my $do = $self->applySimpleFacets($tree, $st, $in_list);

    $tree->currentChild
        and error __x"elements left at tail at {where}"
                , where => $tree->path, class => 'schema';

    +{ st => $do };
}

sub applySimpleFacets($$$)
{   my ($self, $tree, $st, $in_list) = @_;

    # partial
    # content: facet*
    # facet = minExclusive | minInclusive | maxExclusive | maxInclusive
    #   | totalDigits | fractionDigits | maxScale | minScale | length
    #   | minLength | maxLength | enumeration | whiteSpace | pattern

    my $where = $tree->path . '#facet';
    my %facets;
    for(my $child = $tree->currentChild; $child; $child = $tree->nextChild)
    {   my $facet = $child->localName;
        last if $facet =~ $attribute_defs;

        my $value = $child->getAttribute('value');
        defined $value
            or error __x"no value for facet `{facet}' at {where}"
                   , facet => $facet, where => $where, class => 'schema';

           if($facet eq 'enumeration') { push @{$facets{enumeration}}, $value }
        elsif($facet eq 'pattern')     { push @{$facets{pattern}}, $value }
        elsif(!exists $facets{$facet}) { $facets{$facet} = $value }
        else
        {   error __x"facet `{facet}' defined twice at {where}"
                , facet => $facet, where => $where, class => 'schema';
        }
    }

    return $st
        if $self->{ignore_facets} || !keys %facets;

    #
    # new facets overrule all of the base-class
    #

    if(defined $facets{totalDigits} && defined $facets{fractionDigits})
    {   my $td = delete $facets{totalDigits};
        my $fd = delete $facets{fractionDigits};
        $facets{totalFracDigits} = [$td, $fd];
    }

    # First the strictly ordered facets, before an eventual split
    # of the list, then the other facets
    my @early;
    foreach my $ordered ( qw/whiteSpace pattern/ )
    {   my $limit = delete $facets{$ordered};
        push @early, builtin_facet($where, $self, $ordered, $limit)
           if defined $limit;
    }

    my @late
      = map { builtin_facet($where, $self, $_, $facets{$_}) }
            keys %facets;

      $in_list
    ? $self->make(facets_list => $where, $st, \@early, \@late)
    : $self->make(facets => $where, $st, @early, @late);
}

sub element($)
{   my ($self, $tree) = @_;

    # attributes: abstract, default, fixed, form, id, maxOccurs, minOccurs
    #           , name, nillable, ref, substitutionGroup, type
    # ignored: block, final, targetNamespace additional restrictions
    # content: annotation?
    #        , (simpleType | complexType)?
    #        , (unique | key | keyref)*

    my $node     = $tree->node;
    my $name     = $node->getAttribute('name')
        or error __x"element has no name at {where}"
             , where => $tree->path, class => 'schema';

    $self->assertType($tree->path, name => NCName => $name);
    my $fullname = pack_type $self->{tns}, $name;

    # detect recursion
    my $nodeid = $$node;  # the internal SCALAR value; the C struct
    if(exists $self->{nest}{$nodeid})
    {   my $outer = \$self->{nest}{$nodeid};
        return sub { $$outer->(@_) };
    }
    $self->{nest}{$nodeid} = undef;

    my $where    = $tree->path. "#el($name)";
    my $form     = $node->getAttribute('form');
    my $qual
      = !defined $form         ? $self->{elems_qual}
      : $form eq 'qualified'   ? 1
      : $form eq 'unqualified' ? 0
      : error __x"form must be (un)qualified, not `{form}' at {where}"
            , form => $form, where => $tree->path, class => 'schema';

    my $trans     = $qual ? 'tag_qualified' : 'tag_unqualified';
    my $tag       = $self->make($trans => $where, $node, $name);

    my ($typename, $type);
    my $nr_childs = $tree->nrChildren;
    if(my $isa = $node->getAttribute('type'))
    {   $nr_childs==0
            or error __x"no childs expected with attribute `type' at {where}"
                   , where => $where, class => 'schema';

        $self->assertType($where, type => QName => $isa);
        $typename = $self->rel2abs($where, $node, $isa);
        $type     = $self->typeByName($tree, $typename);
    }
    elsif($nr_childs==0)
    {   $typename = $self->anyType($node);
        $type     = $self->typeByName($tree, $typename);
    }
    elsif($nr_childs!=1)
    {   error __x"expected is only one child at {where}"
          , where => $where, class => 'schema';
    }
    else # nameless types
    {   my $child = $tree->firstChild;
        my $local = $child->localname;
        my $nest  = $tree->descend($child);

        $type
          = $local eq 'simpleType'  ? $self->simpleType($nest, 0)
          : $local eq 'complexType' ? $self->complexType($nest)
          : error __x"unexpected element child `{name}' and {where}"
                , name => $local, where => $where, class => 'schema';
    }

    my ($before, $replace, $after)
      = $self->findHooks($where, $typename, $node);

    my ($st, $elems, $attrs, $attrs_any)
      = @$type{ qw/st elems attrs attrs_any/ };
    $_ ||= [] for $elems, $attrs, $attrs_any;

    my $r;
    if($replace) { ; }             # overrule processing
    elsif(! defined $st)           # complexType
    {   $r = $self->make(complex_element =>
            $where, $tag, $elems, $attrs, $attrs_any);
    }
    elsif(@$attrs || @$attrs_any)  # complex simpleContent
    {   $r = $self->make(tagged_element =>
            $where, $tag, $st, $attrs, $attrs_any);
    }
    else                           # simple
    {   $r = $self->make(simple_element => $where, $tag, $st);
    }

    my $do = ($before || $replace || $after)
      ? $self->make(hook => $where, $r, $tag, $before, $replace, $after)
      : $r;

    # this must look very silly to you... however, this is resolving
    # recursive schemas: this way nested use of the same element
    # definition will catch the code reference of the outer definition.
    $self->{nest}{$nodeid} = $do;
    delete $self->{nest}{$nodeid};  # clean the outer definition
}

sub particle($)
{   my ($self, $tree) = @_;

    my $node  = $tree->node;
    my $local = $node->localName;
    my $where = $tree->path;

    my $min   = $node->getAttribute('minOccurs');
    my $max   = $node->getAttribute('maxOccurs');

    $min = $self->{action} ne 'WRITER' || !$node->getAttribute('default')
        unless defined $min;
    # default attribute in writer means optional, but we want to see
    # them in the reader, to see the value.
 
    defined $max or $max = 1;

    $max = 'unbounded'
        if $max ne 'unbounded' && $max > 1 && !$self->{check_occurs};

#??
#   return ()
#       if $max ne 'unbounded' && $max==0;

    $min = 0
        if $max eq 'unbounded' && !$self->{check_occurs};

    return $self->anyElement($tree, $min, $max)
        if $local eq 'any';

    my ($label, $process)
      = $local eq 'element'        ? $self->particleElement($tree)
      : $local eq 'group'          ? $self->particleGroup($tree)
      : $local =~ $particle_blocks ? $self->particleBlock($tree)
      : error __x"unknown particle type '{name}' at {where}"
            , name => $local, where => $tree->path, class => 'schema';

    defined $label
        or return ();

    return $self->make(block_handler => $where, $label, $min, $max, $process, $local)
        if ref $process eq 'BLOCK';

    my $required = $min==0 ? undef
      : $self->make(required => $where, $label, $process);

    ($label => $self->make
       (element_handler => $where, $label, $min, $max, $required, $process));
}

sub particleGroup($)
{   my ($self, $tree) = @_;

    # attributes: id, maxOccurs, minOccurs, name, ref
    # content: annotation?, (all|choice|sequence)?
    # apparently, a group can not refer to a group... well..

    my $node  = $tree->node;
    my $where = $tree->path . '#group';
    my $ref   = $node->getAttribute('ref')
        or error __x"group without ref at {where}"
             , where => $where, class => 'schema';

    $self->assertType($tree, ref => QName => $ref);
    my $typename = $self->rel2abs($where, $node, $ref);

    my $dest    = $self->namespaces->find(group => $typename)
        or error __x"cannot find group `{name}' at {where}"
             , name => $typename, where => $where, class => 'schema';

    my $group   = $tree->descend($dest->{node});
    return {} if $group->nrChildren==0;

    $group->nrChildren==1
        or error __x"only one particle block expected in group `{name}' at {where}"
               , name => $typename, where => $where, class => 'schema';

    my $local = $group->currentLocal;
    $local    =~ m/^(?:all|choice|sequence)$/
        or error __x"illegal group member `{name}' at {where}"
               , name => $local, where => $where, class => 'schema';

    $self->particleBlock($group->descend);
}

sub particleBlock($)
{   my ($self, $tree) = @_;

    my $node  = $tree->node;
    my @pairs = map { $self->particle($tree->descend($_)) } $tree->childs;
    @pairs or return ();

    # label is name of first component, only needed when maxOcc > 1
    my $label     = $pairs[0];
    my $blocktype = $node->localName;

    ($label => $self->make($blocktype => $tree->path, @pairs));
}

sub findSgMemberNodes($)
{   my ($self, $type) = @_;
    my @subgrps;
    foreach my $subgrp ($self->namespaces->findSgMembers($type))
    {   my $node = $subgrp->{node};
        push @subgrps, $node;

        my $abstract = $node->getAttribute('abstract') || 'false';
        $self->isTrue($abstract) or next;

        my $groupname = $node->getAttribute('name')
            or error __x"substitutionGroup element needs name at {where}"
                 , where => $node->path, class => 'schema';

        my $subtype   = pack_type $self->{tns}, $groupname;
        push @subgrps, $self->findSgMemberNodes($subtype);
    }
    @subgrps;
}
        
sub particleElementSubst($)
{   my ($self, $tree) = @_;

    my $node  = $tree->node;
    my $where = $tree->path . '#subst';

    my $groupname = $node->getAttribute('name')
        or error __x"substitutionGroup element needs name at {where}"
               , where => $tree->path, class => 'schema';

    $self->assertType($where, name => QName => $groupname);
 
    my $tns     = $self->{tns};
    my $type    = pack_type $tns, $groupname;
    my @subgrps = $self->findSgMemberNodes($type);

    # at least the base is expected
    @subgrps
        or error __x"no substitutionGroups found for {type} at {where}"
               , type => $type, where => $where, class => 'schema';

    my @elems = map { $self->particleElement($tree->descend($_)) } @subgrps;

    ($groupname => $self->make(substgroup => $where, $type, @elems));
}

sub particleElement($)
{   my ($self, $tree) = @_;

    my $node  = $tree->node;

    if(my $ref =  $node->getAttribute('ref'))
    {   my $refname = $self->rel2abs($tree, $node, $ref);
        my $where   = $tree->path . "/$ref";

        my $def     = $self->namespaces->find(element => $refname)
            or error __x"cannot find element '{name}' at {where}"
                   , name => $refname, where => $where, class => 'schema';

        local $self->{tns} = $def->{ns};
        my $elems_qual = $def->{efd} eq 'qualified';
        if(exists $self->{elements_qualified})
        {   my $qual = $self->{elements_qualified} || 0;
            $elems_qual = $qual eq 'ALL' ? 1 : $qual eq 'NONE' ? 0 : $qual;
        }
        local $self->{elems_qual} = $elems_qual;

        my $attrs_qual = $def->{afd} eq 'qualified';
        if(exists $self->{attributes_qualified})
        {   my $qual = $self->{attributes_qualified} || 0;
            $attrs_qual = $qual eq 'ALL' ? 1 : $qual eq 'NONE' ? 0 : $qual;
        }
        local $self->{attrs_qual} = $attrs_qual;


        my $refnode  = $def->{node};
        my $abstract = $refnode->getAttribute('abstract') || 'false';
        $self->assertType($where, abstract => boolean => $abstract);

        return $self->isTrue($abstract)
          ? $self->particleElementSubst($tree->descend($refnode))
          : $self->particleElement($tree->descend($refnode, $ref));
    }

    my $name     = $node->getAttribute('name')
        or error __x"element needs name or ref at {where}"
               , where => $tree->path, class => 'schema';

    my $where    = $tree->path . "/el($name)";
    my $default  = $node->getAttributeNode('default');
    my $fixed    = $node->getAttributeNode('fixed');

    my $nillable = $node->getAttribute('nillable') || 'false';
    $self->assertType($where, nillable => boolean => $nillable);

    my $do       = $self->element($tree->descend($node, $name));

    my $generate
     = $self->isTrue($nillable) ? 'element_nillable'
     : defined $default         ? 'element_default'
     : defined $fixed           ? 'element_fixed'
     :                            'element';

    my $value
     = defined $default         ? $default->textContent
     : defined $fixed           ? $fixed->textContent
     : undef;

    my $ns    = $node->namespaceURI;
    my $do_el = $self->make($generate => $where, $ns, $name, $do, $value);

    $do_el = $self->make('element_href' => $where, $ns, $name, $do_el)
        if $self->{permit_href} && $self->{action} eq 'READER';
 
    ($name => $do_el);
}

sub attributeOne($)
{   my ($self, $tree) = @_;

    # attributes: default, fixed, form, id, name, ref, type, use
    # content: annotation?, simpleType?

    my $node = $tree->node;
    my $type;

    my($ref, $name, $form, $typeattr);
    if(my $refattr =  $node->getAttribute('ref'))
    {   $self->assertType($tree, ref => QName => $refattr);

        my $refname = $self->rel2abs($tree, $node, $refattr);
        my $def     = $self->namespaces->find(attribute => $refname)
            or error __x"cannot find attribute {name} at {where}"
                 , name => $refname, where => $tree->path, class => 'schema';

        $ref        = $def->{node};
        local $self->{tns} = $def->{ns};
        my $attrs_qual = $def->{efd} eq 'qualified';
        if(exists $self->{attributes_qualified})
        {   my $qual = $self->{attributes_qualified} || 0;
            $attrs_qual = $qual eq 'ALL' ? 1 : $qual eq 'NONE' ? 0 : $qual;
        }
        local $self->{attrs_qual} = $attrs_qual;

        $name       = $ref->getAttribute('name')
            or error __x"ref attribute without name at {where}"
                 , where => $tree->path, class => 'schema';

        if($typeattr = $ref->getAttribute('type'))
        {   # postpone interpretation
        }
        else
        {   my $other = $tree->descend($ref);
            $other->nrChildren==1 && $other->currentLocal eq 'simpleType'
                or error __x"toplevel attribute {type} has no type attribute nor single simpleType child"
                     , type => $refname, class => 'schema';
            $type   = $self->simpleType($other->descend);
        }
        $form = $ref->getAttribute('form');
        $node = $ref;
    }
    elsif($tree->nrChildren==1)
    {   $tree->currentLocal eq 'simpleType'
            or error __x"attribute child can only be `simpleType', not `{found}' at {where}"
                 , found => $tree->currentLocal, where => $tree->path
                 , class => 'schema';

        $name       = $node->getAttribute('name')
            or error __x"attribute without name at {where}"
                   , where => $tree->path;

        $form       = $node->getAttribute('form');
        $type       = $self->simpleType($tree->descend);
    }

    else
    {   $name       = $node->getAttribute('name')
            or error __x"attribute without name or ref at {where}"
                   , where => $tree->path, class => 'schema';

        $typeattr   = $node->getAttribute('type');
        $form       = $node->getAttribute('form');
    }

    my $where = $tree->path.'/@'.$name;
    $self->assertType($where, name => NCName => $name);
    $self->assertType($where, type => QName => $typeattr)
        if $typeattr;

    unless($type)
    {   my $typename = defined $typeattr
          ? $self->rel2abs($where, $node, $typeattr)
          : $self->anyType($node);

         $type  = $self->typeByName($tree, $typename);
    }

    my $st      = $type->{st}
        or error __x"attribute not based in simple value type at {where}"
             , where => $where, class => 'schema';

    my $qual
      = ! defined $form        ? $self->{attrs_qual}
      : $form eq 'qualified'   ? 1
      : $form eq 'unqualified' ? 0
      : error __x"form must be (un)qualified, not {form} at {where}"
            , form => $form, where => $where, class => 'schema';

    my $trans   = $qual ? 'tag_qualified' : 'tag_unqualified';
    my $tag     = $self->make($trans => $where, $node, $name);
    my $ns      = $qual ? $self->{tns} : '';

    my $use     = $node->getAttribute('use') || '';
    $use =~ m/^(?:optional|required|prohibited|)$/
        or error __x"attribute use is required, optional or prohibited (not '{use}') at {where}"
             , use => $use, where => $where, class => 'schema';

    my $default = $node->getAttributeNode('default');
    my $fixed   = $node->getAttributeNode('fixed');

    my $generate
     = defined $default    ? 'attribute_default'
     : defined $fixed
     ? ($use eq 'optional' ? 'attribute_fixed_optional' : 'attribute_fixed')
     : $use eq 'required'  ? 'attribute_required'
     : $use eq 'prohibited'? 'attribute_prohibited'
     :                       'attribute';

    my $value = defined $default ? $default : $fixed;
    my $do    = $self->make($generate => $where, $ns, $tag, $st, $value);
    defined $do ? ($name => $do) : ();
}

sub attributeGroup($)
{   my ($self, $tree) = @_;

    # attributes: id, ref = QName
    # content: annotation?

    my $node  = $tree->node;
    my $where = $tree->path;
    my $ref   = $node->getAttribute('ref')
        or error __x"attributeGroup use without ref at {where}"
             , where => $tree->path, class => 'schema';

    $self->assertType($where, ref => QName => $ref);

    my $typename = $self->rel2abs($where, $node, $ref);

    my $def  = $self->namespaces->find(attributeGroup => $typename)
        or error __x"cannot find attributeGroup {name} at {where}"
             , name => $typename, where => $where, class => 'schema';

    $self->attributeList($tree->descend($def->{node}));
}

# Don't known how to handle notQName
sub anyAttribute($)
{   my ($self, $tree) = @_;

    # attributes: id
    #  , namespace = ##any|##other| List of (anyURI|##targetNamespace|##local)
    #  , notNamespace = List of (anyURI|##targetNamespace|##local)
    # ignored attributes
    #  , notQName = List of QName
    #  , processContents = lax|skip|strict
    # content: annotation?

    my $node      = $tree->node;
    my $where     = $tree->path . '@any';

    my $handler   = $self->{anyAttribute};
    my $namespace = $node->getAttribute('namespace')       || '##any';
    my $not_ns    = $node->getAttribute('notNamespace');
    my $process   = $node->getAttribute('processContents') || 'strict';

    warn "HELP: please explain me how to handle notQName"
        if $^W && $node->getAttribute('notQName');

    my ($yes, $no) = $self->translateNsLimits($namespace, $not_ns);
    my $do = $self->make(anyAttribute => $where, $handler, $yes, $no, $process);
    defined $do ? $do : ();
}

sub anyElement($$$)
{   my ($self, $tree, $min, $max) = @_;

    # attributes: id, maxOccurs, minOccurs,
    #  , namespace = ##any|##other| List of (anyURI|##targetNamespace|##local)
    #  , notNamespace = List of (anyURI|##targetNamespace|##local)
    # ignored attributes
    #  , notQName = List of QName
    #  , processContents = lax|skip|strict
    # content: annotation?

    my $node      = $tree->node;
    my $where     = $tree->path . '#any';
    my $handler   = $self->{anyElement};

    my $namespace = $node->getAttribute('namespace')       || '##any';
    my $not_ns    = $node->getAttribute('notNamespace');
    my $process   = $node->getAttribute('processContents') || 'strict';

    info "HELP: please explain me how to handle notQName"
        if $^W && $node->getAttribute('notQName');

    my ($yes, $no) = $self->translateNsLimits($namespace, $not_ns);
    (any => $self->make(anyElement =>
        $where, $handler, $yes, $no, $process, $min, $max));
}

sub translateNsLimits($$)
{   my ($self, $include, $exclude) = @_;

    # namespace    = ##any|##other| List of (anyURI|##targetNamespace|##local)
    # notNamespace = List of (anyURI |##targetNamespace|##local)
    # handling of ##local ignored: only full namespaces are supported for now

    return (undef, [])     if $include eq '##any';

    my $tns       = $self->{tns};
    return (undef, [$tns]) if $include eq '##other';

    my @return;
    foreach my $list ($include, $exclude)
    {   my @list;
        if(defined $list && length $list)
        {   foreach my $url (split " ", $list)
            {   push @list
                 , $url eq '##targetNamespace' ? $tns
                 : $url eq '##local'           ? ()
                 : $url;
            }
        }
        push @return, @list ? \@list : undef;
    }

    @return;
}

sub complexType($)
{   my ($self, $tree) = @_;

    # Full content:
    #    annotation?
    #  , ( simpleContent
    #    | complexContent
    #    | ( (group|all|choice|sequence)?
    #      , (attribute|attributeGroup)*
    #      , anyAttribute?
    #      )
    #    )
    #  , (assert | report)*

    my $first = $tree->firstChild
        or return {};

    my $name  = $first->localName;
    return $self->complexBody($tree)
        if $name =~ $particle_blocks || $name =~ $attribute_defs;

    $tree->nrChildren==1
        or error __x"expected is single simpleContent or complexContent at {where}"
             , where => $tree->path, class => 'schema';

    my $nest  = $tree->descend($first);
    return $self->simpleContent($nest)
        if $name eq 'simpleContent';

    return  $self->complexContent($nest)
        if $name eq 'complexContent';

    error __x"complexType contains particles, simpleContent or complexContent, not `{name}' at {where}"
      , name => $name, where => $tree->path, class => 'schema';
}

sub complexBody($)
{   my ($self, $tree) = @_;

    $tree->currentChild
        or return ();

    # partial
    #    (group|all|choice|sequence)?
    #  , ((attribute|attributeGroup)*
    #  , anyAttribute?

    my @elems;
    if($tree->currentLocal =~ $particle_blocks)
    {   push @elems, $self->particle($tree->descend);
        $tree->nextChild;
    }

    my @attrs = $self->attributeList($tree);

    defined $tree->currentChild
        and error __x"trailing non-attribute `{name}' at {where}"
              , name => $tree->currentChild->localName, where => $tree->path
              , class => 'schema';

    {elems => \@elems, @attrs};
}

sub attributeList($)
{   my ($self, $tree) = @_;

    # partial content
    #    ((attribute|attributeGroup)*
    #  , anyAttribute?

    my $where = $tree->path;

    my (@attrs, @any);
    for(my $attr = $tree->currentChild; defined $attr; $attr = $tree->nextChild)
    {   my $name = $attr->localName;
        if($name eq 'attribute')
        {   push @attrs, $self->attributeOne($tree->descend) }
        elsif($name eq 'attributeGroup')
        {   my %group = $self->attributeGroup($tree->descend);
            push @attrs, @{$group{attrs}};
            push @any,   @{$group{attrs_any}};
        }
        else { last }
    }

    # officially only one: don't believe that
    while($tree->currentLocal eq 'anyAttribute')
    {   push @any, $self->anyAttribute($tree->descend);
        $tree->nextChild;
    }

    (attrs => \@attrs, attrs_any => \@any);
}

sub simpleContent($)
{   my ($self, $tree) = @_;

    # attributes: id
    # content: annotation?, (restriction | extension)

    $tree->nrChildren==1
        or error __x"need one simpleContent child at {where}"
             , where => $tree->path, class => 'schema';

    my $name  = $tree->currentLocal;
    return $self->simpleContentExtension($tree->descend)
        if $name eq 'extension';

    return $self->simpleContentRestriction($tree->descend)
        if $name eq 'restriction';

     error __x"simpleContent needs extension or restriction, not `{name}' at {where}"
         , name => $name, where => $tree->path, class => 'schema';
}

sub simpleContentExtension($)
{   my ($self, $tree) = @_;

    # attributes: id, base = QName
    # content: annotation?
    #        , (attribute | attributeGroup)*
    #        , anyAttribute?
    #        , (assert | report)*

    my $node     = $tree->node;
    my $where    = $tree->path . '#sext';

    my $base     = $node->getAttribute('base');
    my $typename = defined $base ? $self->rel2abs($where, $node, $base)
     : $self->anyType($node);

    my $basetype = $self->typeByName($tree, $typename);
    defined $basetype->{st}
        or error __x"base of simpleContent not simple at {where}"
             , where => $where, class => 'schema';
 
    $self->extendAttrs($basetype, $self->attributeList($tree));
    $tree->currentChild
        and error __x"elements left at tail at {where}"
              , where => $tree->path, class => 'schema';

    $basetype;

}

sub simpleContentRestriction($$)
{   my ($self, $tree) = @_;

    # attributes id, base = QName
    # content: annotation?
    #        , (simpleType?, facet*)?
    #        , (attribute | attributeGroup)*, anyAttribute?
    #        , (assert | report)*

    my $node  = $tree->node;
    my $where = $tree->path . '#cres';

    my $type;
    if(my $basename = $node->getAttribute('base'))
    {   $self->assertType($where, base => QName => $basename);
        my $typename = $self->rel2abs($where, $node, $basename);
        $type        = $self->typeByName($tree, $typename);
    }
    else
    {   my $first    = $tree->currentLocal
            or error __x"no base in complex-restriction, so simpleType required at {where}"
                 , where => $where, class => 'schema';

        $first eq 'simpleType'
            or error __x"simpleType expected, because there is no base attribute at {where}"
                 , where => $where, class => 'schema';

        $type = $self->simpleType($tree->descend);
        $tree->nextChild;
    }

    my $st = $type->{st}
        or error __x"not a simpleType in simpleContent/restriction at {where}"
             , where => $where, class => 'schema';

    $type->{st} = $self->applySimpleFacets($tree, $st, 0);

    $self->extendAttrs($type, $self->attributeList($tree));

    $tree->currentChild
        and error __x"elements left at tail at {where}"
                , where => $where, class => 'schema';

    $type;
}

sub complexContent($)
{   my ($self, $tree) = @_;

    # attributes: id, mixed = boolean
    # content: annotation?, (restriction | extension)

    my $node = $tree->node;
    #$self->isTrue($node->getAttribute('mixed') || 'false')
    
    $tree->nrChildren == 1
        or error __x"only one complexContent child expected at {where}"
             , where => $tree->path, class => 'schema';

    my $name  = $tree->currentLocal;
 
    return $self->complexContentExtension($tree->descend)
        if $name eq 'extension';

    # nice for validating, but base can be ignored
    return $self->complexBody($tree->descend)
        if $name eq 'restriction';

    error __x"complexContent needs extension or restriction, not `{name}' at {where}"
        , name => $name, where => $tree->path, class => 'schema';
}

sub complexContentExtension($)
{   my ($self, $tree) = @_;

    my $node  = $tree->node;
    my $base  = $node->getAttribute('base') || 'anyType';
    my $type  = {};
    my $where = $tree->path . '#cce';

    if($base ne 'anyType')
    {   my $typename = $self->rel2abs($where, $node, $base);
        my $typedef  = $self->namespaces->find(complexType => $typename)
            or error __x"unknown base type '{type}' at {where}"
                 , type => $typename, where => $tree->path, class => 'schema';

        $type = $self->complexType($tree->descend($typedef->{node}));
    }

    my $own = $self->complexBody($tree);
    unshift @{$own->{$_}}, @{$type->{$_} || []}
        for qw/elems attrs attrs_any/;

    $own;
}

#
# Helper routines
#

# print $self->rel2abs($path, $node, '{ns}type')    ->  '{ns}type'
# print $self->rel2abs($path, $node, 'prefix:type') ->  '{ns(prefix)}type'

sub rel2abs($$$)
{   my ($self, $where, $node, $type) = @_;
    return $type if substr($type, 0, 1) eq '{';

    my ($prefix, $local) = $type =~ m/^(.+?)\:(.*)/ ? ($1, $2) : ('', $type);
    my $url = $node->lookupNamespaceURI($prefix);

    error __x"No namespace for prefix `{prefix}' in `{type}' at {where}"
      , prefix => $prefix, type => $type, where => $where, class => 'schema'
        if length $prefix && !defined $url;

     pack_type $url, $local;
}

sub anyType($)
{   my ($self, $node) = @_;
    pack_type $node->namespaceURI, 'anyType';
}

sub findHooks($$$)
{   my ($self, $path, $type, $node) = @_;
    # where is before, replace, after

    my %hooks;
    foreach my $hook (@{$self->{hooks}})
    {   my $match;

        $match++
            if !$hook->{path} && !$hook->{id}
            && !$hook->{type} && !$hook->{attribute};

        if(!$match && $hook->{path})
        {   my $p = $hook->{path};
            $match++
               if first {ref $_ eq 'Regexp' ? $path =~ $_ : $path eq $_}
                     ref $p eq 'ARRAY' ? @$p : $p;
        }

        my $id = !$match && $hook->{id} && $node->getAttribute('id');
        if($id)
        {   my $i = $hook->{id};
            $match++
                if first {ref $_ eq 'Regexp' ? $id =~ $_ : $id eq $_} 
                    ref $i eq 'ARRAY' ? @$i : $i;
        }

        if(!$match && defined $type && $hook->{type})
        {   my $t  = $hook->{type};
            my ($ns, $local) = unpack_type $t;
            $match++
                if first {ref $_ eq 'Regexp'     ? $type  =~ $_
                         : substr($_,0,1) eq '{' ? $type  eq $_
                         :                         $local eq $_
                         } ref $t eq 'ARRAY' ? @$t : $t;
        }

        $match or next;

        foreach my $where ( qw/before replace after/ )
        {   my $w = $hook->{$where} or next;
            push @{$hooks{$where}}, ref $w eq 'ARRAY' ? @$w : $w;
        }
    }

    @hooks{ qw/before replace after/ };
}

=chapter DETAILS

=section Translator options

=subsection performance optimization

The M<XML::Compile::Schema::compile()> method (and wrappers) defines
a set options to improve performance or usability.  These options
are translated into the executed code: compile time, not run-time!

The following options with their implications:

=over 4

=item sloppy_integers BOOLEAN

The C<integer> type, as defined by the schema built-in specification,
accepts really huge values.  Also the derived types, like
C<nonNegativeInteger> can contain much larger values than Perl's
internal C<long>.  Therefore, the module will start to use M<Math::BigInt>
for these types if needed.

However, in most cases, people design C<integer> where an C<int> suffices.
The use of big-int values comes with heigh performance costs.  Set this
option to C<true> when you are sure that ALL USES of C<integer> in the
scheme will fit into signed longs (are between -2147483648 and 2147483647
inclusive)

If you do not want limit the number-space, you can safely add
  use Math::BigInt try => 'GMP'
to the top of your main program, and install M<Math::BigInt::GMP>.  Then,
a C library will do the work, much faster than the Perl implementation.

=item check_values BOOLEAN

Check the validity of the values, before parsing them.  This will
report errors for the reader, instead of crashes.  The writer will
not produce invalid data.

=item check_occurs BOOLEAN

Checking whether the number of occurrences for an item are between
C<minOccurs> and C<maxOccurs> (implied for C<all>, C<sequence>, and
C<choice> or explictly specified) takes time.  Of course, in cases
errors must be handled.  When this option is set to C<false>, 
only distinction between single and array elements is made.

=item ignore_facets BOOLEAN

Facets limit field content in the restriction block of a simpleType.
When this option is C<true>, no checks are performed on the values.
In some cases, this may cause problems: especially with whiteSpace and
digits of floats.  However, you may be able to control this yourself.
In most cases, luck even plays a part in this.  Less checks means a
better performance.

Simple type restrictions are not implemented by other XML perl
modules.  When the schema is nicely detailed, this will give
extra security.

=item validation BOOLEAN

When used, it overrules the above C<check_values>, C<check_occurs>, and
C<ignore_facets> options.  A true value enables all checks, a false
value will disable them all.  Of course, the latter is the fastest but
also less secure: your program will need to validate the values in some
other way.

XML::LibXML has its own validate method, but I have not yet seen any
performance figures on that.  If you use it, however, it is of course
a good idea to turn XML::Compile's validation off.

=back

=subsection qualified XML

The produced XML may not use the name-spaces as defined by the schemas,
just to simplify the input and output.  The structural definition of
the schemas is still in-tact, but name-space collission may appear.

Per schema, it can be specified whether the elements and attributes
defined in-there need to be used qualified (with prefix) or not.
This can cause horrible output when within an unqualified schema
elements are used from an other schema which is qualified.

The suggested solution in articles about the subject is to provide
people with both a schema which is qualified as one which is not.
Perl is known to be blunt in its approach: we simply define a flag
which can force one of both on all schemas together, using
C<elements_qualified> and C<attributes_qualified>.  May people and
applications do not understand name-spaces sufficiently, and these
options may make your day!

=subsection Name-spaces

The translator does respect name-spaces, but not all senders and
receivers of XML are name-space capable.  Therefore, you have some
options to interfere.

=over 4

=item output_namespaces HASH|ARRAY-of-PAIRS
The translator will create XML elements (WRITER) which use name-spaces,
based on its own name-space/prefix mapping administration.  This is
needed because the XML tree is created bottom-up, where XML::LibXML
namespace management can only handle this top-down.

When your pass your own HASH as argument, you can explicitly specify the
prefixes you like to be used for which name-space.  Found name-spaces
will be added to the HASH, as well the use count.  When a new name-space
URI is discovered, an attempt is made to use the prefix as found in
the schema. Prefix collisions are actively avoided: when two URIs want
the same prefix, a sequence number is added to one of them which makes
it unique.

The HASH structure looks like this:

  my %namespaces =
    ( myns => { uri => 'myns', prefix => 'mypref', used => 1}
    , ...  => { uri => ... }
    );

  my $make = $schema->compile
    ( WRITER => ...
    , output_namespaces => \%namespaces
    );

  # share the same namespace defs with an other component
  my $other = $schema->compile
    ( WRITER => ...
    , output_namespaces => \%namespaces
    );

When used is specified and larger than 0, then the namespace will
appear in the top-level output element (unless C<include_namespaces>
is false).

Initializing using an ARRAY is a little simpler:

 output_namespaces => [ mypref => 'myns', ... => ... ];

However, be warned that this does not work well with a false value
for C<include_namespaces>: detected namespaces are added to an
internal HASH now, which is not returned; that information is lost.
You will need to know each used namespace beforehand.

=item include_namespaces BOOLEAN
When true and WRITER, the top level returned XML element will contain
the prefix definitions.  Only name-spaces which are actually used
will be included (a count is kept by the translator).  It may
very well list name-spaces which are not in the actual output
because the fields which require them are not included for there is
not value for those fields.

If you like to combine XML output from separate translated parts
(for instance in case of generating SOAP), you may want to delay
the inclusion of name-spaces until a higher level of the XML
hierarchy which is produced later.

=item namespace_reset BOOLEAN
You can pass the same HASH to a next call to a reader or writer to get
consistent name-space usage.  However, when C<include_namespaces> is
used, you may get ghost name-space listings.  This option will reset
the counts on all defined name-spaces.

=item use_default_namespace BOOLEAN (added in release 0.57)
When a true value, the blank prefix will be used for the first namespace
URI which requires a auto-generated prefix.  However, in quite some
environments, people mix horrible non-namespace qualified elements with 
nice namespace qualified elements.  In such situations, namespace the
qualified-but-default prefix (i.e., no prefix) is confusing.  Therefore,
the option defaults to false: do not use the invisible prefix.

You may explicitly specify a blank prefix with C<output_namespaces>,
which will be used when applicable.
=back

=subsection Wildcards handlers

Wildcards are a serious complication: the C<any> and C<anyAttribute>
entities do not describe exactly what can be found, which seriously
hinders the quality of validation and the preparation of M<XML::Compile>.
Therefore, if you use them then you need to process that parts of
XML yourself.  See the various backends on how to create or process
these elements.

=over 4

=item anyElement CODE|'TAKE_ALL'
This will be called when the type definition contains an C<any>
definition, after processing the other element components.  By
default, all C<any> specifications will be ignored.

=item anyAttribute CODE|'TAKE_ALL'
This will be called when the type definitions contains an
C<anyAttribute> definition, after processing the other attributes.
By default, all C<anyAttribute> specifications will be ignored.

=back

=cut

1;
