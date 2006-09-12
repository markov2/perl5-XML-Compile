
use warnings;
use strict;

package XML::Compile::Schema;
use base 'XML::Compile';

use Carp;
use List::Util   qw/first/;
use XML::LibXML  ();
use File::Spec   ();

use XML::Compile::Schema::Specs;
use XML::Compile::Schema::BuiltInStructs qw/builtin_structs/;
use XML::Compile::Schema::Translate      qw/compile_tree/;
use XML::Compile::Schema::Instance;
use XML::Compile::Schema::NameSpaces;

my %schemaLocation =
 ( 'http://www.w3.org/2001/XMLSchema' => '2001-XMLSchema.xsd'
 );

=chapter NAME

XML::Compile::Schema - Compile a schema

=chapter SYNOPSIS

 # compile tree yourself
 my $parser = XML::LibXML->new;
 my $tree   = $parser->parse...(...);
 my $schema = XML::Compile::Schema->new($tree);

 # get schema from string
 my $schema = XML::Compile::Schema->new($xml_string);

 # adding schemas
 $schema->addSchemas($tree);
 $schema->importSchema('http://www.w3.org/2001/XMLSchema');
 $schema->importSchema('2001-XMLSchema.xsd');

 # create and use a reader
 my $read   = $schema->compile(READER => 'mytype');
 my $hash   = $read->($xml);
 
 # create and use a writer
 my $doc    = XML::LibXML::Document->new('1.0', 'UTF-8');
 my $write  = $schema->compile(WRITER => 'mytype');
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

=item XML Reader

The XML reader produces a HASH from a M<XML::LibXML::Node> tree or an
XML string.  Those represent the input data.  The values are checked.
An error produced when a value or the data-structure is not according
to the specs.

=item XML Writer

The writer produces schema compliant XML, based on a HASH.  To get the
data encoding correct, you are required to pass a document in which the
XML nodes may get a place later.

=back

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

The schemas defines kinds of data types.  There are various ways to define
them (with restrictions and extensions), but for the resulting data
structure is that knowledge not important.

=over 4

=item simpleType

A single value.  A lot of single value data-types are built-in (see
M<XML::Compile::Schema::BuiltInTypes>).  In XML, it looks like this:

 <test1>42</test1>

In the HASH structure, the data will be represented as

 test1 => 42

Simple types may have range limiting restrictions (facets), which will
be checked by default.  Types may also have some white-space behavior,
for instance blanks are stripped from integers: before, after, but also
inside the number representing string.

=item complexType/simpleContent

In this case, the single value container may have attributes.  In XML,
this looks like this:

 <test2 question="everything">42</test2>

The number of attributes can be endless, and the value is only one.  This
value has no name, and therefore gets a predefined name C<_>.  As a HASH,
this looks like

 test2 => { _ => 42, question => 'everything' }

=item complexType and complexType/complexContent

These containers not only have attributes, but also multiple values
as content.  The XML could look like:

 <test3 question="everything" by="mouse">
   <answer>42</answer>
   <when>5 billion BC</when>
 </test3>

Represented as HASH, this looks like

 test3 => { question => 'everything', by => 'mouse'
          , answer => 42, when => '5 billion BC' }

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

In this case, the element can appear multiple times.  The elements
will be kept in an ARRAY within the HASH. So

 <test4><a>12</a><a>13</a><b>14</b></test4>

will become

 test4 => { a => [12, 13], b => 14 };

Even when there is only one element found, it will be returned as
ARRAY (of one element).  Therefore, you can write

 my $data = $reader->($xml);
 foreach my $a ( @{$data->{a}} ) {...}

Non-schema based XML processors will not return a single value within
an ARRAY, which makes the code more complicated.

An error will be produced when the number of elements found is
less than minOccurs or more than maxOccurs.

=item use="optional" or minOccurs="0"

The element may be skipped.  When found, it is a single value.

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
with a minOccurs or maxOccurs unequal 1.  An example with a list of
ints:

  <test5>3 8 12</test5>

as Perl structure:

  test5 => [3, 8, 12]

=chapter METHODS

=section Constructors

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->{namespaces} = XML::Compile::Schema::NameSpaces->new;
    $self->SUPER::init($args);

    if(my $top = $self->top)
    {   $self->addSchemas($top);
    }

    $self;
}

=section Accessors

=method namespaces
Returns the M<XML::Compile::Schema::NameSpaces> object which is used
to collect schemas.
=cut

sub namespaces() { shift->{namespaces} }

=method addSchemas NODE
Collect all the schemas defined below the NODE.
=cut

sub addSchemas($$)
{   my ($self, $top) = @_;

    $top    = $top->documentElement
       if $top->isa('XML::LibXML::Document');

    my $nss = $self->namespaces;

    $self->walkTree
    ( $top,
      sub { my $node = shift;
            return 1 unless $node->isa('XML::LibXML::Element')
                         && $node->localname eq 'schema';

            my $schema = XML::Compile::Schema::Instance->new($node)
                or next;

#warn $schema->targetNamespace;
#$schema->printIndex(\*STDERR);
            $nss->add($schema);
            return 0;
          }
    );
}

=method importSchema FILENAME|NAMESPACE
Import (parse) the XML found in the specified file.  Some NAMESPACES
are linked to predefined filenames, especially the schema defining files.
The FILENAME can be relative, see M<findSchemaFile()>.
=cut

sub importSchema($)
{   my ($self, $thing) = @_;

    my $filename = $schemaLocation{$thing} || $thing;

    my $path = $self->findSchemaFile($filename)
        or croak "ERROR: cannot find $filename for $thing";

    my $tree = $self->parseFile($path)
        or croak "ERROR: cannot parse XML from $path";

    $self->addSchema($tree);
}

=section Compilers

=method compile ('READER'|'WRITER'), ELEMENT, OPTIONS

Translate the specified ELEMENT into a CODE reference which is able to
translate between XML-text and a HASH.

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
=default check_occurs <true>
Whether code will be produced to complain about elements which
should or should not appear, and is between bounds or not.
Elements which may have more than 1 occurence will still always
be represented by an ARRAY.

=option  invalid 'IGNORE','WARN','DIE',CODE
=default invalid DIE
What to do in invalid values (ignored when not checking). See
M<invalidsErrorHandler()> who initiates this handler.

=option  ignore_facets BOOLEAN
=default ignore_facets C<false>
Facets influence the formatting and range of values. This does
not come cheap, so can be turned off.  Affects the restrictions
set for a simpleType.

=option  path STRING
=default path <expanded name of type>
Prepended to each error report, to indicate the location of the
error in the XML-Scheme tree.

=option  elements_qualified BOOLEAN
=default elements_qualified <undef>
When defined, this will overrule the C<elementFormDefault> flags in
all schema's.  When not qualified, the xml will not produce or
process prefixes on the elements.

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

=example create an XML reader
 my $msgin  = $rules->compile(READER => 'myns#mytype');
 my $xml    = $parser->parse("some-xml.xml");
 my $hash   = $msgin->($xml);

or
 my $hash   = $msgin->($xml_string);

=example create an XML writer
 my $msgout = $rules->compile(WRITER => 'myns#mytype');
 my $xml    = $msgout->($hash);
 print $xml->toString;
 
=cut

sub compile($$@)
{   my ($self, $direction, $type, %args) = @_;

    exists $args{check_values}
       or $args{check_values} = 1;

    exists $args{check_occurs}
       or $args{check_occurs} = 0;

    $args{sloppy_integers}   ||= 0;
    unless($args{sloppy_integers})
    {   eval "require Math::BigInt";
        die "ERROR: require Math::BigInt or sloppy_integers:\n$@"
            if $@;

        eval "require Math::BigFloat";
        die "ERROR: require Math::BigFloat or sloppy_integers:\n$@"
            if $@;
    }

    $args{include_namespaces} ||= 1;
    $args{output_namespaces}  ||= {};

    do { $_->{used} = 0 for values %{$args{output_namespaces}} }
       if $args{namespace_reset};

    my $nss   = $self->namespaces;
    my $top   = $nss->findType($type) || $nss->findElement($type)
       or croak "ERROR: type $type is not defined";

    $args{path} ||= $top->{full};

    compile_tree
     ( $top->{full}, %args
     , run => builtin_structs($direction) 
     , err => $self->invalidsErrorHandler($args{invalid})
     , nss => $self->namespaces
     );
}

=method template OPTIONS
This method will try to produce a HASH template, to express how
Perl's side of the data structure could look like.
NOT IMPLEMENTED YET
=cut

sub template($@)
{   my ($self, $direction) = (shift, shift);

    my %args =
     ( check_values       => 0
     , check_occurs       => 0
     , invalid            => 'IGNORE'
     , ignore_facets      => 1
     , include_namespaces => 1
     , sloppy_integers    => 1
     , auto_value         => sub { warn @_; $_[0] }
     , @_
     );

   die "ERROR not implemented";
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

1;
