use warnings;
use strict;

package XML::Compile::Schema::Translate;

use Log::Report 'xml-compile', syntax => 'SHORT';
use List::Util  'first';

use XML::Compile::Schema::Specs;
use XML::Compile::Schema::BuiltInFacets;
use XML::Compile::Schema::BuiltInTypes   qw/%builtin_types/;
use XML::Compile::Util                   qw/pack_type/;
use XML::Compile::Iterator               ();

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

Non-namespace schema elements are not implemented, because you shouldn't
want that!  Therefore, missing are
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
 element mixed
 attribute limitiations (facets) on dates
 full understanding of patterns (now limited)
 final is not protected
 QName writer namespace to prefix translation

Of course, the latter list is all fixed in next release ;-)
See chapter L</DETAILS> for more on how the tune the translator.

=chapter METHODS

=c_method compileTree ELEMENT|ATTRIBUTE, OPTIONS
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
{   my ($class, $element, %args) = @_;

    my $path   = $element;
    my $self   = bless \%args, $class;

    ref $element
        and panic "expecting an element name as point to start at $path";

    $self->{bricks}
        or panic "no bricks to build";

    $self->{nss}
        or panic "no namespace tables";

    $self->{hooks}
        or panic "no hooks list defined";

    $self->{action}
        or panic "action type is needed";

    if(my $def = $self->namespaces->findID($element))
    {   my $node  = $def->{node};
        my $name  = $node->localName;

           $name eq 'element'
        or $name eq 'attribute'
        or error __x"ID {id} must be an element or attribute, but is {name}"
              , id => $element, name => $name;

        $element  = $def->{full};
    }

    my $produce = $self->topLevel($path, $element);

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
        , field => $field, value => $value, type => $type, where => $where;

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
    my $nss  = $self->namespaces;

    my $top  = $nss->find(element   => $fullname)
            || $nss->find(attribute => $fullname)
       or error __x(( $fullname eq $path
                    ? N__"cannot find element or attribute {name}"
                    : N__"cannot find element or attribute {name} at {where}"
                    ), name => $fullname, where => $path);

    my $node = $top->{node};

    my $elems_qual = $top->{efd} eq 'qualified';
    if(exists $self->{elements_qualified})
    {   my $qual = $self->{elements_qualified} || 0;
           if($qual eq 'ALL')  { $elems_qual = 1 }
        elsif($qual eq 'NONE') { $elems_qual = 0 }
        elsif($qual ne 'TOP')  { $elems_qual = $qual }
        else
        {   # explitly overrule the name-space qualification of the
            # top-level element, which is dirty but people shouldn't
            # use unqualified schemas anyway!!!
            $node->removeAttribute('form');   # when in schema
            $node->setAttribute(form => 'qualified');
        }
    }

    local $self->{elems_qual} = $elems_qual;
    local $self->{tns}        = $top->{ns};
    my $schemans = $node->namespaceURI;

    my $tree = XML::Compile::Iterator->new
      ( $top->{node}
      , $path
      , sub { my $n = shift;
                 $n->isa('XML::LibXML::Element')
              && $n->namespaceURI eq $schemans
              && $n->localName !~ $ignore_elements
            }
      );

    my $name = $node->localName;
    my $make
      = $name eq 'element'   ? $self->element($tree)
      : $name eq 'attribute' ? $self->attributeOne($tree)
      : error __x"top-level {full} is not an element or attribute but {name} at {where}"
            , full => $fullname, name => $name, where => $tree->path;

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
          ( builtin=> $where, $node, $typename , $code, $self->{check_values});

        return +{ st => $st };
    }

    #
    # Then try own schemas
    #

    my $top    = $self->namespaces->find(complexType => $typename)
              || $self->namespaces->find(simpleType  => $typename)
       or error __x"cannot find type {type} at {where}"
              , type => $typename, where => $tree->path;

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
          , type => $typedef, where => $tree->path;
}

sub simpleType($;$)
{   my ($self, $tree, $in_list) = @_;

    $tree->nrChildren==1
       or error __x"simpleType must have exactly one child at {where}"
              , where => $tree->path;

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
          , local => $name, where => $tree->path;

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
                   , where => $where;

        $self->assertType($where, itemType => QName => $type);
        my $typename = $self->rel2abs($where, $node, $type);
        $per_item    = $self->typeByName($tree, $typename);
    }
    else
    {   $tree->nrChildren==1
            or error __x"list expects one simpleType child at {where}"
                   , where => $where;

        $tree->currentLocal eq 'simpleType'
            or error __x"list can only have a simpleType child at {where}"
                   , where => $where;

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
                       , type => $typename, where => $where;

            push @types, $st;
        }
    }

    foreach my $child ($tree->childs)
    {   my $name = $child->localName;
        $name eq 'simpleType'
            or error __x"only simpleType's within union, found {local} at {where}"
                   , local => $name, where => $where;

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
                   , where => $where;

        $simple->localName eq 'simpleType'
            or error __x"simpleType expected, because there is no base attribute at {where}"
                   , where => $where;

        $base = $self->simpleType($tree->descend($simple, 'st'));
        $tree->nextChild;
    }

    my $st = $base->{st}
        or error __x"simple-restriction is not a simpleType at {where}"
               , where => $where;

    my $do = $self->applySimpleFacets($tree, $st, $in_list);

    $tree->currentChild
        and error __x"elements left at tail at {where}"
                , where => $tree->path;

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
                   , facet => $facet, where => $where;

           if($facet eq 'enumeration') { push @{$facets{enumeration}}, $value }
        elsif($facet eq 'pattern')     { push @{$facets{pattern}}, $value }
        elsif(!exists $facets{$facet}) { $facets{$facet} = $value }
        else
        {   error __x"facet `{facet}' defined twice at {where}"
                , facet => $facet, where => $where;
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
    # ignored: block, final
    # content: annotation?
    #        , (simpleType | complexType)?
    #        , (unique | key | keyref)*

    my $node     = $tree->node;
    my $name     = $node->getAttribute('name')
        or error __x"element has no name at {where}", where => $tree->path;

    $self->assertType($tree->path, name => NCName => $name);

    my $where    = $tree->path. "#el($name)";
    my $form     = $node->getAttribute('form');
    my $qual
      = !defined $form         ? $self->{elems_qual}
      : $form eq 'qualified'   ? 1
      : $form eq 'unqualified' ? 0
      : error __x"form must be (un)qualified, not `{form}' at {where}"
            , form => $form, where => $tree->path;

    my $trans     = $qual ? 'tag_qualified' : 'tag_unqualified';
    my $tag       = $self->make($trans => $where, $node, $name);

    my ($typename, $type);
    my $nr_childs = $tree->nrChildren;
    if(my $isa = $node->getAttribute('type'))
    {   $nr_childs==0
            or error __x"no childs expected with attribute `type' at {where}"
                   , where => $where;

        $self->assertType($where, type => QName => $isa);
        $typename = $self->rel2abs($where, $node, $isa);
        $type     = $self->typeByName($tree, $typename);
    }
    elsif($nr_childs==0)
    {   $typename = $self->anyType($node);
        $type     = $self->typeByName($tree, $typename);
    }
    elsif($nr_childs!=1)
    {   error __x"expected is only one child at {where}", where => $where;
    }
    else # nameless types
    {   my $child = $tree->firstChild;
        my $local = $child->localname;
        my $nest  = $tree->descend($child);

        $type
          = $local eq 'simpleType'  ? $self->simpleType($nest, 0)
          : $local eq 'complexType' ? $self->complexType($nest)
          : error __x"unexpected element child `{name}' and {where}"
                , name => $local, where => $where;
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

      ($before || $replace || $after)
    ? $self->make(hook => $where, $r, $tag, $before, $replace, $after)
    : $r
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

    $min = 0
        if $max eq 'unbounded' && !$self->{check_occurs};

    return $self->anyElement($tree, $min, $max)
        if $local eq 'any';

    my ($label, $process)
      = $local eq 'element'        ? $self->particleElement($tree)
      : $local eq 'group'          ? $self->particleGroup($tree)
      : $local =~ $particle_blocks ? $self->particleBlock($tree)
      : error __x"unknown particle type '{name}' at {where}"
            , name => $local, where => $tree->path;

   return ($label =>
     $self->make(block_handler => $where, $label, $min, $max, $process, $local))
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
        or error __x"group without ref at {where}", where => $where;

    $self->assertType($tree, ref => QName => $ref);
    my $typename = $self->rel2abs($where, $node, $ref);

    my $dest    = $self->namespaces->find(group => $typename)
        or error __x"cannot find group `{name}' at {where}"
               , name => $typename, where => $where;

    my $group   = $tree->descend($dest->{node});
    return {} if $group->nrChildren==0;

    $group->nrChildren==1
        or error __x"only one particle block expected in group `{name}' at {where}"
               , name => $typename, where => $where;

    my $local = $group->currentLocal;
    $local    =~ m/^(?:all|choice|sequence)$/
        or error __x"illegal group member `{name}' at {where}"
               , name => $local, where => $where;

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

sub particleElementSubst($)
{   my ($self, $tree) = @_;

    my $node  = $tree->node;
    my $where = $tree->path . '#subst';

    my $groupname = $node->getAttribute('name')
        or error __x"substitutionGroup element needs name at {where}"
               , where => $tree->path;

    $self->assertType($where, name => QName => $groupname);
 
    my $tns     = $self->{tns};
    my $type    = pack_type $tns, $groupname;
    my @subgrps = map {$_->{node}}
        $self->namespaces->findSgMembers($type);

    # at least the base is expected
    @subgrps
        or error __x"no substitutionGroups found for {type} at {where}"
               , type => $type, where => $where;

    my @elems = map { $self->particleElement($tree->descend($_)) } @subgrps;

    ($groupname => $self->make(substgroup => $where, $type, @elems));
}

sub particleElement($)
{   my ($self, $tree) = @_;

    my $node  = $tree->node;

    if(my $ref =  $node->getAttribute('ref'))
    {   my $refname = $self->rel2abs($tree, $node, $ref);
        my $where   = $tree->path . "#ref($ref)";

        my $def     = $self->namespaces->find(element => $refname)
            or error __x"cannot find element '{name}' at {where}"
                   , name => $refname, where => $where;

        my $refnode  = $def->{node};
        my $abstract = $refnode->getAttribute('abstract') || 'false';
        $self->assertType($where, abstract => boolean => $abstract);

        return $self->isTrue($abstract)
          ? $self->particleElementSubst($tree->descend($refnode))
          : $self->particleElement($tree->descend($refnode, 'ref'));
    }

    my $name     = $node->getAttribute('name')
        or error __x"element needs name or ref at {where}"
               , where => $tree->path;

    my $where    = $tree->path . "/el($name)";
    my $default  = $node->getAttributeNode('default');
    my $fixed    = $node->getAttributeNode('fixed');

    my $nillable = $node->getAttribute('nillable') || 'false';
    $self->assertType($where, nillable => boolean => $nillable);

    my $do       = $self->element($tree->descend($node));

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
    ($name => $self->make($generate => $where, $ns, $name, $do, $value));
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
                   , name => $refname, where => $tree->path;

        $ref        = $def->{node};
        $name       = $ref->getAttribute('name')
            or error __x"ref attribute without name at {where}"
                   , where => $tree->path;

        if($typeattr = $ref->getAttribute('type'))
        {   # postpone interpretation
        }
        else
        {   my $other = $tree->descend($ref);
            $other->nrChildren==1 && $other->currentLocal eq 'simpleType'
                or error __x"toplevel attribute {type} has no type attribute nor single simpleType child"
                      , type => $refname;
            $type   = $self->simpleType($other->descend);
        }
        $form       = $ref->getAttribute('form');
    }
    elsif($tree->nrChildren==1)
    {   $tree->currentLocal eq 'simpleType'
            or error __x"attribute child can only be `simpleType', not `{found}' at {where}"
                  , found => $tree->currentLocal, where => $tree->path;

        $name       = $node->getAttribute('name')
            or error __x"attribute without name at {where}"
                   , where => $tree->path;

        $form       = $node->getAttribute('form');
        $type       = $self->simpleType($tree->descend);
    }

    else
    {   $name       = $node->getAttribute('name')
            or error __x"attribute without name or ref at {where}"
                   , where => $tree->path;

        $typeattr   = $node->getAttribute('type');
        $form       = $node->getAttribute('form');
    }

    my $where = $tree->path.'@'.$name;
    $self->assertType($where, name => NCName => $name);
    $self->assertType($where, type => QName => $typeattr)
        if $typeattr;

    my $path    = $tree->path . "/at($name)";

    unless($type)
    {    my $typename = defined $typeattr
          ? $self->rel2abs($path, $node, $typeattr)
          : $self->anyType($node);

         $type  = $self->typeByName($tree, $typename);
    }

    my $st      = $type->{st}
        or error __x"attribute not based in simple value type at {where}"
               , where => $where;

    my $qual
      = ! defined $form        ? $self->{attrs_qual}
      : $form eq 'qualified'   ? 1
      : $form eq 'unqualified' ? 0
      : error __x"form must be (un)qualified, not {form} at {where}"
            , form => $form, where => $where;

    my $trans   = $qual ? 'tag_qualified' : 'tag_unqualified';
    my $tag     = $self->make($trans => $path, $node, $name);
    my $ns      = $qual ? $self->{tns} : '';

    my $use     = $node->getAttribute('use') || '';
    $use =~ m/^(?:optional|required|prohibited|)$/
        or error __x"attribute use is required, optional or prohibited (not '{use}') at {where}"
               , use => $use, where => $where;

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
    ($name => $self->make($generate => $path, $ns, $tag, $st, $value));
}

sub attributeGroup($)
{   my ($self, $tree) = @_;

    # attributes: id, ref = QName
    # content: annotation?

    my $node  = $tree->node;
    my $where = $tree->path;
    my $ref   = $node->getAttribute('ref')
        or error __x"attributeGroup use without ref at {where}"
               , where => $tree->path;

    $self->assertType($where, ref => QName => $ref);

    my $typename = $self->rel2abs($where, $node, $ref);

    my $def  = $self->namespaces->find(attributeGroup => $typename)
        or error __x"cannot find attributeGroup {name} at {where}"
               , name => $typename, where => $where;

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

    $tree->nrChildren
        or error __x"empty complexType at {where}", where => $tree->path;

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
               , where => $tree->path;

    my $nest  = $tree->descend($first);
    return $self->simpleContent($nest)
        if $name eq 'simpleContent';

    return  $self->complexContent($nest)
        if $name eq 'complexContent';

    error __x"complexType contains particles, simpleContent, or complexContent, not '{name}' at {where}"
        , name => $name, where => $tree->path;
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
        and error __x"trailing non-attribute at {where}", where => $tree->path;

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
             , where => $tree->path;

    my $name  = $tree->currentLocal;
    return $self->simpleContentExtension($tree->descend)
        if $name eq 'extension';

    return $self->simpleContentRestriction($tree->descend)
        if $name eq 'restriction';

     error __x"simpleContent either extension or restriction, not `{name}' at {where}"
         , name => $name, where => $tree->path;
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
               , where => $where;
 
    $self->extendAttrs($basetype, $self->attributeList($tree));
    $tree->currentChild
        and error __x"elements left at tail at {where}"
                , where => $tree->path;

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
                   , where => $where;

        $first eq 'simpleType'
            or error __x"simpleType expected, because there is no base attribute at {where}"
                   , where => $where;

        $type = $self->simpleType($tree->descend);
        $tree->nextChild;
    }

    my $st = $type->{st}
        or error __x"not a simpleType in simpleContent/restriction at {where}"
               , where => $where;

    $type->{st} = $self->applySimpleFacets($tree, $st, 0);

    $self->extendAttrs($type, $self->attributeList($tree));

    $tree->currentChild
        and error __x"elements left at tail at {where}"
                , where => $where;

    $type;
}

sub complexContent($)
{   my ($self, $tree) = @_;

    # attributes: id, mixed = boolean
    # content: annotation?, (restriction | extension)

    my $node = $tree->node;
    $self->isTrue($node->getAttribute('mixed') || 'false')
        and warn "mixed content not supported" if $^W;
    
    $tree->nrChildren == 1
        or error __x"only one complexContent child expected at {where}"
               , where => $tree->path;

    my $name  = $tree->currentLocal;
 
    return $self->complexContentExtension($tree->descend)
        if $name eq 'extension';

    # nice for validating, but base can be ignored
    return $self->complexBody($tree->descend)
        if $name eq 'restriction';

    error __x"complexContent either extension or restriction, not '{name}' at {where}"
        , name => $name, where => $tree->path;
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
                   , type => $typename, where => $tree->path;

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

    my ($url, $local)
     = $type =~ m/^(.+?)\:(.*)/
     ? ($node->lookupNamespaceURI($1), $2)
     : ($node->lookupNamespaceURI(''), $type);

     defined $url
         or error __x"No namespace for type '{type}' at {where}"
                , type => $type, where => $where;

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
            if !$hook->{path} && !$hook->{id} && !$hook->{type};

        if(my $p = $hook->{path})
        {   $match++
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
        {   my $t     = $hook->{type};
            my $local = $type =~ m/^\{.*?\}(.*)$/ ? $1 : die $type;
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

=item output_namespaces HASH
The translator will create XML elements (WRITER) which use name-spaces,
based on its own name-space/prefix mapping administration.  This is
needed because the XML tree is formed bottom-up, where XML::LibXML
can only handle this top-down.

When your pass your own HASH as argument, you can explicitly specify
the prefixes you like to be used for which name-space.  Found name-spaces
will be added to the hash, as well the use count.  When a new name-space
URI is discovered, an attempt is made to use the prefix as found in the
schema. Prefix collisions are actively avoided: when two URIs want the
same prefix, a sequence number is added to one of them which makes it
unique.

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
