
use warnings;
use strict;

package XML::Compile::Schema;
use base 'XML::Compile';

use Carp;
use List::Util   qw/first/;
use XML::LibXML  ();
use File::Spec   ();

use XML::Compile::Schema::Specs;
use XML::Compile::Schema::Translate      ();
use XML::Compile::Schema::Instance;
use XML::Compile::Schema::NameSpaces;

=chapter NAME

XML::Compile::Schema - Compile a schema

=chapter SYNOPSIS

 # compile tree yourself
 my $parser = XML::LibXML->new;
 my $tree   = $parser->parse...(...);
 my $schema = XML::Compile::Schema->new($tree);

 # get schema from string
 my $schema = XML::Compile::Schema->new($xml_string);

 # get schema from file
 my $schema = XML::Compile::Schema->new($filename);

 # adding schemas
 $schema->addSchemas($tree);
 $schema->importDefinitions('http://www.w3.org/2001/XMLSchema');
 $schema->importDefinitions('2001-XMLSchema.xsd');

 # create and use a reader
 my $read   = $schema->compile(READER => '{myns}mytype');
 my $hash   = $read->($xml);
 
 # create and use a writer
 my $doc    = XML::LibXML::Document->new('1.0', 'UTF-8');
 my $write  = $schema->compile(WRITER => '{myns}mytype');
 my $xml    = $write->($doc, $hash);

 # show result
 print $xml->toString;

=chapter DESCRIPTION

This module collects knowledge about one or more schemas.  The most
important method is M<compile()> which can create XML file readers and
writers based on the schema information and some selected type.

Two implementations use the translator, and more can be added later.  Both
get created with the C<compile> method.

=over 4

=item READER (translate XML to HASH)

The XML reader produces a HASH from a M<XML::LibXML::Node> tree or an
XML string.  Those represent the input data.  The values are checked.
An error produced when a value or the data-structure is not according
to the specs.

The CODE reference which is returned can be called with anything
accepted by M<dataToXML()>.

=example create an XML reader
 my $msgin  = $rules->compile(READER => '{myns}mytype');
 my $xml    = $parser->parse("some-xml.xml");
 my $hash   = $msgin->($xml);

or

 my $hash   = $msgin->('some-xml.xml');
 my $hash   = $msgin->($xml_string);
 my $hash   = $msgin->($xml_node);

=item WRITER (translate HASH to XML)

The writer produces schema compliant XML, based on a HASH.  To get the
data encoding correct, you are required to pass a document in which the
XML nodes may get a place later.

=example create an XML writer
 my $doc    = XML::LibXML::Document->new('1.0', 'UTF-8');
 my $write  = $schema->compile(WRITER => '{myns}mytype');
 my $xml    = $write->($doc, $hash);
 print $xml->toString;
 
alternative

 my $write  = $schema->compile(WRITER => 'myns#myid');
=back

Be warned that the schema itself is NOT VALIDATED; you can easily
construct schema's which do work with this module, but are not
valid according to W3C.  Only in some cases, the translater will
refuse to accept mistakes: mainly because it cannot produce valid
code.

See chapter L</DETAILS> and learn how the data is processed.

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=option  hook ARRAY-WITH-HOOKDATA | HOOK
=default hook C<undef>
See M<addHook()>.  Adds one HOOK (HASH).

=option  hooks ARRAY-OF-HOOK
=default hooks []
See M<addHooks()>.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->{namespaces} = XML::Compile::Schema::NameSpaces->new;
    $self->SUPER::init($args);

    $self->importDefinitions($args->{top});

    $self->{hooks} = [];
    if(my $h1 = $args->{hook})
    {   $self->addHook(ref $h1 eq 'ARRAY' ? @$h1 : $h1);
    }
    if(my $h2 = $args->{hooks})
    {   $self->addHooks(ref $h2 eq 'ARRAY' ? @$h2 : $h2);
    }
 
    $self;
}

=section Accessors

=method namespaces
Returns the M<XML::Compile::Schema::NameSpaces> object which is used
to collect schemas.
=cut

sub namespaces() { shift->{namespaces} }

=method addSchemas XML, OPTIONS
Collect all the schemas defined in the XML data.

=error required is a XML::LibXML::Node
Use M<importDefinitions()> to specify schema's in any (other) form, like
as string.
=cut

sub addSchemas($)
{   my $self = shift;
    my $node = shift or return ();

    ref $node && $node->isa('XML::LibXML::Node')
        or croak "ERROR: required is a XML::LibXML::Node\n";

    $node = $node->documentElement
        if $node->isa('XML::LibXML::Document');

    my $nss = $self->namespaces;

    $self->walkTree
    ( $node,
      sub { my $this = shift;
            return 1 unless $this->isa('XML::LibXML::Element')
                         && $this->localname eq 'schema';

            my $schema = XML::Compile::Schema::Instance->new($this)
                or next;

#warn $schema->targetNamespace;
#$schema->printIndex(\*STDERR);
            $nss->add($schema);
            return 0;
          }
    );
}

=method importDefinitions XMLDATA, OPTIONS
Import (include) the schema information included in the XMLDATA.  The
XMLDATA must be acceptable for M<dataToXML()>.  The OPTIONS are passed
to M<addSchemas()>.
=cut

sub importDefinitions($@)
{   my ($self, $thing) = (shift, shift);
    my $tree = $self->dataToXML($thing) or return;
    $self->addSchemas($tree, @_);
}

=method addHook HOOKDATA|HOOK|undef
HOOKDATA is a LIST of options as key-value pairs, HOOK is a HASH with
the same data.  C<undef> is ignored. See M<addHooks()> and
L</Schema hooks> below.
=cut

sub addHook(@)
{   my $self = shift;
    push @{$self->{hooks}}, @_>=1 ? {@_} : defined $_[0] ? shift : ();
    $self;
}

=method addHooks HOOK, [HOOK, ...]
Add multiple hooks at once.  These all must be HASHes. See L</Schema hooks>
and M<addHook()>. C<undef> values are ignored.
=cut

sub addHooks(@)
{   my $self = shift;
    push @{$self->{hooks}}, grep {defined} @_;
    $self;
}

=method hooks
Returns the LIST of defined hooks (HASHes).
=cut

sub hooks() { @{shift->{hooks}} }

=section Compilers

=method compile ('READER'|'WRITER'), ELEMENT, OPTIONS

Translate the specified ELEMENT into a CODE reference which is able to
translate between XML-text and a HASH.  When the ELEMENT is C<undef>,
then an empty LIST is returned.

The ELEMENT is the starting-point for processing in the data-structure.
It can either be a global element, or a global type.  The NAME
must be specified in C<{url}name> format, there the url is the
name-space.  An alternative is the C<url#id> which refers to 
an element or type with the specific C<id> attribute value.

When a READER is created, a CODE reference is returned which needs
to be called with parsed XML (an L<XML::LibXML::Node>) or an XML text.
Returned is a nested HASH structure which contains the data from
contained in the XML.  When a simple element type is addressed, you
will get a single value back,

When a WRITER is created, a CODE reference is returned which needs
to be called with a HASH, and returns a XML::LibXML::Node.

Most options below are explained in more detailed in the manual-page
M<XML::Compile::Schema::Translate>.

=option  check_values BOOLEAN
=default check_values <true>
Whether code will be produce to check that the XML fields contain
the expected data format.

Turning this off will improve the processing significantly, but is
(of course) much less unsafer.  Do not set it off when you expect
data from external sources.

=option  check_occurs BOOLEAN
=default check_occurs <false>
Whether code will be produced to complain about elements which
should or should not appear, and is between bounds or not.
Elements which may have more than 1 occurence will still always
be represented by an ARRAY.

=option  invalid 'IGNORE','WARN','DIE',CODE
=default invalid DIE
What to do in invalid values (ignored when not checking). See
M<invalidsErrorHandler()> who initiates this handler.

=option  ignore_facets BOOLEAN
=default ignore_facets <false>
Facets influence the formatting and range of values. This does
not come cheap, so can be turned off.  Affects the restrictions
set for a simpleType.

=option  path STRING
=default path <expanded name of type>
Prepended to each error report, to indicate the location of the
error in the XML-Scheme tree.

=option  elements_qualified C<TOP>|C<ALL>|C<NONE>|BOOLEAN
=default elements_qualified <undef>
When defined, this will overrule the C<elementFormDefault> flags in
all schema's.  When C<TOP> is specified, at least the top-element will
be name-space qualified.  When C<ALL> or a true value is given, then all
elements will be used qualified.  When C<NONE> or a false value is given,
the XML will not produce or process prefixes on the elements.

The C<form> attributes will be respected, except on the top element when
C<TOP> is specified.  Use hooks when you need to fix name-space use in
more subtile ways.

=option  attributes_qualified BOOLEAN
=default attributes_qualified <undef>
When defined, this will overrule the C<attributeFormDefault> flags in
all schema's.  When not qualified, the xml will not produce nor
process prefixes on attributes.

=option  output_namespaces HASH
=default output_namespaces {}
Can be used to predefine an output namespace (when 'WRITER') for instance
to reserve common abbreviations like C<soap> for external use.  Each
entry in the hash has as key the namespace uri.  The value is a hash
which contains C<uri>, C<prefix>, and C<used> fields.  Pass a reference
to a private hash to catch this index.

=option  include_namespaces BOOLEAN
=default include_namespaces <true>
Indicates whether the WRITER should include the prefix to namespace
translation on the top-level element of the returned tree.  If not,
you may continue with the same name-space table to combine various
XML components into one, and add the namespaces later.

=option  namespace_reset BOOLEAN
=default namespace_reset <false>
Use the same prefixes in C<output_namespaces> as with some other compiled
piece, but reset the counts to zero first.

=option  sloppy_integers BOOLEAN
=default sloppy_integers <false>
The C<decimal> and C<integer> types must support at least 18 digits,
which is larger than Perl's 32 bit internal integers.  Therefore, the
implementation will use M<Math::BigInt> objects to handle them.  However,
often an simple C<int> type whould have sufficed, but the XML designer
was lazy.  A long is much faster to handle.  Set this flag to use C<int>
as fast (but inprecise) replacements.

Be aware that C<Math::BigInt> and C<Math::BigFloat> objects are nearly
but not fully transparent mimicing the behavior of Perl's ints and
floats.  See their respective manual-pages.  Especially when you wish
for some performance, you should optimize access to these objects to
avoid expensive copying which is exactly the spot where the difference
are.

=option  anyElement CODE
=default anyElement C<undef>
In general, C<any> schema components cannot be handled automatically.
If  you need to create or process any information, then read about
wildcards in the DETAILS chapter of the manual-page for the specific
back-end.

=option  anyAttribute CODE
=default anyAttribute C<undef>
In general, C<anyAttribute> schema components cannot be handled
automatically.  If  you need to create or process anyAttribute
information, then read about wildcards in the DETAILS chapter of the
manual-page for the specific back-end.

=option  hook HOOK|ARRAY-OF-HOOKS
=default hook C<undef>
Define one or more processing hooks.  See L</Schema hooks> below.
These hooks are only active for this compiled entity, where M<addHook()>
and M<addHooks()> can be used to define hooks which are used for all
results of M<compile()>.  The hooks specified with the C<hook> or C<hooks>
option are run before the global definitions.

=option  hooks HOOK|ARRAY-OF-HOOKS
=default hooks C<undef>
Alternative for option C<hook>.

=cut

sub compile($$@)
{   my ($self, $action, $type, %args) = @_;
    defined $type or return ();

    exists $args{check_values}
       or $args{check_values} = 1;

    exists $args{check_occurs}
       or $args{check_occurs} = 1;

    $args{sloppy_integers}   ||= 0;
    unless($args{sloppy_integers})
    {   eval "require Math::BigInt";
        die "ERROR: require Math::BigInt or sloppy_integers:\n$@"
            if $@;

        eval "require Math::BigFloat";
        die "ERROR: require Math::BigFloat or sloppy_integers:\n$@"
            if $@;
    }

    $args{include_namespaces} = 1
        unless defined $args{include_namespaces};

    $args{output_namespaces}  ||= {};

    do { $_->{used} = 0 for values %{$args{output_namespaces}} }
        if $args{namespace_reset};

    my $nss   = $self->namespaces;

    my ($h1, $h2) = (delete $args{hook}, delete $args{hooks});
    my @hooks = $self->hooks;
    push @hooks, ref $h1 eq 'ARRAY' ? @$h1 : $h1 if $h1;
    push @hooks, ref $h2 eq 'ARRAY' ? @$h2 : $h2 if $h2;

    my $bricks = 'XML::Compile::Schema::' .
     ( $action eq 'READER' ? 'XmlReader'
     : $action eq 'WRITER' ? 'XmlWriter'
     : croak "ERROR: create only READER, WRITER, not '$action'."
     );

    eval "require $bricks";
    die $@ if $@;

    XML::Compile::Schema::Translate->compileTree
     ( $type, %args
     , bricks => $bricks
     , err    => $self->invalidsErrorHandler($args{invalid})
     , nss    => $self->namespaces
     , hooks  => \@hooks
     );
}

=method template 'XML'|'PERL', TYPE, OPTIONS
WARNING: under development!  The implementation is far from complete.

Schema's can be horribly complex and unreadible.  Therefore, this template
method can be called to create an example which demonstrates how data of
the specified TYPE as XML or Perl is organized in practice.

Some OPTIONS are explained in M<XML::Compile::Schema::Translate>.
There are some extra OPTIONS defined for the final output process.

=option  elements_qualified C<ALL>|C<TOP>|C<NONE>|BOOLEAN
=default elements_qualified <undef>

=option  attributes_qualified BOOLEAN
=default attributes_qualified <undef>

=option  include_namespaces BOOLEAN
=default include_namespaces <true>

=option  show STRING|'ALL'|'NONE'
=default show C<ALL>
A comma seperated list of tokens, which explain what kind of comments need
to be included in the output.  The available tokens are: C<struct>, C<type>,
C<occur>, C<facets>.  A value of C<ALL> will select all available comments.
The C<NONE> or empty string will exclude all comments.

=option  indent STRING
=default indent "  "
The leading indentation string per nesting.  Must start with at least one
blank.

=cut

sub template($@)
{   my ($self, $action, $type, %args) = @_;

    my $show = exists $args{show} ? $args{show} : 'ALL';
    $show = 'struct,type,occur,facets' if $show eq 'ALL';
    $show = '' if $show eq 'NONE';
    my @comment = map { ("show_$_" => 1) } split m/\,/, $show;

    my $nss = $self->namespaces;

    my $indent                  = $args{indent} || "  ";
    $args{check_occurs}         = 1;
    $args{include_namespaces} ||= 1;

    my $bricks = 'XML::Compile::Schema::Template';
    eval "require $bricks";
    die $@ if $@;

    my $compiled = XML::Compile::Schema::Translate->compileTree
     ( $type
     , bricks => $bricks
     , nss    => $self->namespaces
     , err    => $self->invalidsErrorHandler('IGNORE')
     , hooks  => []
     , %args
     );

    my $ast = $compiled->();
# use Data::Dumper;
# $Data::Dumper::Indent = 1;
# warn Dumper $ast;

    if($action eq 'XML')
    {   my $doc  = XML::LibXML::Document->new('1.1', 'UTF-8');
        my $node = $bricks->toXML($doc,$ast, @comment, indent => $indent);
        return $node->toString(1);
    }

    if($action eq 'PERL')
    {   return $bricks->toPerl($ast, @comment, indent => $indent);
    }

    die "ERROR: template output is either in XML or PERL layout, not '$action'\n";
}

=method invalidsErrorHandler 'IGNORE','USE'.'WARN','DIE',CODE

What to do when a validation error appears during validation?  This method
translates all string options into a single code reference which is
returned.  Please use the C<invalid> options of M<compile()>
which will call this method indirectly.

When C<IGNORE> is specified, the process will ignore the specified
value as if it was not specified at all.  C<USE> will not complain,
and use the value found. With C<WARN>, it will continue with the value
but a warning is printed first.  On C<DIE> it will stop processing,
as will the program (catch it with C<eval>).

When a CODE reference is specified, that will be called specifying
the type path, actual type expected (expanded name), the errorneous
value, and an error string.

=cut

sub invalidsErrorHandler($)
{   my $key = $_[1] || 'DIE';

      ref $key eq 'CODE'? $key
    : $key eq 'IGNORE'  ? sub { undef }
    : $key eq 'USE'     ? sub { $_[1] }
    : $key eq 'WARN'
    ? sub {warn "$_[2] ("
              . (defined $_[1]? $_[1] : 'undef')
              . ") for $_[0]\n"; $_[1]}
    : $key eq 'DIE'
    ? sub {die  "$_[2] (".(defined $_[1] ? $_[1] : 'undef').") for $_[0]\n"}
    : die "ERROR: error handler expects CODE, 'IGNORE',"
        . "'USE','WARN', or 'DIE', not $key";
}

=method types
List all types, defined by all schemas sorted alphabetically.
=cut

sub types()
{   my $nss = shift->namespaces;
    sort map {$_->types}
          map {$nss->schemas($_)}
             $nss->list;
}

=method elements
List all elements, defined by all schemas sorted alphabetically.
=cut

sub elements()
{   my $nss = shift->namespaces;
    sort map {$_->elements}
          map {$nss->schemas($_)}
             $nss->list;
}

=chapter DETAILS

=section Addressing components

Normally, external users can only address elements within a schema,
and types are hidden to be used by other schema's only.  For this
reason, it is permitted to create an element and a type with the
same name.

The compiler requires a starting-point.  This can either be an
element name or an element's id.  The format of the element name
is C<{url}name>, for instance

 {http://library}book

refers to the built-in C<int> data-type.  You may also start with

 http://www.w3.org/2001/XMLSchema#float

as long as this ID refers to an element.

=section Representing data-structures

The code will do its best to produce a correct translation. For
instance, an accidental C<1.9999> will be converted into C<2>
when the schema says that the field is an C<int>.  It will also
strip superfluous blanks when the data-type permits.  Especially
watch-out for the C<Integer> types, which produce M<Math::BigInt>
objects unless M<compile(sloppy_integers)> is used.

Elements can be complex, and themselve contain elements which
are complex.  In the Perl representation of the data, this will
be shown as nested hashes with the same structure as the XML.

You should not take tare of character encodings, whereas XML::LibXML is
doing that for us: you shall not escape characters like "E<lt>" yourself.

The schemas define kinds of data types.  There are various ways to define
them (with restrictions and extensions), but for the resulting data
structure is that knowledge not important.

=over 4

=item simpleType

A single value.  A lot of single value data-types are built-in (see
M<XML::Compile::Schema::BuiltInTypes>).

Simple types may have range limiting restrictions (facets), which will
be checked by default.  Types may also have some white-space behavior,
for instance blanks are stripped from integers: before, after, but also
inside the number representing string.

Note that some of the reader hooks will alter the single value of these
elements into a HASH like used for the complexType/simpleContent (next
paragraph), to be able to return some extra collected information.

=example typical simpleType

In XML, it looks like this:

 <test1>42</test1>

In the HASH structure, the data will be represented as

 test1 => 42

With reader hook C<after => 'XML_NODE'> hook applied, it will become

 test1 => { _ => 42
          , _XML_NODE => $obj
          }
 
=item complexType/simpleContent

In this case, the single value container may have attributes.  The number
of attributes can be endless, and the value is only one.  This value
has no name, and therefore gets a predefined name C<_>.

=example typical simpleContent example

In XML, this looks like this:

 <test2 question="everything">42</test2>

As a HASH, this looks like

 test2 => { _ => 42
          , question => 'everything'
          }

=item complexType and complexType/complexContent

These containers not only have attributes, but also multiple values
as content.  The C<complexContent> is used to create inheritance
structures in the data-type definition.  This does not affect the
XML data package itself.

=example typical complexType element

The XML could look like:

 <test3 question="everything" by="mouse">
   <answer>42</answer>
   <when>5 billion BC</when>
 </test3>

Represented as HASH, this looks like

 test3 => { question => 'everything'
          , by       => 'mouse'
          , answer   => 42
          , when     => '5 billion BC'
          }

=back

=section Processing elements

A second factor which determines the data-structure is the element
occurence.  Usually, elements have to appear once and exactly once
on a certain location in the XML data structure.  This order is
automatically produced by this module. But elements may appear multiple
times.

=over 4

=item usual case

The default behavior for an element (in a sequence container) is to
appear exactly once.  When missing, this is an error.

=item maxOccurs larger than 1

In this case, the element can appear multiple times.  Multiple values will
be kept in an ARRAY within the HASH.  Non-schema based XML processors
will not return a single value as an ARRAY, which makes that code more
complicated.

An error will be produced when the number of elements found is
less than C<minOccurs> or more than C<maxOccurs>, unless
M<compile(check_occurs)> is C<false>.

=example two values for C<a>

 <test4><a>12</a><a>13</a><b>14</b></test4>

will become

 test4 => { a => [12, 13], b => 14 };

=example always an array

Even when there is only one element found, it will be returned as
ARRAY (of one element).  Therefore, you can write

 my $data = $reader->($xml);
 foreach my $a ( @{$data->{a}} ) {...}


=item use="optional" or minOccurs="0"

The element may be skipped.  When found it is a single value.

=item use="forbidden"

When the element is found, an error is produced.

=item default="value"

When the XML does not contain the element, the default value is
used... but only if this element's container exists.  This has
no effect on the writer.

=item fixed="value"

Produce an error when the value is not present or different (after
the white-space rules where applied).

=back

=section List type

List simpleType objects are also represented as ARRAY, like elements
with a minOccurs or maxOccurs unequal 1.

=example with a list of ints

  <test5>3 8 12</test5>

as Perl structure:

  test5 => [3, 8, 12]

=section substitutionGroup

A substitution group is kind-of choice between alternative (complex)
types.  However, in this case roles have reversed: instead a C<choice>
which lists the alternatives, here the alternative elements register
themselves as valid for an abstract (I<head>) element.  All alternatives
should be extensions of the head element's type, but there is no way to
check that.

=example substitutionGroup

 <xs:element name="price"  type="xs:int" abstract="true" />
 <xs:element name="euro"   type="xs:int" substitutionGroup="price" />
 <xs:element name="dollar" type="xs:int" substitutionGroup="price" />

 <xs:element name="product">
   <xs:complexType>
      <xs:element name="name" type="xs:string" />
      <xs:element ref="price" />
   </xs:complexType>
 </xs:element>
 
Now, valid XML data is

 <product>
   <name>Ball</name>
   <euro>12</euro>
 </product>

and

 <product>
   <name>Ball</name>
   <dollar>6</dollar>
 </product>

The HASH repesentation is respectively

 product => {name => 'Ball', euro  => 12}
 product => {name => 'Ball', dollar => 6}
 
=section Wildcards

The C<any> and C<anyAttribute> elements are referred to as C<wildcards>:
they specify groups of elements and attributes which can be used, in
stead of being explicit.

The author of this module advices B<against the use of wildcards>
in schema's, because the purpose of schema's is to be explicit and that
basic idea is simply thrown away by these wildcards.  Let people cleanly
extend the schema with inheritance!  If you use a standard schema
which facilitates these wildcards, then please do not use them!

Because wildcards are not explicit about the types to expect, the
C<XML::Compile> module can not prepare for them automatically.
However, as user of the schema you probably know better about the possible
contents of these fields.  Therefore, you can translate that
knowledge into code explicitly.  Read about the processing of wildcards
in the manual page for each of the back-ends, because it is different
in each case.

=section Schema hooks

You can use hooks, for instance, to block processing parts of the message,
to create work-arounds for schema bugs, or to extract more information
during the process than done by default.

=subsection defining hooks

Multiple hooks can active during the compilation process of a type,
when C<compile()> is called.  During Schema translation, each of the
hooks is checked for all types which are processed.  When multiple
hooks select the object to get a modified behavior, then all are
evaluated in order of definition.

Defining a B<global> hook (where HOOKDATA is the LIST of PAIRS with
hook parameters, and HOOK a HASH with such HOOKDATA):

 my $schema = XML::Compile::Schema->new
  ( ...
  , hook  => HOOK
  , hooks => [ HOOK, HOOK ]
  );

 $schema->addHook(HOOKDATA | HOOK);
 $schema->addHooks(HOOK, HOOK, ...);

 my $wsdl   = XML::Compile::WSDL->new(...);
 $wsdl->schemas->addHook(HOOKDATA | HOOK);

B<local> hooks are only used for one reader or writer.  They are
evaluated before the global hooks.

 my $reader = $schema->compile(READER => $type
  , hook => HOOK, hooks => [ HOOK, HOOK, ...]);

 # syntax may still change
 $wsdl->call(GetPrice => $params, hook => HOOK, ...);
 $wsdl->prepare('GetPrice', hook => HOOK, ...);
 $wsdl->server(hook => HOOK, ...);

=examples of HOOKs:

 my $hook = { type    => '{my_ns}my_type'
            , before  => sub { ... }
            };

 my $hook = { path    => qr/\(volume\)/
            , replace => 'SKIP'
            };

 # path contains "(volume)" or id is 'aap' or id is 'noot'
 my $hook = { path    => qr/\(volume\)/
            , id      => [ 'aap', 'noot' ]
            , before  => [ sub {...}, sub { ... } ]
            , after   => sub { ... }
            };

=subsection general syntax

Each hook has two kinds of parameters: selectors and processors.
Selectors define the schema component of which the processing is modified.
When one of the selectors matches, the processing information for the hook
is used.  When no selector is specified, then the hook will be used on all
elements.  Available selectors (see below for details on each of them):

=over 4
=item . type
=item . id
=item . path
=back

As argument, you can specify one element as STRING, a regular expression
to select multiple elements, or an ARRAY of STRINGs and REGEXes.

Next to where the hook is placed, we need to known what to do in
the case: the hook contains processing information.  When more than
one hook matches, then all of these processors are called in order
of hook definition.  However, first the compile hooks are taken,
and then the global hooks.

How the processing works exactly depends on the compiler back-end.  There
are major differences.  Each of those manual-pages lists the specifics.
The label tells us when the processing is initiated.  Available labels are
C<before>, C<replace>, and C<after>.

=subsection hooks on matching types

The C<type> selector specifies a complexType of simpleType by name.
Best is to base the selection on the full name, like C<{ns}type>,
which will avoid all kinds of name-space conflicts in the future.
However, you may also specify only the C<type> (in any name-space).
Any REGEX will be matched to the full type name. Be careful with the
pattern archors.

=examples use of the type selector

 type => 'int'
 type => '{http://www.w3.org/2000/10/XMLSchema}int'
 type => qr/\}xml_/   # type start with xml_
 type => [ qw/int float/ ];

=subsection hooks on matching ids

Matching based on IDs can reach more schema elements: some types are
anonymous but still have an ID.  Best is to base selection on the full
ID name, like C<ns#id>, to avoid all kinds of name-space conflicts in
the future.

=examples use of the ID selector

 # default schema types have id's with same name
 id => 'int'
 id => 'http://www.w3.org/2000/10/XMLSchema#int'
 id => qr/\#xml_/   # id which start with xml_
 id => [ qw/int float/ ];

=subsection hooks on matching paths

When you see error messages, you always see some representation of
the path where the problem was discovered.  You can use this path
as selector, when you know what it is... BE WARNED, that the current
structure of the path is not really consequent hence will be 
improved in one of the future releases, breaking backwards compatibility.

=cut

1;
