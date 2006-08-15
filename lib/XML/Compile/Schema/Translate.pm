
use warnings;
use strict;

package XML::Compile::Schema::Translate;
use base 'Exporter';

our @EXPORT = 'compile_tree';

use Carp;

use XML::Compile::Schema::Specs;
use XML::Compile::Schema::BuiltInFacets;
use XML::Compile::Schema::BuiltInTypes   qw/%builtin_types/;

sub _rel2abs($$);

=chapter NAME

XML::Compile::Schema::Translate - create an XML data parser

=chapter SYNOPSIS

 # for internal use only!

=chapter DESCRIPTION

This module converts a schema type definition into a code
reference which can be used to interpret a schema.  The sole public
function in this package is M<compile_tree()>, and is called by
M<XML::Compile::Schema::compile()>, which does a lot of set-ups.
Please do not try to use this package directly!

The code in this package interprets schemas; it understands, for
instance, how complexType definitions work.  Then, when the
schema syntax is decoded, it will knot the pieces together into
one CODE reference which can be used in the main user program.

=section Unsupported features

This implementation is work in progress, but most structures in
W3C schema's are implemented.  A few nuts are still to crack:
 schema schemaLocation
 schema noNamespaceSchemaLocation
 schema version
 element mixed
 facets on dates
 limited understanding of patterns
 import
 include
 anyAttribute
 group minOccurs maxOccurs
 final and abstract
 substitutionGroup
 unique, keyref, selector, field, include, notation

Of course, these are all fixed in next release ;-)

=section Rules of translation

The following rules are used during translation, applicable to
both the reader as the writer:

=over 4

=item Encoding

this module uses XML::LibXML which does the character encoding for
us: you do not have to escape characters like E<lt> yourself.

=item Nesting

Elements can be complex, and themselve contain elements which
are complex.  In the Perl representation of the data, this will
be shown as nested hashes with the same structure as the XML.

=item Arrays

Any element which has a maxOccurs larger than 1 will be returned
as an array (or undef).  This will avoid the situation where the
user code only handles a single element instance where the schema
defines that multiple values can be returned.  The same is true
for list types.

=item Schema validation

Be warned that the schema itself is NOT VALIDATED; you can easily
construct schema's which do work with this module, but are not
valid according to W3C.  Only in some cases, the translater will
refuse to accept mistakes: mainly because it cannot produce valid
code.

=item Value checking

The code will do its best to produce a correct translation. For
instance, an accidental C<1.9999> will be converted into C<2>
when the schema says that the field is an C<int>.

=back

=section Performance optimization

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

=section Qualified XML

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

=section Name-spaces

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

=chapter FUNCTIONS

=c_method compile_tree TYPENAME, OPTIONS
Do not call this function yourself, but use
M<XML::Compile::Schema::compile()> (or wrappers around that).

This function returns a CODE reference, which can translate
between Perl datastructures and XML, based on a schema.  Before
this method is called is the schema already translated into
a table of types.

=required nss M<XML::Compile::Schema::NameSpaces>

=cut

sub compile_tree($@)
{   my ($typename, %args) = @_;

    ref $typename
       and croak 'ERROR: expecting a type name as point to start';
 
    my $processor = _final_type($args{path}, \%args, $typename);
    defined $processor or return ();

    my $produce   = $args{run}{wrapper}->($processor);

      $args{include_namespaces}
    ? $args{run}{wrapper_ns}->($produce, $args{output_namespaces})
    : $produce;
}

sub _assert_type($$$$)
{   my ($path, $field, $type, $value) = @_;
    return if $builtin_types{$type}{check}->($value);
    die "ERROR: Field $field contains `$value' which is not a valid $type.\n";
}

sub _final_type($$$)
{   my ($path, $args, $typename) = @_;

    #
    # Is a built-in type?  Special handlers
    #

    my $code = XML::Compile::Schema::Specs->builtInType
       ($typename, sloppy_integers => $args->{sloppy_integers});

    if($code)
    {
#warn "TYPE FINAL: $typename\n";
       return $args->{run}
         ->{$args->{check_values} ? 'builtin_checked' : 'builtin_unchecked'}
         ->($path, $args, $typename, $code);
    }

    #
    # Not a built-in type: a bit more work to do.
    #

    my $nss    = $args->{nss};
    my $top    = $nss->findID($typename)
              || $nss->findElement($typename)
              || $nss->findType($typename)
       or croak "ERROR: cannot find $typename for $path\n";

    my $node   = $top->{node};

    my $ns     = $node->namespaceURI;
    my $schema = XML::Compile::Schema::Specs->predefinedSchema($ns);
    defined $schema
       or croak "ERROR: $typename not in a predefined schema namespace";

    my $elems_qual
     = exists $args->{elements_qualified} ? $args->{elements_qualified}
     : $top->{efd} eq 'qualified';

    my $attrs_qual
     = exists $args->{attributes_qualified} ? $args->{attributes_qualified}
     : $top->{afd} eq 'qualified';

#warn "TYPE: $typename\n";
    my $label  = $top->{name};
    my $name   = $node->localname;

    local $args->{tns}        = $top->{ns};
    local $args->{elems_qual} = $elems_qual;
    local $args->{attrs_qual} = $attrs_qual;

    if($name eq 'simpleType')
    {   return _simpleType($path, $args, $node) }
    elsif($name eq 'complexType')
    {   return _complexType($path, $args, $node) }
    elsif($name eq 'element')
    {   return _element($path, $args, $node) }

    if($name eq 'group' || $name eq 'attributeGroup')
    {   croak "ERROR: $name is not a final type, only for reference\n" }
    else
    {   croak "ERROR: $name is not understood as final type\n" }
}

sub _ref_type($$$$)
{   my ($path, $args, $typename, $name) = @_;

    my $nss    = $args->{nss};
    my $top    = $nss->findElement($typename)
       or croak "ERROR: cannot find ref-type $typename for $path\n";

    my $node   = $top->{node};
    my $local  = $node->localname;
    if($local ne $name)
    {   croak "ERROR: $path $typename should refer to a $name, not a $local";
    }
  
    $node;
}

sub _simpleType($$$)
{   my ($path, $args, $node) = @_;
#warn "simpleType $path\n";
    my $ns   = $node->namespaceURI;

    foreach my $child ($node->childNodes)
    {   next unless $child->isa('XML::LibXML::Element');
        next if $child->namespaceURI ne $ns;

        my $local = $child->localName;
        next if $local eq 'notation';

        return
        $local eq 'restriction' ? _simple_restriction($path, $args, $child)
      : $local eq 'list'        ? _simple_list($path, $args, $child)
      : $local eq 'union'       ? _simple_union($path, $args, $child)
      : die "ERROR: do not understand simpleType component $local in $path\n";
    }

    die "ERROR: no definition in simpleType in $path\n";
}

sub _simple_list($$$)
{   my ($path, $args, $node) = @_;

    my $ns   = $node->namespaceURI;
    my $per_item;
    if(my $type = $node->getAttribute('itemType'))
    {   my $typename = _rel2abs($node, $type);
        $per_item    = _final_type($path, $args, $typename);
    }
    elsif(my @nodes = $node->getChildrenByTagNameNS($ns,'simpleType'))
    {   die "ERROR: only one simpleType within list" if @nodes > 1;
        $per_item    = _simpleType($path, $args, $nodes[0]);
    }
    else
    {   die "ERROR: list requires itemType attribute or simpleType in $path\n";
    }

    $args->{run}{list}->($path, $args, $per_item);
}

sub _simple_union($$$)
{   my ($path, $args, $node) = @_;
    my $ns   = $node->namespaceURI;

    my @types;

    # Normal error handling switched off, and check_values must be on
    # When check_values is off, we may decide later to treat that as
    # string, which is faster but not 100% safe, where int 2 may be
    # formatted as float 1.999

    my $err = $args->{err};
    local $args->{err} = sub {undef}; #sub {warn "UNION no match @_\n"; undef};
    local $args->{check_values} = 1;

    if(my $members = $node->getAttribute('memberTypes'))
    {   foreach my $type (split " ", $members)
        {   my $typename = _rel2abs($node, $type);
            push @types, _final_type($path, $args, $typename);
        }
    }

    foreach my $child ($node->childNodes)
    {   next unless $child->isa('XML::LibXML::Element');
        next if $child->namespaceURI ne $ns;

        my $local = $child->localName;
        next if $local eq 'notation';

        die "ERROR: only simpleType's within union in $path\n"
            if $local ne 'simpleType';

        push @types, _simpleType($path, $args, $child);
    }

    $args->{run}{union}->($path, $args, $err, @types);
}

sub _simple_restriction($$$)
{   my ($path, $args, $node) = @_;
    my $ns = $node->namespaceURI;
    my $st;

    if(my $base = $node->getAttribute('base'))
    {   my $typename = _rel2abs($node, $base);
        $st = _final_type($path, $args, $typename);
    }
    elsif($base = $node->getChildrenByTagNameNS($ns,'simpleType'))
    {   # untested
        $st = _simpleType("$path/st", $args, $base);
    }
    else
    {   die "ERROR: restriction $path requires either base or simpleType\n";
    }

    return $st if $args->{ignore_facets};

    # Collect the facets

    my @childs = grep {$_->isa('XML::LibXML::Element')} $node->childNodes;
    return $st unless @childs;

    my %facets;
    foreach my $child (@childs)
    {   next unless $child->namespaceURI eq $ns;
        my $facet = $child->localName;
        my $value    = $child->getAttribute('value');
        defined $value or die "ERROR: no value for $facet in $path\n";

           if($facet eq 'enumeration') { push @{$facets{enumeration}}, $value }
        elsif($facet eq 'pattern')     { push @{$facets{pattern}}, $value }
        elsif(exists $facets{$facet})
        {   die "ERROR: facet $facet defined twice in $path\n" }
        else
        {   $facets{$facet} = $value }
    }

    if(defined $facets{totalDigits} && defined $facets{fractionDigits})
    {   my $td = delete $facets{totalDigits};
        my $fd = delete $facets{fractionDigits};
        $facets{totalFracDigits} = [$td, $fd];
    }

    # First the strictly ordered facets, then the other facets
    my @rules;

    foreach my $facet ( qw/whiteSpace pattern/ )
    {   my $value = delete $facets{$facet};
        push @rules, builtin_facet($path, $args, $facet, $value)
           if defined $value;
    }

    # <list> types need to split here

    foreach my $facet (keys %facets)
    {   push @rules, builtin_facet($path, $args, $facet, $facets{$facet});
    }

      @rules==0 ? $st
    : @rules==1 ? _call_facet($st, $rules[0])
    :             _call_facets($st, @rules);
}

sub _call_facet($$)
{   my ($st, $facet) = @_;
    sub { my $v = $st->(@_);
          defined $v ? $facet->($v) : $v;
        };
}

sub _call_facets($@)
{   my ($st, @facets) = @_;
    sub { my $v = $st->(@_);
          for(@facets) {defined $v or last; $v = $_->($v)}
          $v;
        };
}

sub _element($$$)
{   my ($path, $args, $node) = @_;
#warn "element: $path\n";

    my $do;
    my @childs   = grep {$_->isa('XML::LibXML::Element')} $node->childNodes;
    if(my $ref = $node->getAttribute('ref'))
    {   @childs and warn "ERROR: no childs expected with ref in $path\n";
        my $typename = _rel2abs($node, $ref);
        my $dest     = _ref_type($path, $args, $typename, 'element')
           or return ();
        $path       .= "/ref($ref)";
        return _final_type($path, $args, $typename);
    }

    my $name     = $node->getAttribute('name')
       or croak "ERROR: element $path without name";
    _assert_type($path, name => NCName => $name);
    $path       .= "/el($name)";

    my $qual     = $args->{elems_qual};
    if(my $form = $node->getAttribute('form'))
    {   $qual = $form eq 'qualified'   ? 1
              : $form eq 'unqualified' ? 0
              : croak "ERROR: form must be (un)qualified, not $form";
    }

    my $trans    = $qual ? 'tag_qualified' : 'tag_unqualified';
    my $tag      = $args->{run}{$trans}->($args, $node, $name);

    if(my $type = $node->getAttribute('type'))
    {   @childs and warn "ERROR: no childs expected with type in $path\n";
        my $typename = _rel2abs($node, $type);
        $do = _final_type($path, $args, $typename);
    }
    elsif(!@childs)
    {   my $typename = _rel2abs($node, 'anyType');
        $do = _final_type($path, $args, $typename);
    }
    else
    {   @childs > 1
           and die "ERROR: expected is only one child in $path\n";
 
        # nameless types
        my $child = $childs[0];
        my $local = $child->localname;
        $do = $local eq 'simpleType'  ? _simpleType($path, $args, $child)
            : $local eq 'complexType' ? _complexType($path, $args, $child)
            : $local =~ m/^(sequence|choice|all|group)$/
            ?                           _complexType($path, $args, $child)
            : die "ERROR: unexpected element child $local at $path\n";
    }

    $args->{run}{create_element}->($path, $args, $tag, $do);
}

sub _choice($$$)
{   my ($path, $args, $node) = @_;
    my $min = $node->getAttribute('minOccurs');
    my $max = $node->getAttribute('maxOccurs');
    defined $min or $min = 0;
    defined $max or $max = 1;

    # sloppy: sum should not exceed max, we let each to max.
    # nested sequences not supported correctly
    map {_particle($path, $args, $_, $min, $max, 0, $max)}
       grep {$_->isa('XML::LibXML::Element')}
           $node->childNodes;
}

sub _particle($$$$$$$)
{   my ( $path, $args, $node, $min_default, $max_default
       , $min_perm, $max_perm) = @_;

    my $ns     = $node->namespaceURI;
    my @childs = $node;
    my @do;

    while(my $child = shift @childs)
    {   next unless $child->isa('XML::LibXML::Element');
        next if $child->namespaceURI ne $ns;
        my $name = $child->localName;

        if($name eq 'sequence')
        {   unshift @childs, $child->childNodes;
            next;
        }

        if($name eq 'group')
        {   unshift @childs, _group_particle($path, $args, $child);
            next;
        }

        if($name eq 'choice')
        {   push @do, _choice($path, $args, $child);
            next;
        }
        # 'all' is not permitted

        next if $name ne 'element';

        my $do = _element($path, $args, $child);
        my $childname = $child->getAttribute('name');

        my $min = $child->getAttribute('minOccurs');
        my $max = $child->getAttribute('maxOccurs');
        defined $min or $min = $min_default;
        defined $max or $max = $max_default;

        if($args->{check_occurs})
        {  $min >= $min_perm
              or croak "ERROR: element min-occur $min below permitted $min_perm\n";

           $max_perm eq 'unbounded' || $max ne 'unbounded' || $max <= $max_perm
              or croak "ERROR: element max-occur $max larger than permitted $max_perm\n";
        }
 
        my $nillable = 0;
        if(my $nil = $child->getAttribute('nillable'))
        {    $nillable = $nil eq 'true';
        }

        my $default = $child->getAttributeNode('default');
        my $fixed   = $child->getAttributeNode('fixed');

        my $generate
         = ($max eq 'unbounded' || $max > 1)
         ? ( $args->{check_occurs}
           ? 'element_repeated'
           : 'element_array'
           )
         : ($args->{check_occurs} && $min==1)
         ? ( $nillable      ? 'element_nillable'
           : defined $fixed ? 'element_fixed'
           :                  'element_obligatory'
           )
         : ( defined $default ? 'element_default'
           : defined $fixed   ? 'element_fixed'
           : 'element_optional'
           );

        my $value = defined $default ? $default : $fixed;

        push @do, $childname => 
           $args->{run}{$generate}
                ->("$path/$childname", $args, $ns, $childname, $do
                  , $min, $max, $value);
    }

    @do;
}

sub _attribute($$$)
{   my ($path, $args, $node) = @_;

    my $name = $node->getAttribute('name')
       or croak "ERROR: attribute $path without name";

    $path   .= "/at($name)";

    my $qual = $args->{attrs_qual};
    if(my $form = $node->getAttribute('form'))
    {   $qual = $form eq 'qualified'   ? 1
              : $form eq 'unqualified' ? 0
              : croak "ERROR: form must be (un)qualified, not $form";
    }

    my $trans    = $qual ? 'tag_qualified' : 'tag_unqualified';
    my $tag  = $args->{run}{$trans}->($args, $node, $name);

    my $do;
    if(my $type = $node->getAttribute('type'))
    {   my $typename = _rel2abs($node, $type);
        $do = _final_type($path, $args, $typename);
    }
    else
    {   die "attribute without type in $path\n";
    }

    my $use     = $node->getAttribute('use') || 'optional';
    my $default = $node->getAttributeNode('default');
    my $fixed   = $node->getAttributeNode('fixed');

    my $generate
     = defined $default    ? 'attribute_default'
     : defined $fixed      ? 'attribute_fixed'
     : $use eq 'required'  ? 'attribute_required'
     : $use eq 'optional'  ? 'attribute_optional'
     : $use eq 'prohibited' ? 'attribute_prohibited'
     : croak "ERROR: attribute use is required, optional or prohibited (not '$use') in $path.\n";

    my $value = defined $default ? $default : $fixed;
    $name => $args->{run}{$generate}->($path, $args, $tag, $do, $value);
}

sub _group_particle($$$)
{   my ($path, $args, $node) = @_;

    my $ref = $node->getAttribute('ref')
       or croak "ERROR: group $path without ref";

    $path     .= "/gr";
    my $typename = _rel2abs($node, $ref);
#warn $typename;

    my $dest   = _ref_type($path, $args, $typename, 'group');
    defined $dest ? $dest->childNodes : ();
}

sub _attribute_group($$$);
sub _attribute_group($$$)
{   my ($path, $args, $node) = @_;

    my $ref = $node->getAttribute('ref')
       or croak "ERROR: attributeGroup $path without ref";

    $path     .= "/ag";
    my $typename = _rel2abs($node, $ref);
#warn $typename;

    my @res;
    my $dest   = _ref_type($path, $args, $typename, 'attributeGroup');
    defined $dest or return ();

    foreach my $child ($dest->childNodes)
    {   next unless $child->isa('XML::LibXML::Element');
        my $local = $child->localname;
        if($local eq 'attribute')
        {   push @res, _attribute($path, $args, $child) }
        elsif($local eq 'attributeGroup')
        {   push @res, _attribute_group($path, $args, $child) }
    }

    @res;
}

sub _complexType($$$)
{   my ($path, $args, $node) = @_;
    my @elems = _complex_elems($path, $args, $node);
    @elems ? $args->{run}{complexType}->($path, $args, $node, @elems) : ();
}

sub _complex_elems($$$)
{   my ($path, $args, $node) = @_;

    my @childs = $node->localName eq 'complexType' ? $node->childNodes : $node;
    my @elems;

    while(my $child = shift @childs)
    {   next unless $child->isa('XML::LibXML::Element');
        my $name = $child->localName;

        if($name eq 'simpleContent')
        {   # incorrect
            unshift @childs, $child->childNodes;
            next;
        }
        if($name eq 'complexContent')
        {   push @elems, _complexContent($path, $args, $child) }
        elsif($name eq 'attribute')
        {   push @elems, _attribute($path, $args, $child) }
        elsif($name eq 'attributeGroup')
        {   push @elems, _attribute_group($path, $args, $child) }
        else
        {   push @elems, _particles($path, $args, $child) }
    }

    @elems;
}

sub _complexContent($$$)
{   my ($path, $args, $node) = @_;

    my @childs = $node->childNodes;
    my @elems;

    while(my $child = shift @childs)
    {   next unless $child->isa('XML::LibXML::Element');
        my $name = $child->localName;
 
        if(   $name eq 'sequence' || $name eq 'choice' || $name eq 'all'
           || $name eq 'element'  || $name eq 'group')
        {   push @elems, _particles($path, $args, $child);
        }
        elsif($name eq 'extension')
        {   push @elems, _complex_extension($path, $args, $child);
        }
        elsif($name eq 'restriction')
        {   # nice for validating, but base can be ignored
            push @elems, map {particles($path, $args, $_)}
               grep {$_->isa('XML::LibXML::Element')} $child->childNodes;
        }
        else
        {   warn "WARN: unrecognized complexContent element '$name' in $path\n";
        }
    }

    @elems;
}

sub _complex_extension($$$)
{   my ($path, $args, $node) = @_;

    my $base = $node->getAttribute('base') || 'anyType';
    my @elems;

    if($base ne 'anyType')
    {   my $typename = _rel2abs($node, $base);
        my $typedef  = $args->{nss}->findType($typename)
            or die "ERROR: cannot base on unknown $base, at $path";

        $typedef->{type} eq 'complexType'
            or die "ERROR: base $base not complexType, at $path";

        push @elems, _complex_elems("$path#base", $args, $typedef->{node});
    }

    push @elems, map {_particles($path, $args, $_)}
        grep {$_->isa('XML::LibXML::Element')} $node->childNodes;

    @elems;
}

sub _particles($$$)
{   my ($path, $args, $node) = @_;

    my $name = $node->localName;

      $name eq 'sequence' || $name eq 'element' || $name eq 'group'
    ? _particle($path, $args, $node, 1, 1, 0, 'unbounded')
    : $name eq 'choice'
    ? _choice($path, $args, $node)
    : $name eq 'all'
    ? _particle($path, $args, $node, 1, 1, 1, 'unbounded')
    : die "ERROR: unrecognized particle '$name' in $path\n";
}

#
# Helper routines
#

# print _rel2abs($node, '{ns}type')    ->  '{ns}type'
# print _rel2abs($node, 'prefix:type') ->  '{ns(prefix)}type'

sub _rel2abs($$)
{   return $_[1] if substr($_[1], 0, 1) eq '{';

    my ($url, $local)
     = $_[1] =~ m/^(.+?)\:(.*)/
     ? ($_[0]->lookupNamespaceURI($1), $2)
     : ($_[0]->namespaceURI, $_[1]);

     defined $url
         or croak "ERROR: cannot understand type '$_[1]'";

     "{$url}$local";
}

1;
