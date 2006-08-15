
use warnings;
use strict;

package XML::Compile::Schema;
use base 'XML::Compile';

use Carp;
use List::Util   qw/first/;
use XML::LibXML;

use XML::Compile::Schema::Specs;
use XML::Compile::Schema::BuiltInStructs qw/builtin_structs/;
use XML::Compile::Schema::Translate      qw/compile_tree/;
use XML::Compile::Schema::Instance;
use XML::Compile::Schema::NameSpaces;

=chapter NAME

XML::Compile::Schema - Compile a schema

=chapter SYNOPSIS

 # preparation
 my $parser = XML::LibXML->new;
 my $tree   = $parser->parse...(...);

 my $schema = XML::Compile::Schema->new($tree);

 my $schema = XML::Compile::Schema->new($xml_string);
 my $read   = $schema->compile(READER => 'mytype');
 my $hash   = $read->($xml);
 
 my $doc    = XML::LibXML::Document->new('1.0', 'UTF-8');
 my $write  = $schema->compile(WRITER => 'mytype');
 my $xml    = $write->($doc, $hash);
 print $xml->toString;

=chapter DESCRIPTION

This module collects knowledge about a schema.  The most important
method is M<compile()> which can create XML file readers and writers
based on the schema information and some selected type.

WARNING: The compiler is implemented in M<XML::Compile::Schema::Translate>,
which is NOT FINISHED.  See that manual page about the specific behavior
and its (current) limitations!

WARNING: the provided B<schema is not validated>!  In some cases,
compile-time and run-time errors will be reported, but typically only
in cases that the parser has no idea what to do with such a mistake.
On the other hand, the processed B<data is validated>: the output should
follow the specs closely.

Two implementations use the translator, and more can be added later.  Both
get created with the M<compile()> method.

=over 4

=item XML Reader

The XML reader produces a hash from a M<XML::LibXML::Node> tree, or an
XML string.  The values are checked and will be ignored if the value is
not according to the specs.

=item XML Writer

The writer produces schema compliant XML, based on a hash.  To get the
data encoding correct, you are required to pass a document in which the
XML nodes may get a place later.

=back

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
Returns the M<XML::Compile::Schema::Namespaces> object which is used
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

=section Compilers

=method compile ('READER'|'WRITER'), NAME, OPTIONS

Translate the specified TYPE into a CODE reference which is able to
translate between XML-text and a HASH.

The NAME is the starting-point for processing in the data-structure.
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
             $nss->namespaces;
}

=method elements
List all elements, defined by all schemas sorted alphabetically.
=cut

sub elements()
{   my $nss = shift->namespaces;
    sort map {$_->elements}
          map {$nss->schemas($_)}
             $nss->namespaces;
}

1;
