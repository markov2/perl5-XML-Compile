
# The code is this module is messy: sorry.  It needs a good rewrite.
# Gladly, a large number of tests guarentees at least most of the
# expected functionality.

use warnings;
use strict;

package XML::Compile::Schema::Translate;

use List::Util  'first';
use Carp;

use XML::Compile::Schema::Specs;
use XML::Compile::Schema::BuiltInFacets;
use XML::Compile::Schema::BuiltInTypes   qw/%builtin_types/;

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

This implementation is work in progress, but most structures in
W3C schema's are implemented.

Non-namespace schema elements are not implemented, because you shouldn't
want that!  Therefore, missing are
 schema noNamespaceSchemaLocation
 any ##local
 anyAttribute ##local

Some things do not work in schema's anyway:
 automatic import
 include

Used for indexing XML, not for our need:
 unique, keyref, selector, field

A few nuts are still to crack:
 any* processContents always interpreted as lax
 schema version
 element mixed
 facets on dates
 full understanding of patterns (now limited)
 final
 notation, annotation
 explicit ordering within choice and all
 QName writer namespace to prefix translation

Of course, the latter list is all fixed in next release ;-)
See chapter L</DETAILS> for more on how the tune the translator.

=chapter METHODS

=c_method compileTree ELEMENT, OPTIONS
Do not call this function yourself, but use
M<XML::Compile::Schema::compile()> (or wrappers around that).

This function returns a CODE reference, which can translate
between Perl datastructures and XML, based on a schema.  Before
this method is called is the schema already translated into
a table of types.

=requires nss L<XML::Compile::Schema::NameSpaces>

=requires bricks CLASS

=requires err CODE

=requires hooks ARRAY
=cut

sub compileTree($@)
{   my ($class, $element, %args) = @_;

    my $path   = $element;
    my $self   = bless \%args, $class;

    ref $element
        and $self->error($path, "expecting an element name as point to start");

    $self->{bricks}
        or $self->error($path, "no bricks");

    $self->{nss}
        or $self->error($path, "no namespaces");

    $self->{err}
        or $self->error($path, "no error handler");

    $self->{hooks}
        or $self->error($path, "no hooks defined");

    if(my $def = $self->namespaces->findID($element))
    {   my $node  = $def->{node};
        my $local = $node->localName;
        $local eq 'element'
            or $self->error($path, "$element is not an element");
        $element  = $def->{full};
    }

    my $make    = $self->element_by_name($path, $element);
    my $produce = $self->make(wrapper => $make);

      $self->{include_namespaces}
    ? $self->make(wrapper_ns => $path, $produce, $self->{output_namespaces})
    : $produce;
}

sub error($$@)
{   my ($self, $path) = (shift, shift);
    die 'ERROR: '.join('', @_)."\n  in $path\n";
}

sub assert_type($$$$)
{   my ($self, $path, $field, $type, $value) = @_;
    return if $builtin_types{$type}{check}->($value);
    $self->error($path,
        "Field $field contains '$value' which is not a valid $type.");
}

my $skip_tags = qr/^(?:notation|annotation|key|unique|keyref|selector|field)$/;
sub childs($)   # returns only elements in same name-space
{   my $self = shift;
    my $node = shift;
    my $ns   = $node->namespaceURI;
    grep {   $_->isa('XML::LibXML::Element')
          && $_->namespaceURI eq $ns
          && $_->localName !~ $skip_tags
         } $node->childNodes;
}

sub namespaces() { $_[0]->{nss} }

sub make($@)
{   my ($self, $component, $path, @args) = @_;
    no strict 'refs';
    "$self->{bricks}::$component"->($path, $self, @args);
}

sub element_by_name($$)
{   my ($self, $path, $element) = @_;
    my $nss    = $self->namespaces;
#warn "$element";
    my $top    = $nss->findElement($element)
       or $self->error($path, "cannot find element $element");

    my $node   = $top->{node};
    my $local  = $node->localName;
    $local eq 'element'
       or $self->error($path, "$element is not an element");

    local $self->{elems_qual} = exists $self->{elements_qualified}
     ? $self->{elements_qualified} : $top->{efd} eq 'qualified';
    local $self->{tns}        = $top->{ns};

    $self->element_by_node($path, $top->{node});
}

sub type_by_name($$$)
{   my ($self, $path, $node, $typename) = @_;

    #
    # First try to catch build-ins
    #

    my $code = XML::Compile::Schema::Specs->builtInType
       ($node, $typename, sloppy_integers => $self->{sloppy_integers});

    if($code)
    {
#warn "TYPE FINAL: $typename\n";
        my $c = $self->{check_values}? 'builtin_checked' : 'builtin_unchecked';
        my $type = $self->make($c => $path, $node, $typename, $code);

        return {st => $type};
    }

    #
    # Then try own schema's
    #

    my $top    = $self->namespaces->findType($typename)
       or $self->error($path, "cannot find type $typename");

    $self->type_by_top($path, $top);
}

sub type_by_top($$)
{   my ($self, $path, $top) = @_;
    my $node = $top->{node};

    #
    # Setup default name-space processing
    #

    my $elems_qual
     = exists $self->{elements_qualified} ? $self->{elements_qualified}
     : $top->{efd} eq 'qualified';

    my $attrs_qual
     = exists $self->{attributes_qualified} ? $self->{attributes_qualified}
     : $top->{afd} eq 'qualified';

    local $self->{elems_qual} = $elems_qual;
    local $self->{attrs_qual} = $attrs_qual;
    local $self->{tns}        = $top->{ns};
    my $local = $node->localName;

      $local eq 'simpleType'  ? $self->simpleType ($path, $node)
    : $local eq 'complexType' ? $self->complexType($path, $node)
    : $self->error($path, "expecting simpleType or complexType, not '$local'");
}

sub reference($$$)
{   my ($self, $path, $typename, $kind) = @_;

    my $nss    = $self->namespaces;
    my $top    = $nss->findElement($typename)
       or $self->error($path, "cannot find ref-type $typename for");

    my $node   = $top->{node};
    my $local  = $node->localname;
    $local eq $kind
       or $self->error($path, "$typename should refer to a $kind, not $local");

    $top;
}

sub simpleType($$$)
{   my ($self, $path, $node, $in_list) = @_;

    my @childs = $self->childs($node);
    @childs==1
       or $self->error($path, "simpleType must have only one child");

    my $child = shift @childs;
    my $local = $child->localName;

    my $type
    = $local eq 'restriction'
                        ? $self->simple_restriction($path, $child, $in_list)
    : $local eq 'list'  ? $self->simple_list($path, $child)
    : $local eq 'union' ? $self->simple_union($path, $child)
    : $self->error($path
        , "simpleType contains $local, must be restriction, list, or union\n");

    delete @$type{ qw/attrs attrs_any/ };
    $type;
}

sub simple_list($$)
{   my ($self, $path, $node) = @_;

    my $per_item;
    if(my $type = $node->getAttribute('itemType'))
    {   my $typename = $self->rel2abs($path, $node, $type);
        $per_item    = $self->type_by_name($path, $node, $typename);
    }
    else
    {   my @childs   = $self->childs($node);
        @childs==1
           or $self->error($path, "expected one simpleType child or itemType attribute");

        my $child    = shift @childs;
        my $local    = $child->localName;
        $local eq 'simpleType'
           or $self->error($path, "simple list container can only have simpleType");

        $per_item    = $self->simpleType($path, $child, 1);
    }

    my $st = $per_item->{st}
        or $self->error($path, "list must be of simple type");

    my $do = $self->make(list => $path, $st);

    $per_item->{st} = $do;
    $per_item->{is_list} = 1;
    $per_item;
}

sub simple_union($$)
{   my ($self, $path, $node) = @_;

    my @types;

    # Normal error handling switched off, and check_values must be on
    # When check_values is off, we may decide later to treat that as
    # string, which is faster but not 100% safe, where int 2 may be
    # formatted as float 1.999

    my $err = $self->{err};
    local $self->{err} = sub {undef}; #sub {warn "UNION no match @_\n"; undef};
    local $self->{check_values} = 1;

    if(my $members = $node->getAttribute('memberTypes'))
    {   foreach my $union (split " ", $members)
        {   my $typename = $self->rel2abs($path, $node, $union);
            my $type = $self->type_by_name($path, $node, $typename);
            my $st   = $type->{st}
               or $self->error($path, "union only of simpleTypes");

            push @types, $st;
        }
    }

    foreach my $child ( $self->childs($node))
    {   my $local = $child->localName;

        $local eq 'simpleType'
           or $self->error($path, "only simpleType's within union");

        my $ctype = $self->simpleType($path, $child, 0);
        push @types, $ctype->{st};
    }

    my $do = $self->make(union => $path, $err, @types);
    { st => $do, is_union => 1 };
}

sub simple_restriction($$$)
{   my ($self, $path, $node, $in_list) = @_;
    my $base;

    if(my $basename = $node->getAttribute('base'))
    {   my $typename = $self->rel2abs($path, $node, $basename);
        $base        = $self->type_by_name($path, $node, $typename);
        defined $base->{st}
           or $self->error($path, "base $basename for simple-restriction is not simpleType");
    }

    # Collect the facets

    my (%facets, @attr_nodes);
  FACET:
    foreach my $child ( $self->childs($node))
    {   my $facet = $child->localName;

        if($facet eq 'simpleType')
        {   $base = $self->type_by_name("$path/st", $child, $facet);
            next FACET;
        }

        if($facet eq 'attribute' || $facet eq 'anyAttribute')
        {   push @attr_nodes, $child;
            next FACET;
        }

        my $value = $child->getAttribute('value');
        defined $value
           or $self->error($path, "no value for facet $facet");

           if($facet eq 'enumeration') { push @{$facets{enumeration}}, $value }
        elsif($facet eq 'pattern')     { push @{$facets{pattern}}, $value }
        elsif(exists $facets{$facet})
        {   $self->error($path, "facet $facet defined twice") }
        else
        {   $facets{$facet} = $value }
    }

    defined $base
       or $self->error($path, "simple-restriction requires either base or simpleType");

    my @attrs_def = $self->attribute_list($path, @attr_nodes);

    my $st = $base->{st};
    return { st => $st, @attrs_def }
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
        push @early, builtin_facet($path, $self, $ordered, $limit)
           if defined $limit;
    }

    my @late;
    foreach my $unordered (keys %facets)
    {   push @late, builtin_facet($path, $self, $unordered, $facets{$unordered});
    }

    my $do = $in_list
           ? $self->make(facets_list => $path, $st, \@early, \@late)
           : $self->make(facets => $path, $st, @early, @late);

   {st => $do, @attrs_def};
}

sub substitutionGroupElements($$)
{   my ($self, $path, $node) = @_;

    # type is ignored: only used as documentation

    my $name     = $node->getAttribute('name')
       or $self->error($path, "substitutionGroup element needs name");
    $self->assert_type($path, name => NCName => $name);

    $path       .= "/sg($name)";

    my $tns     = $self->{tns};
    my $absname = "{$tns}$name";
    my @subgrps = $self->namespaces->findSgMembers($absname);
    @subgrps
       or $self->error($path, "no substitutionGroups found for $absname");

    map { $_->{node} } @subgrps;
}

sub element_by_node($$)
{   my ($self, $path, $node) = @_;
#warn "element: $path\n";

    my @childs   = $self->childs($node);

    my $name     = $node->getAttribute('name')
        or $self->error($path, "element has no name");
    $self->assert_type($path, name => NCName => $name);
    $path       .= "/el($name)";
#warn "element: $path\n", $node->toString;

    my $qual     = $self->{elems_qual};
    if(my $form = $node->getAttribute('form'))
    {   $qual = $form eq 'qualified'   ? 1
              : $form eq 'unqualified' ? 0
              : $self->error($path, "form must be (un)qualified, not $form");
    }

    my $trans    = $qual ? 'tag_qualified' : 'tag_unqualified';
    my $tag      = $self->make($trans => $path, $node, $name);

    my ($typename, $type);
    if(my $isa = $node->getAttribute('type'))
    {   @childs
            and $self->error($path, "no childs expected for type");

        $typename = $self->rel2abs($path, $node, $isa);
        $type     = $self->type_by_name($path, $node, $typename);
    }
    elsif(!@childs)
    {   $typename = $self->anyType($node);
        $type     = $self->type_by_name($path, $node, $typename);
    }
    else
    {   @childs > 1
           and $self->error($path, "expected is only one child");
 
        # nameless types
        my $child = $childs[0];
        my $local = $child->localname;
        $type
         = $local eq 'simpleType'  ? $self->simpleType($path, $child, 0)
         : $local eq 'complexType' ? $self->complexType($path, $child)
         : $self->error($path, "unexpected element child $local");
    }

    my $attrs     = $type->{attrs}     || [];
    my $attrs_any = $type->{attrs_any} || [];
    my $elems     = $type->{elems}     || [];
    my $elems_any = $type->{elems_any} || [];

    my ($before, $replace, $after)
        = $self->findHooks($path, $typename, $node);

    my $r;
    if($replace) { ; }              # overrule processing
    elsif(!$type->{st})             # complexType (complexContent)
    {   my @do = @$elems;
        push @do, @$attrs if $attrs;

        $r = $self->make(create_complex_element => $path, $tag, \@do,
            $elems_any, $attrs_any);
    }
    elsif(@$attrs || @$attrs_any)   # complex simpleContent
    {   $r = $self->make(create_tagged_element =>
           $path, $tag, $type->{st}, $attrs, $attrs_any);
    }
    else                            # simple
    {   $r = $self->make(create_simple_element => $path, $tag, $type->{st});
    }

    return $r unless $before || $replace || $after;

    $self->make(create_hook => $path, $r, $before, $replace, $after);
}

sub particles($$$$)
{   my ($self, $path, $node, $min, $max) = @_;
#warn "Particles ".$node->localName;
    my %h;
    foreach my $child ($self->childs($node))
    {   my $p = $self->particle($path, $child, $min, $max);
        push @{$h{elems}},     @{$p->{elems}}     if $p->{elems};
        push @{$h{elems_any}}, @{$p->{elems_any}} if $p->{elems_any};
    }
    \%h;
}

sub particle($$$$);
sub particle($$$$)
{   my ($self, $path, $node, $min_default, $max_default) = @_;

    my $local = $node->localName;
    my $min   = $node->getAttribute('minOccurs');
    my $max   = $node->getAttribute('maxOccurs');

#warn "Particle: $local\n";
#warn "PARTICLE $local: \n",$node->toString;
    my @do;

    if($local eq 'sequence' || $local eq 'choice' || $local eq 'all')
    {   defined $min or $min = $local eq 'choice' ? 0 : ($min_default || 1);
        defined $max or $max = ($max_default || 1);
        return $self->particles($path, $node, $min, $max)
    }

    if($local eq 'group')
    {   my $ref = $node->getAttribute('ref')
           or $self->error($path, "group without ref");

        $path     .= "/gr";
        my $typename = $self->rel2abs($path, $node, $ref);
#warn $typename;

        my $dest   = $self->reference("$path/gr", $typename, 'group');
        return $self->particles($path, $dest->{node}, $min, $max);
    }

    if($local eq 'any')
    {   return {elems_any => [$self->any_element($path, $node, $min, $max)]};
    }

    if($local ne 'element')
    {   $self->error($path, "unknown particle type '$local'");
        return undef;
    }

    defined $min or $min = $min_default;
    defined $max or $max = $max_default;

    if(my $ref =  $node->getAttribute('ref'))
    {   my $refname = $self->rel2abs($path, $node, $ref);
        my $def     = $self->reference($path, $refname, 'element');
        $node       = $def->{node};

        my $abstract = $node->getAttribute('abstract') || 'false';
        if($abstract eq 'true')
        {   my %h;
            foreach my $e ($self->substitutionGroupElements($path, $node))
            {   my $p = $self->particle($path, $e, 0, 1);
                push @{$h{elems}},     @{$p->{elems}}     if $p->{elems}; 
                push @{$h{elems_any}}, @{$p->{elems_any}} if $p->{elems_any}; 
            }
            return \%h;
        }
    }

    my $name = $node->getAttribute('name');
    defined $name
        or $self->error($path, "missing name for element");
#warn "    is element $name";

    my $do   = $self->element_by_node($path, $node);

    my $nillable = 0;
    if(my $nil = $node->getAttribute('nillable'))
    {    $nillable = $nil eq 'true';
    }

    my $default = $node->getAttributeNode('default');
    my $fixed   = $node->getAttributeNode('fixed');

    my $generate
     = ($max eq 'unbounded' || $max > 1)
     ? ( $self->{check_occurs}
       ? 'element_repeated'
       : 'element_array'
       )
     : ($self->{check_occurs} && $min>=1)
     ? ( $nillable        ? 'element_nillable'
       : defined $default ? 'element_default'
       : defined $fixed   ? 'element_fixed'
       :                    'element_obligatory'
       )
     : ( defined $default ? 'element_default'
       : defined $fixed   ? 'element_fixed_optional'
       :                    'element_optional'
       );

    my $value = defined $default ? $default : $fixed;
    my $ns    = $node->namespaceURI;

    { elems => [$name => $self->make($generate => "$path/$name"
    , $ns, $name, $do, $min,$max, $value)]};
}

sub attribute($$)
{   my ($self, $path, $node) = @_;

    my($ref, $name, $form, $typeattr);
    if(my $refattr =  $node->getAttribute('ref'))
    {   my $refname = $self->rel2abs($path, $node, $refattr);
        my $def     = $self->reference($path, $refname, 'attribute');
        $ref        = $def->{node};

        $name       = $ref->getAttribute('name')
           or $self->error($path, "ref attribute without name");

        $typeattr   = $ref->getAttribute('type');
        $form       = $ref->getAttribute('form');
    }
    else
    {   $name       = $node->getAttribute('name')
           or $self->error($path, "attribute without name or ref");

        $typeattr   = $node->getAttribute('type');
        $form       = $node->getAttribute('form');
    }

    $path   .= "/at($name)";

    my $qual = $self->{attrs_qual};

    if($form)
    {   $qual = $form eq 'qualified'   ? 1
              : $form eq 'unqualified' ? 0
              : $self->error($path, "form must be (un)qualified, not $form");
    }

    my $trans = $qual ? 'tag_qualified' : 'tag_unqualified';
    my $tag   = $self->make($trans => $path, $node, $name);
    my $ns    = $qual ? $self->{tns} : '';

    my $typename = defined $typeattr
     ? $self->rel2abs($path, $node, $typeattr)
     : $self->anyType($node);

    my $type     = $self->type_by_name($path, $node, $typename);
    my $st       = $type->{st}
        or $self->error($path, "attribute not based in simple value type");

    my $use     = $node->getAttribute('use') || '';
    $self->error($path
      , "attribute use is required, optional or prohibited (not '$use')")
       if $use !~ m/^(?:optional|required|prohibited|)$/;

    my $default = $node->getAttributeNode('default');
    my $fixed   = $node->getAttributeNode('fixed');

    my $generate
     = defined $default    ? 'attribute_default'
     : defined $fixed
     ? ($use eq 'optional' ? 'attribute_fixed_optional' : 'attribute_fixed')
     : $use eq 'required'  ? 'attribute_required'
     : $use eq 'prohibited'? 'attribute_prohibited'
     :                       'attribute_optional';

    my $value = defined $default ? $default : $fixed;
    $name => $self->make($generate => $path, $ns, $tag, $st, $value);
}

sub attribute_group($$)
{   my ($self, $path, $node) = @_;

    my $ref  = $node->getAttribute('ref')
       or $self->error($path, "attributeGroup use without ref");

    $path   .= "/ag";
    my $typename = $self->rel2abs($path, $node, $ref);
#warn $typename;

    my $def  = $self->reference($path, $typename, 'attributeGroup');
    defined $def or return ();

    $self->attribute_list($path, $self->childs($def->{node}));
}

sub attribute_list($@)
{   my ($self, $path) = (shift, shift);
    my (@attrs, @any);

    foreach my $attr (@_)
    {   my $local = $attr->localName;
        if($local eq 'attribute')
        {   push @attrs, $self->attribute($path, $attr);
            next;
        }

        my %attrs
         = $local eq 'attributeGroup' ? $self->attribute_group($path, $attr)
         : $local eq 'anyAttribute'   ? $self->any_attribute($path, $attr)
         : $self->error($path
             , "expected is attribute(Group) not '$local'. Forgot <sequence>?");

        push    @attrs, @{$attrs{attrs}     || []};
        unshift @any,   @{$attrs{attrs_any} || []};
    }

    (attrs => \@attrs, attrs_any => \@any);
}

# Don't known how to handle notQName
sub any_attribute($$)
{   my ($self, $path, $node) = @_;
    my $handler   = $self->{anyAttribute};
    my $namespace = $node->getAttribute('namespace')       || '##any';
    my $not_ns    = $node->getAttribute('notNamespace');
    my $process   = $node->getAttribute('processContents') || 'strict';

    my ($yes, $no) = $self->translate_ns_limits($namespace, $not_ns);
    my $do = $self->make(anyAttribute => $path, $handler, $yes, $no, $process);
    defined $do ? (attrs_any => [$do]) : ();
}

sub any_element($$$$)
{   my ($self, $path, $node, $min, $max) = @_;
    my $handler   = $self->{anyElement};
    my $namespace = $node->getAttribute('namespace')       || '##any';
    my $not_ns    = $node->getAttribute('notNamespace');
    my $process   = $node->getAttribute('processContents') || 'strict';

    my ($yes, $no) = $self->translate_ns_limits($namespace, $not_ns);
    $self->make(anyElement => $path, $handler, $yes,$no, $process, $min,$max);
}

# namespace    = (##any|##other) | List of (anyURI|##targetNamespace|##local)
# notNamespace = List of (anyURI |##targetNamespace|##local)
# handling of ##local ignored: only full namespaces are supported
sub translate_ns_limits($$)
{   my ($self, $include, $exclude) = @_;

    my $tns       = $self->{tns};
    return (undef, [])     if $include eq '##any';
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

sub complexType($$)
{   my ($self, $path, $node) = @_;

    my @childs = $self->childs($node);
    @childs or $self->error($path, "empty complexType");

    my $first  = shift @childs;
    my $local  = $first->localName;

    if($local eq 'simpleContent')
    {   @childs
            and $self->error($path,"$local must be alone in complexType");

        return $self->simpleContent($path, $first);
    }

    my $type;
    if($local eq 'complexContent')
    {   @childs
            and $self->error($path,"$local must be alone in complexType");

        return $self->complexContent($path, $first);
    }

    $self->complex_body($path, $node);
}

sub complex_body($$)
{   my ($self, $path, $node) = @_;

    my @childs = $self->childs($node);

    my $first  = $childs[0]
        or return {};

    my $local  = $first->localName;

    my $elems;
    if($local =~ m/^(?:sequence|choice|all|group)$/)
    {   $elems = $self->particle($path, $first, 1, 1);
        shift @childs;
    }

   +{ ($elems ? %$elems : ())
    , $self->attribute_list($path, @childs)
    };
}

sub simpleContent($$)
{   my ($self, $path, $node) = @_;

    my @elems;
    my @childs = $self->childs($node);
    @childs == 1
      or $self->error($path, "only one simpleContent child");

    my $child  = shift @childs;
    my $name = $child->localName;
 
    return $self->simpleContent_ext($path, $child)
        if $name eq 'extension';

    # nice for validating, but base can be ignored
    return $self->simpleContent_res($path, $child)
        if $name eq 'restriction';

    $self->error($path
     , "simpleContent either extension or restriction, not '$name'");
}

sub simpleContent_ext($$)
{   my ($self, $path, $node) = @_;

    my $base     = $node->getAttribute('base');
    my $typename = defined $base ? $self->rel2abs($path, $node, $base)
     : $self->anyType($node);

    my $basetype = $self->type_by_name("$path#base", $node, $typename);
    my $st = $basetype->{st}
        or $self->error($path, "base of simpleContent not simple");
 
    my @attrs    = @{$basetype->{attrs}     || []};
    my @attrs_any= @{$basetype->{attrs_any} || []};
    my @childs   = $self->childs($node);

    my %additional = $self->attribute_list($path, @childs);
    push @attrs,        @{$additional{attrs}};
    unshift @attrs_any, @{$additional{attrs_any}};
    
    {st => $st, attrs => \@attrs, attrs_any => \@attrs_any};
}

sub simpleContent_res($$)
{   my ($self, $path, $node) = @_;
    my $type = $self->simple_restriction($path, $node, 0);

    my $st    = $type->{st}
       or $self->error($path, "not a simpleType in simpleContent/restriction");

    $type;
}

sub complexContent($$)
{   my ($self, $path, $node) = @_;

    my @elems;
    my @childs = $self->childs($node);
    @childs == 1
      or $self->error($path, "only one complexContent child");

    my $child  = shift @childs;
    my $name = $child->localName;
 
    return $self->complexContent_ext($path, $child)
        if $name eq 'extension';

    # nice for validating, but base can be ignored
    return $self->complex_body($path, $child)
        if $name eq 'restriction';

    $self->error($path
     , "complexContent either extension or restriction, not '$name'");
}

sub complexContent_ext($$)
{   my ($self, $path, $node) = @_;

    my $base = $node->getAttribute('base') || 'anyType';
    my $type = {};

    if($base ne 'anyType')
    {   my $typename = $self->rel2abs($path, $node, $base);
        my $typedef  = $self->namespaces->findType($typename)
            or $self->error($path, "cannot base on unknown $base");

        $typedef->{type} eq 'complexType'
            or $self->error($path, "base $base not complexType");

        $type = $self->complexType($path, $typedef->{node});
    }

    my $own = $self->complex_body($path, $node);
    push    @{$type->{elems}},     @{$own->{elems}}     if $own->{elems};
    push    @{$type->{elems_any}}, @{$own->{elems_any}} if $own->{elems_any};
    push    @{$type->{attrs}},     @{$own->{attrs}}     if $own->{attrs};
    unshift @{$type->{attrs_any}}, @{$own->{attrs_any}} if $own->{attrs_any};
    $type;
}

#
# Helper routines
#

# print $self->rel2abs($path, $node, '{ns}type')    ->  '{ns}type'
# print $self->rel2abs($path, $node, 'prefix:type') ->  '{ns(prefix)}type'

sub rel2abs($$$)
{   my ($self, $path, $node, $type) = @_;
    return $type if substr($type, 0, 1) eq '{';

    my ($url, $local)
     = $type =~ m/^(.+?)\:(.*)/
     ? ($node->lookupNamespaceURI($1), $2)
     : ($node->lookupNamespaceURI(''), $type);

     defined $url
         or $self->error($path, "No namespace for type '$type'");

     "{$url}$local";
}

sub anyType($)
{   my ($self, $node) = @_;
    my $ns = $node->namespaceURI;
    "{$ns}anyType";
}

sub findHooks($$$)
{   my ($self, $path, $type, $node) = @_;
    # where is before, replace, after

    my %hooks;
    foreach my $hook (@{$self->{hooks}})
    {   my $match;
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

The produced XML may not use the name-spaces as defined by the schema's,
just to simplify the input and output.  The structural definition of
the schema's is still in-tact, but name-space collission may appear.

Per schema, it can be specified whether the elements and attributes
defined in-there need to be used qualified (with prefix) or not.
This can cause horrible output when within an unqualified schema
elements are used from an other schema which is qualified.

The suggested solution in articles about the subject is to provide
people with both a schema which is qualified as one which is not.
Perl is known to be blunt in its approach: we simply define a flag
which can force one of both on all schema's together, using
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
=cut

1;
