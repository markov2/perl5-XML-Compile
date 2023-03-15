# This code is part of distribution XML-Compile.  Meta-POD processed with
# OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package XML::Compile::Schema;
use base 'XML::Compile';

use warnings;
use strict;

use Log::Report    'xml-compile';

use List::Util     qw/first/;
use XML::LibXML    ();
use File::Spec     ();
use File::Basename qw/basename/;
use Digest::MD5    qw/md5_hex/;

use XML::Compile::Schema::Specs;
use XML::Compile::Schema::Instance;
use XML::Compile::Schema::NameSpaces;
use XML::Compile::Util       qw/SCHEMA2001 SCHEMA2001i unpack_type/;

use XML::Compile::Translate  ();

=chapter NAME

XML::Compile::Schema - Compile a schema into CODE

=chapter SYNOPSIS

 # compile tree yourself
 my $parser = XML::LibXML->new;
 my $tree   = $parser->parse...(...);
 my $schema = XML::Compile::Schema->new($tree);

 # get schema from string
 my $schema = XML::Compile::Schema->new($xml_string);

 # get schema from file (most used)
 my $schema = XML::Compile::Schema->new($filename);
 my $schema = XML::Compile::Schema->new([glob "*.xsd"]);

 # the "::Cache" extension has more power
 my $schema = XML::Compile::Cache->new(\@xsdfiles);

 # adding more schemas, from parsed XML
 $schema->addSchemas($tree);

 # adding more schemas from files
 # three times the same: well-known url, filename in schemadir, url
 # Just as example: usually not needed.
 $schema->importDefinitions('http://www.w3.org/2001/XMLSchema');
 $schema->importDefinitions('2001-XMLSchema.xsd');
 $schema->importDefinitions(SCHEMA2001);  # from ::Util

 # alternatively
 my @specs  = ('one.xsd', 'two.xsd', $schema_as_string);
 my $schema = XML::Compile::Schema->new(\@specs); # ARRAY!

 # see what types are defined
 $schema->printIndex;

 # create and use a reader
 use XML::Compile::Util qw/pack_type/;
 my $elem   = pack_type 'my-namespace', 'my-local-name';
                # $elem eq "{my-namespace}my-local-name"
 my $read   = $schema->compile(READER => $elem);
 my $data   = $read->($xmlnode);
 my $data   = $read->("filename.xml");
 
 # when you do not know the element type beforehand
 use XML::Compile::Util qw/type_of_node/;
 my $elem   = type_of_node $xml->documentElement;
 my $reader = $reader_cache{$type}               # either exists
          ||= $schema->compile(READER => $elem); #   or create
 my $data   = $reader->($xmlmsg);
 
 # create and use a writer
 my $doc    = XML::LibXML::Document->new('1.0', 'UTF-8');
 my $write  = $schema->compile(WRITER => '{myns}mytype');
 my $xml    = $write->($doc, $hash);
 $doc->setDocumentElement($xml);

 # show result
 print $doc->toString(1);

 # to create the type nicely
 use XML::Compile::Util qw/pack_type/;
 my $type   = pack_type 'myns', 'mytype';
 print $type;  # shows  {myns}mytype

 # using a compiled routines cache
 use XML::Compile::Cache;   # separate distribution
 my $schema = XML::Compile::Cache->new(...);

 # Show which data-structure is expected
 print $schema->template(PERL => $type);

 # Error handling tricks with Log::Report
 use Log::Report mode => 'DEBUG';  # enable debugging
 dispatcher SYSLOG => 'syslog';    # errors to syslog as well
 try { $reader->($data) };         # catch errors in $@

=chapter DESCRIPTION

This module collects knowledge about one or more schemas.  The most
important method provided is M<compile()>, which can create XML file
readers and writers based on the schema information and some selected
element or attribute type.

Various implementations use the translator, and more can be added
later:

=over 4

=item C<< $schema->compile('READER'...) >> translates XML to HASH

The XML reader produces a HASH from a M<XML::LibXML::Node> tree or an
XML string.  Those represent the input data.  The values are checked.
An error produced when a value or the data-structure is not according
to the specs.

The CODE reference which is returned can be called with anything
accepted by M<dataToXML()>.

Example: create an XML reader

 my $msgin  = $rules->compile(READER => '{myns}mytype');
 # or  ...  = $rules->compile(READER => pack_type('myns', 'mytype'));
 my $xml    = $parser->parse("some-xml.xml");
 my $hash   = $msgin->($xml);

or

 my $hash   = $msgin->('some-xml.xml');
 my $hash   = $msgin->($xml_string);
 my $hash   = $msgin->($xml_node);

with M<XML::Compile::Cache> as schema object:

 $rules->addPrefix(m => 'myns');
 my $hash   = $rules->reader('m:mytype')->($xml);

=item C<< $schema->compile('WRITER', ...) >> translates HASH to XML

The writer produces schema compliant XML, based on a Perl HASH.  To get
the data encoding correctly, you are required to pass a document object
in which the XML nodes may get a place later.

Create an XML writer

 my $doc    = XML::LibXML::Document->new('1.0', 'UTF-8');
 my $write  = $schema->compile(WRITER => '{myns}mytype');
 my $xml    = $write->($doc, $hash);
 print $xml->toString;
 
alternative

 my $write  = $schema->compile(WRITER => 'myns#myid');

with M<XML::Compile::Cache> as schema object:

 $rules->addPrefix(m => 'myns');
 my $xml    = $rules->writer('m:mytype')->($doc, $hash);

=item C<< $schema->template('XML', ...) >> creates an XML example

Based on the schema, this produces an XML message as example.  Schemas
are usually so complex that people loose overview.  This example may
put you back on track, and used as starting point for many creating the
XML version of the message.

=item C<< $schema->template('PERL', ...) >> creates an Perl example

Based on the schema, this produces an Perl HASH structure (a bit
like the output by Data::Dumper), which can be used as template
for creating messages.  The output contains documentation, and is
usually much clearer than the schema itself.

=item C<< $schema->template('TREE', ...) >> creates a parse tree

To be able to produce Perl-text and XML examples, the templater
generates an abstract tree from the schema.  That tree is returned
here.  Be warned that the structure is not fixed over releases:
add regression tests for this to your project.

=back

Be warned that the B<schema is not validated>; you can develop schemas
which do work well with this module, but are not valid according to W3C.
In many cases, however, the translater will refuse to accept mistakes:
mainly because it cannot produce valid code.

The values (both for reading as for writing) are strictly validated.
However, the reader is sloppy with unexpected attributes, and many
other things: that's too expensive to check.

=chapter METHODS

=section Constructors

=c_method new [$xmldata], %options
Details about many name-spaces can be organized with only a single
schema object (actually, the data is administered in an internal
M<XML::Compile::Schema::NameSpaces> object)

The initial information is extracted from the $xmldata source.  The $xmldata
can be anything what is acceptable by M<importDefinitions()>, which
is everything accepted by M<dataToXML()> or an ARRAY of those things.
You may also add any OPTION accepted by M<addSchemas()> to guide the
understanding of the schema.  When no $xmldata is provided, you can add
it later with M<importDefinitions()>

You can specify the hooks before you define the schemas the hooks
work on: all schema information and all hooks are only used when
the readers and writers get compiled.

=option  hook $hook|ARRAY
=default hook C<undef>
See M<addHook()>.  Adds one $hook (HASH) or more at once.

=option  hooks ARRAY
=default hooks []
Add one or more hooks.  See M<addHooks()>.

=option  typemap HASH
=default typemap {}
HASH of Schema type to Perl object or Perl class.  See L</Typemaps>, the
serialization of objects.

=option  key_rewrite HASH|CODE|ARRAY
=default key_rewrite []
Translate XML element local-names into different Perl keys.
See L</Key rewrite>.

=option  ignore_unused_tags BOOLEAN|REGEXP
=default ignore_unused_tags <false>
(WRITER) Usually, a C<mistake> warning is produced when a user provides
a data structure which contains more data than is needed for the XML
message which is created; this will show structural problems.  However,
in some cases, you may want to play tricks with the data-structure and
therefore disable this precausion.

With a REGEXP, you can have more control.  Only keys which do match
the expression will be ignored silently.  Other keys (usually typos
and other mistakes) will get reported.  See L</Typemaps>

=option  block_namespace NAMESPACE|TYPE|HASH|CODE|ARRAY
=default block_namespace []
See M<blockNamespace()>

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->{namespaces} = XML::Compile::Schema::NameSpaces->new;
    $self->SUPER::init($args);

    $self->importDefinitions($args->{top}, %$args)
        if $args->{top};

    $self->{hooks} = [];
    if(my $h1 = $args->{hook})
    {   $self->addHook(ref $h1 eq 'ARRAY' ? @$h1 : $h1);
    }
    if(my $h2 = $args->{hooks})
    {   $self->addHook($_) for ref $h2 eq 'ARRAY' ? @$h2 : $h2;
    }
 
    $self->{key_rewrite} = [];
    if(my $kr = $args->{key_rewrite})
    {   $self->addKeyRewrite(ref $kr eq 'ARRAY' ? @$kr : $kr);
    }

    $self->{block_nss}   = [];
    $self->blockNamespace($args->{block_namespace});

    $self->{typemap}     = $args->{typemap} || {};
    $self->{unused_tags} = $args->{ignore_unused_tags};

    $self;
}

#--------------------------------------

=section Accessors

=method addHook $hook|LIST|undef
A $hook is specified as HASH or a LIST of PAIRS.  When C<undef>, this call
is ignored. See M<addHooks()> and L</Schema hooks> below.
=cut

sub addHook(@)
{   my $self = shift;
    push @{$self->{hooks}}, @_>1 ? {@_} : defined $_[0] ? shift : ();
    $self;
}

=method addHooks $hook, [$hook, ...]
Add multiple hooks at once.  These must all be HASHes. See L</Schema hooks>
and M<addHook()>. C<undef> values are ignored.
=cut

sub addHooks(@)
{   my $self = shift;
    $self->addHook($_) for @_;
    $self;
}

=method hooks [<'READER'|'WRITER'>]
Returns the LIST of defined hooks (as HASHes).
[1.36] When an action parameter is provided, it will only return a list
with hooks added with that action value or no action at all.
=cut

sub hooks(;$)
{   my $hooks = shift->{hooks};
    my $dir   = shift or return @$hooks;
    grep +(!$_->{action} || $_->{action} eq $dir), @$hooks;
}

=method addTypemaps PAIRS
Add new XML-Perl type relations.  See L</Typemaps>.
=method addTypemap PAIR
Synonym for M<addTypemap()>.
=cut

sub addTypemaps(@)
{   my $map = shift->{typemap};
    while(@_ > 1)
    {   my $k = shift;
        $map->{$k} = shift;
    }
    $map;
}
*addTypemap = \&addTypemaps;

=method addSchemas $xml, %options
Collect all the schemas defined in the $xml data.  The $xml parameter
must be a M<XML::LibXML> node, therefore it is advised to use
M<importDefinitions()>, which has a much more flexible way to
specify the data.

When the object extends M<XML::Compile::Cache>, the prefixes declared
on the schema element will be taken as default prefixes.

=option  source STRING
=default source C<undef>
An indication where this schema data was found.  If you use M<dataToXML()>
in LIST context, you get such an indication.

=option  filename FILENAME
=default filename C<undef>
Explicitly state from which file the data is coming.

=option  element_form_default 'qualified'|'unqualified'
=default element_form_default <undef>
Overrule the default as found in the schema.  Many old schemas (like
WSDL11 and SOAP11) do not specify the correct default element form in
the schema but only in the text.

=option  attribute_form_default 'qualified'|'unqualified'
=default attribute_form_default <undef>

=option  target_namespace NAMESPACE
=default target_namespace <undef>
Overrule (or set) the target namespace in the schema.

=cut

sub addSchemas($@)
{   my ($self, $node, %opts) = @_;
    defined $node or return ();

    my @nsopts;
    foreach my $o (qw/source filename target_namespace
        element_form_default attribute_form_default/)
    {   push @nsopts, $o => delete $opts{$o} if exists $opts{$o};
    }

    UNIVERSAL::isa($node, __PACKAGE__)
        and error __x"use useSchema(), not addSchemas() for a {got} object"
             , got => ref $node;

    UNIVERSAL::isa($node, 'XML::LibXML::Node')
        or error __x"addSchema() requires an XML::LibXML::Node";

    $node = $node->documentElement
        if $node->isa('XML::LibXML::Document');

    my $nss = $self->namespaces;
    my @schemas;

    $self->walkTree
    ( $node,
      sub { my $this = shift;
            return 1 unless $this->isa('XML::LibXML::Element')
                         && $this->localName eq 'schema';

            my $schema = XML::Compile::Schema::Instance->new($this, @nsopts)
                or next;

            $nss->add($schema);
            push @schemas, $schema;
            return 0;
          }
    );
    @schemas;
}

=method useSchema $schema, [$schema, ...]
Pass a M<XML::Compile::Schema> object, or extensions like
M<XML::Compile::Cache>, to be used as definitions as well.  First,
elements are looked-up in the current schema definition object.  If not
found the other provided $schema objects are checked in the order as
they were added.

Searches for definitions do not recurse into schemas which are used
by the used schema.

=example use other Schema
  my $wsdl = XML::Compile::WSDL->new($wsdl);
  my $geo  = Geo::GML->new(version => '3.2.1');
  # both $wsdl and $geo extend XML::Compile::Schema

  $wsdl->useSchema($geo);
=cut

sub useSchema(@)
{   my $self = shift;
    foreach my $schema (@_)
    {   error __x"useSchema() accepts only {pkg} extensions, not {got}"
          , pkg => __PACKAGE__, got => (ref $schema || $schema);
        $self->namespaces->use($schema);
    }
    $self;
}

=method addKeyRewrite $predef|CODE|HASH, ...
Add new rewrite rules to the existing list (initially provided with
M<new(key_rewrite)>).  The whole list of rewrite rules is returned.

C<PREFIXED> rules will be applied first.  Special care is taken that the
prefix will not be called twice.  The last added set of rewrite rules
will be applied first.  See L</Key rewrite>.

=cut

sub addKeyRewrite(@)
{   my $self = shift;
    unshift @{$self->{key_rewrite}}, @_;
    defined wantarray ? $self->_key_rewrite(undef) : ();
}

sub _key_rewrite($)
{   my $self = shift;
    my @more = map { ref $_ eq 'ARRAY' ? @$_ : defined $_ ? $_ : () } @_;

    my ($pref_all, %pref, @other);
    foreach my $rule (@more, @{$self->{key_rewrite}})
    {   if($rule eq 'PREFIXED') { $pref_all++ }
        elsif($rule =~ m/^PREFIXED\((.*)\)/) { $pref{$_}++ for split /\,/, $1 }
        else { push @other, $rule }
    }

    ( ( $pref_all  ? 'PREFIXED'
      : keys %pref ? 'PREFIXED('.join(',', sort keys %pref).')'
      : ()), @other );
}

=method blockNamespace $ns|$type|HASH|CODE|ARRAY

Block all references to a $ns or full $type, as if they do not appear
in the schema.  Specially useful if the schema includes references to
old (deprecated) versions of itself which are not being used.  It can
also be used to block inclusion of huge structures which are not used,
for increased compile performance, or to avoid buggy constructs.

These values can also be passed with M<new(block_namespace)> and
M<compile(block_namespace)>.

=cut

sub blockNamespace(@)
{   my $self = shift;
    push @{$self->{block_nss}}, @_;
}

sub _block_nss(@)
{   my $self = shift;
    grep defined, map {ref $_ eq 'ARRAY' ? @$_ : $_}
        @_, @{$self->{block_nss}};
}

#--------------------------------------

=section Compilers

=method compile <'READER'|'WRITER'>, $type, %options

Translate the specified ELEMENT (found in one of the read schemas) into
a CODE reference which is able to translate between XML-text and a HASH.
When the $type is C<undef>, an empty LIST is returned.

The indicated $type is the starting-point for processing in the
data-structure, a toplevel element or attribute name.  The name must
be specified in C<{url}name> format, there the url is the name-space.
An alternative is the C<url#id> which refers to an element or type with
the specific C<id> attribute value.

When a READER is created, a CODE reference is returned which needs
to be called with XML, as accepted by M<XML::Compile::dataToXML()>.
Returned is a nested HASH structure which contains the data from
contained in the XML.  The transformation rules are explained below.

When a WRITER is created, a CODE reference is returned which needs
to be called with an M<XML::LibXML::Document> object and a HASH, and
returns a M<XML::LibXML::Node>.

Many %options below are B<explained in more detailed> in the manual-page
M<XML::Compile::Translate>, which implements the compilation.

=option  validation BOOLEAN
=default validation <true>
XML message must be validated, to lower the chance on abuse.  However,
of course, it costs performance which is only partially compensated by
fewer checks in your code.  This flag overrules the C<check_values>,
C<check_occurs>, and C<ignore_facets>.

=option  check_values BOOLEAN
=default check_values <true>
Whether code will be produce to check that the XML fields contain
the expected data format.

Turning this off will improve the processing speed significantly, but is
(of course) much less safe.  Do not set it off when you expect data from
external sources: validation is a crucial requirement for XML.

=option  check_occurs BOOLEAN
=default check_occurs <true>
Whether code will be produced to do bounds checking on elements and blocks
which may appear more than once. When the schema says that maxOccurs is 1,
then that element becomes optional.  When the schema says that maxOccurs
is larger than 1, then the output is still always an ARRAY, but now of
unrestricted length.

=option  ignore_facets BOOLEAN
=default ignore_facets <false>
Facets influence the formatting and range of values. This does
not come cheap, so can be turned off.  It affects the restrictions
set for a simpleType.  The processing speed will improve, but validation
is a crucial requirement for XML: please do not turn this off when the
data comes from external sources.

=option  path STRING
=default path <expanded name of type>
Prepended to each error report, to indicate the location of the
error in the XML-Scheme tree.

=option  elements_qualified C<TOP>|C<ALL>|C<NONE>|BOOLEAN
=default elements_qualified <undef>
When defined, this will overrule the use of namespaces (as prefix) on
elements in all schemas.  When C<ALL> or a true value is given, then all
elements will be used qualified.  When C<NONE> or a false value is given,
the XML will not produce or process prefixes on any element.

All top-level elements (and attributes) will be used in a name-space
qualified way, if they have a targetNamespace.  Some applications require
some global element with qualification, so refuse global elements which
have no qualification.  Using the C<TOP> setting, the compiler checks
that the targetNamespace exists.

The C<form> attributes in the schema will be respected; overrule the
effects of this option.  Use hooks when you need to fix name-space use
in more subtile ways.

With C<element_form_default>, you can correct whole
schema's about their name-space behavior.

Change in [1.44]: C<TOP> before enforced a name-space on the top-level.
There should always be a name-space on the top element.  It got changed
into that C<TOP> checks that the globals have a targetNamespace.

=option  attributes_qualified C<ALL>|C<NONE>|BOOLEAN
=default attributes_qualified <undef>
[1.44] Like option C<elements_qualified>, but then for attributes.

=option  prefixes HASH|ARRAY-of-PAIRS
=default prefixes {}
Can be used to pre-define prefixes for namespaces (for 'WRITER' or
key rewrite) for instance to reserve common abbreviations like C<soap>
for external use.  Each entry in the hash has as key the namespace uri.
The value is a hash which contains C<uri>, C<prefix>, and C<used> fields.
Pass a reference to a private hash to catch this index.  An ARRAY with
prefix, uri PAIRS is simpler.

 prefixes => [ mine => $myns, two => $twons ]
 prefixes => { $myns => 'mine', $twons => 'two' }

 # the previous is short for:
 prefixes => { $myns  => [ uri => $myns, prefix => 'mine', used => 0 ]
             , $twons => [ uri => $twons, prefix => 'two', ...] };

=option  output_namespaces HASH|ARRAY-of-PAIRS
=default output_namespaces undef
[Pre-0.87] name for the C<prefixes> option.  Deprecated.

=option  include_namespaces BOOLEAN|CODE
=default include_namespaces <true>
[writer] Indicates whether the namespace declaration should be included
on the top-level element.  If not, you may continue with the same
name-space table to combine various XML components into one, and add the
namespaces later.  No namespace definition can be added the production
rule produces an attribute.

When a CODE reference is passed, it will be called for each namespace
to decide whether it should be included or not. When true, it will
we added. The CODE is called with a namespace, its prefix, and the
number of times it was used for that schema element translator.

=option  namespace_reset BOOLEAN
=default namespace_reset <false>
[writer] Use the same prefixes in C<prefixes> as with some other compiled
piece, but reset the counts to zero first.

=option  use_default_namespace BOOLEAN
=default use_default_namespace <false>
[0.91, writer] When mixing qualified and unqualified namespaces, then the use of
a default namespace can be quite confusing: a name-space without prefix.
Therefore, by default, all qualified elements will have an explicit prefix.

=option  sloppy_integers BOOLEAN
=default sloppy_integers <false>
[reader] The XML C<integer> data-types must support at least 18 digits,
which is larger than Perl's 32 bit internal integers.  Therefore, the
implementation will use M<Math::BigInt> objects to handle them.  However,
often an simple C<int> type whould have sufficed, but the XML designer
was lazy.  A long is much faster to handle.  Set this flag to use C<int>
as fast (but inprecise) replacements.

Be aware that C<Math::BigInt> and C<Math::BigFloat> objects are nearly
but not fully transparently mimicking the behavior of Perl's ints and
floats.  See their respective manual-pages.  Especially when you wish
for some performance, you should optimize access to these objects to
avoid expensive copying which is exactly the spot where the differences
are.

You can also improve the speed of Math::BigInt by installing
Math::BigInt::GMP.  Add C<< use Math::BigInt try => 'GMP'; >> to the
top of your main script to get more performance.

=option  sloppy_floats BOOLEAN
=default sloppy_floats <false>
[reader] The float types of XML are all quite big, and support NaN, INF,
and -INF.  Perl's normal floats do not, and therefore M<Math::BigFloat>
is used.  This, however, is slow.  When true, you will crash on any value
which is not understood by Perl's default float... but run much faster.
See also C<sloppy_integers>.

=option  any_element CODE|'TAKE_ALL'|'SKIP_ALL'
=default any_element C<undef>
[0.89, reader] In general, C<any> schema components cannot be handled
automatically.  If  you need to create or process any information, then
read about wildcards in the DETAILS chapter of the manual-page for the
specific back-end.
[pre-0.89] this option was named C<anyElement>, which will still work.

=option  any_attribute CODE|'TAKE_ALL'|'SKIP_ALL'
=default any_attribute C<undef>
[0.89, reader] In general, C<anyAttribute> schema components cannot be handled
automatically.  If  you need to create or process anyAttribute
information, then read about wildcards in the DETAILS chapter of the
manual-page for the specific back-end.
[pre-0.89] this option was named C<anyElement>, which will still work.

=option  any_type CODE
=default any_type <returns string or node>
[1.07] how to handle "anyType" type elements.  Supported values depends
on the backend, specializations of M<XML::Compile::Translate>.

=option  hook $hook|ARRAY-OF-hooks
=default hook C<undef>
Define one or more processing $hooks.  See L</Schema hooks> below.
These hooks are only active for this compiled entity, where M<addHook()>
and M<addHooks()> can be used to define hooks which are used for all
results of M<compile()>.  The hooks specified with the C<hook> or C<hooks>
option are run before the global definitions.

=option  hooks $hook|ARRAY-OF-hooks
=default hooks C<undef>
Alternative for option C<hook>.

=option  permit_href BOOLEAN
=default permit_href <false>
[reader] When parsing SOAP-RPC encoded messages, the elements may have
a C<href> attribute pointing to an object with C<id>.  The READER will
return the unparsed, unresolved node when the attribute is detected,
and the SOAP-RPC decoder will have to discover and resolve it.

=option  ignore_unused_tags BOOLEAN|REGEXP
=default ignore_unused_tags <false>
[writer] Overrules what is set with M<new(ignore_unused_tags)>.

=option  interpret_nillable_as_optional BOOLEAN
=default interpret_nillable_as_optional <false>
Found in the schema wild-life: people who think that nillable means
optional.  Not too hard to fix.  For the WRITER, you still have to state
NIL explicitly, but the elements are not constructed.  The READER will
output NIL when the nillable elements are missing.

=option  typemap HASH
=default typemap {}
Add this typemap to the relations defined by M<new(typemap)> or
M<addTypemaps()>

=option  mixed_elements CODE|PREDEFINED
=default mixed_elements 'ATTRIBUTES'
[reader] What to do when mixed schema elements are to be processed.  Read
more in the L</DETAILS> section below.

=option  key_rewrite HASH|CODE|ARRAY
=default key_rewrite []
Add key rewrite rules to the front of the list of rules, as set by
M<new(key_rewrite)> and M<addKeyRewrite()>.  See L</Key rewrite>

=option  default_values 'MINIMAL'|'IGNORE'|'EXTEND'
=default default_values <depends on backend>
[reader] How to treat default values as provided by the schema.
With C<IGNORE> (the writer default), you will see exactly what is
specified in the XML or HASH.  With C<EXTEND> (the reader default) will
show the default and fixed values in the result.  C<MINIMAL> does remove
all fields which are the same as the default setting: simplifies.
See L</Default Values>.

=option  abstract_types 'ERROR'|'ACCEPT'
=default abstract_types 'ERROR'
How to handle the use abstract types.  Of course, they should not be
used, but sometime they accidentally are.  When set to C<ERROR>, an error
will be produced whenever an abstract type is encountered.
C<ACCEPT> will ignore the fact that the types are abstract, and treat
them as non-abstract types.

=option  block_namespace NAMESPACE|TYPE|HASH|CODE|ARRAY
=default block_namespace []
[reader] See M<blockNamespace()>.

=option  xsi_type HASH
=default xsi_type {}
See L</Handling xsi:type>.  The HASH maps types as mentioned in the schema,
to extensions of those types which are addressed via the horrible C<xsi:type>
construct.  When you specify C<AUTO> as value for some type, the translator
tries collect possible xsi:type values from the loaded schemas. This may be
slow and may produce imperfect results.

=option  xsi_type_everywhere BOOLEAN
=default xsi_type_everywhere <false>
[1.48, writer] Add an C<xsi:type> attribute to all elements, for instance as
used in SOAP RPC/encoded.  The type added is the type according to the
schema, unless the C<xsi:type> is already present on an element for
some other reason.

Be aware that this option has a different purpose from C<xsi_type>.
In this case, we do add exactly the type specified in the xsd to each
element which does not have an C<xsi:type> attribute yet.  The C<xsi_type>
on the other hand, implements the (mis-)feature that the element's
content may get replaced by any extended type with this dynamic flag.

=option  json_friendly BOOLEAN
=default json_friendly <false>
[1.55] When enabled, booleans will be blessed in M<Types::Serialiser>
booleans.  Floats get nummified.  Together, this will make the output
of the reader usable as JSON without any further conversion.

=cut

sub compile($$@)
{   my ($self, $action, $type, %args) = @_;
    defined $type or return ();

    if(exists $args{validation})
    {   $args{check_values}  =   $args{validation};
        $args{check_occurs}  =   $args{validation};
        $args{ignore_facets} = ! $args{validation};
    }
    else
    {   exists $args{check_values} or $args{check_values} = 1;
        exists $args{check_occurs} or $args{check_occurs} = 1;
    }

    my $iut = exists $args{ignore_unused_tags}
      ? $args{ignore_unused_tags} : $self->{unused_tags};

    $args{ignore_unused_tags}
      = !defined $iut ? undef : ref $iut eq 'Regexp' ? $iut : qr/^/;

    exists $args{include_namespaces}
        or $args{include_namespaces} = 1;

    if($args{sloppy_integers} ||= 0)
    {   eval "require Math::BigInt";
        panic "require Math::BigInt or sloppy_integers:\n$@"
            if $@;
    }

    if($args{sloppy_floats} ||= 0)
    {   eval "require Math::BigFloat";
        panic "require Math::BigFloat by sloppy_floats:\n$@" if $@;
    }

    if($args{json_friendly} ||= 0)
    {   eval "require Types::Serialiser";
        panic "require Types::Serialiser by json_friendly:\n$@" if $@;
    }

    $args{prefixes} = $self->_namespaceTable
      (($args{prefixes} || $args{output_namespaces})
      , $args{namespace_reset}
      , !($args{use_default_namespace} || $args{use_default_prefix})
        # use_default_prefix renamed in 0.90
      );

    my $nss   = $self->namespaces;

    my ($h1, $h2) = (delete $args{hook}, delete $args{hooks});
    my @hooks = $self->hooks($action);
    push @hooks, ref $h1 eq 'ARRAY' ? @$h1 : $h1 if $h1;
    push @hooks, ref $h2 eq 'ARRAY' ? @$h2 : $h2 if $h2;

    my %map = ( %{$self->{typemap}}, %{$args{typemap} || {}} );
    trace "schema compile $action for $type";

    my @rewrite = $self->_key_rewrite(delete $args{key_rewrite});
    my @blocked = $self->_block_nss(delete $args{block_namespace});

    $args{abstract_types} ||= 'ERROR';
    $args{mixed_elements} ||= 'ATTRIBUTES';
    $args{default_values} ||= $action eq 'READER' ? 'EXTEND' : 'IGNORE';

    # Option rename in 0.88
    $args{any_element}    ||= delete $args{anyElement};
    $args{any_attribute}  ||= delete $args{anyAttribute};

    if(my $xi = $args{xsi_type})
    {   my $nss = $self->namespaces;
        foreach (keys %$xi)
        {   $xi->{$_} = $nss->autoexpand_xsi_type($_) if $xi->{$_} eq 'AUTO';
        }
    }

    my $transl = XML::Compile::Translate->new
     ( $action
     , nss     => $self->namespaces
     );

    $transl->compile
     ( $type, %args
     , hooks    => \@hooks
     , typemap  => \%map
     , rewrite  => \@rewrite
     , block_namespace => \@blocked
     );
}

# also used in ::Cache init()
sub _namespaceTable($;$$)
{   my ($self, $table, $reset_count, $block_default) = @_;
    $table = { reverse @$table }
        if ref $table eq 'ARRAY';

    $table->{$_}    = { uri => $_, prefix => $table->{$_} }
        for grep ref $table->{$_} ne 'HASH', keys %$table;

    if($reset_count)
    {   $_->{used} = 0 for values %$table;
    }

    $table->{''}    = {uri => '', prefix => '', used => 0}
        if $block_default && !grep $_->{prefix} eq '', values %$table;

    # very strong preference for 'xsi'
    $table->{&SCHEMA2001i} = {uri => SCHEMA2001i, prefix => 'xsi', used => 0};

    $table;
}

=method compileType <'READER'|'WRITER'>, $type, %options
This is a hack to be able to process components of SOAP messages, which
are only specified by type.  Probably (hopefully) you do no need it.
All %options are the same as for M<compile()>.
=cut

sub compileType($$@)
{   my ($self, $action, $type, %args) = @_;

    # translator can only create elements, not types.
    my $elem           = delete $args{element} || $type;
    my ($ens, $elocal) = unpack_type $elem;
    my ($ns, $local)   = unpack_type $type;

    my $SchemaNS = SCHEMA2001;

    my $defs     = $ns ? <<_DIRTY_TRICK1 : <<_DIRTY_TRICK2;
<schema xmlns="$SchemaNS"
   targetNamespace="$ens"
   xmlns:tns="$ns">
  <element name="$elocal" type="tns:$local" />
</schema>
_DIRTY_TRICK1
<schema xmlns="$SchemaNS"
   targetNamespace="$ens"
   elementFormDefault="unqualified"
   >
  <element name="$elocal" type="$local" />
</schema>
_DIRTY_TRICK2

    $self->importDefinitions($defs);
    $self->compile($action, $elem, %args);
}

=method template <'XML'|'PERL'|'TREE'>, $element, %options

Schema's can be horribly complex and unreadible.  Therefore, this template
method can be called to create an example which demonstrates how data
of the specified $element shown as XML or Perl is organized in practice.

The 'TREE' template returns the intermediate parse tree, which gets
formatted into the XML or Perl example.  This is not a stable interface:
it may change without much notice.

Some %options are explained in M<XML::Compile::Translate>.  There are
some extra %options defined for the final output process.

The templates produced are B<not always correct>.  Please contribute
improvements: read and understand the comments in the text.

=option  elements_qualified 'ALL'|'TOP'|'NONE'|BOOLEAN
=default elements_qualified <undef>

=option  attributes_qualified BOOLEAN
=default attributes_qualified <undef>

=option  include_namespaces BOOLEAN|CODE
=default include_namespaces <true>

=option  show_comments STRING|'ALL'|'NONE'
=default show_comments C<ALL>
A comma separated list of tokens, which explain what kind of comments need
to be included in the output.  The available tokens are: C<struct>, C<type>,
C<occur>, C<facets>.  A value of C<ALL> will select all available comments.
The C<NONE> or empty string will exclude all comments.

=option  indent STRING
=default indent "  "
The leading indentation string per nesting.  Must start with at least one
blank.

=option  abstract_types 'ERROR'|'ACCEPT'
=default abstract_types 'ERROR'
By default, do not show abstract types in the output.

=option  skip_header BOOLEAN
=default skip_header <false>
Skip the comment header from the output.

=option  key_rewrite HASH|CODE|ARRAY
=default key_rewrite []

=option  output_style 1|2
=default output_style 1
[1.61] Style 2 is a little different.
=cut

sub template($@)
{   my ($self, $action, $type, %args) = @_;

    my ($to_perl, $to_xml)
      = $action eq 'PERL' ? (1, 0)
      : $action eq 'XML'  ? (0, 1)
      : $action eq 'TREE' ? (0, 0)
      : error __x"template output is either in XML or PERL layout, not '{action}'"
        , action => $action;

    my $show
      = exists $args{show_comments} ? $args{show_comments}
      : exists $args{show} ? $args{show} # pre-0.79 option name 
      : 'ALL';

    $show    = 'struct,type,occur,facets' if $show eq 'ALL';
    $show    = '' if $show eq 'NONE';
    my %show = map {("show_$_" => 1)} split m/\,/, $show;
    my $nss  = $self->namespaces;

    my $indent                  = $args{indent} || "  ";
    $args{check_occurs}         = 1;
    $args{mixed_elements}     ||= 'ATTRIBUTES';
    $args{default_values}     ||= 'EXTEND';
    $args{abstract_types}     ||= 'ERROR';

    exists $args{include_namespaces}
        or $args{include_namespaces} = 1;

    # it could be used to add extra comment lines
    error __x"typemaps not implemented for XML template examples"
        if $to_xml && defined $args{typemap} && keys %{$args{typemap}};

    my @rewrite = $self->_key_rewrite(delete $args{key_rewrite});
    my @blocked = $self->_block_nss(delete $args{block_namespace});

    my $table   = $args{prefixes} = $self->_namespaceTable
      (($args{prefixes} || $args{output_namespaces})
      , $args{namespace_reset}
      , !$args{use_default_namespace}
      );

    my $used = $to_xml && $show{show_type};
    $table->{&SCHEMA2001}
       ||= +{prefix => 'xs',  uri => SCHEMA2001,  used => $used};
    $table->{&SCHEMA2001i}
       ||= +{prefix => 'xsi', uri => SCHEMA2001i, used => $used};

    my $transl  = XML::Compile::Translate->new
     ( 'TEMPLATE'
     , nss         => $self->namespaces
     );

    my $compiled = $transl->compile
     ( $type
     , %args
     , rewrite         => \@rewrite
     , block_namespace => \@blocked   # not yet supported
     , output          => $action
     );
    $compiled or return;

    my $ast = $compiled->();
#use Data::Dumper; $Data::Dumper::Indent = 1; warn Dumper $ast;

    if($to_perl)
    {   return $transl->toPerl($ast, %show, indent => $indent
          , skip_header => $args{skip_header})
    }

    if($to_xml)
    {   my $doc  = XML::LibXML::Document->new('1.1', 'UTF-8');
        my $node = $transl->toXML($doc, $ast, %show
          , indent => $indent, skip_header => $args{skip_header});
        return $node->toString(1);
    }

    # return tree
    $ast;
}

#------------------------------------------

=section Administration

=method namespaces
Returns the M<XML::Compile::Schema::NameSpaces> object which is used
to collect schemas.
=cut

sub namespaces() { shift->{namespaces} }

=method importDefinitions $xmldata, %options
Import (include) the schema information included in the $xmldata.  The
$xmldata must be acceptable for M<dataToXML()>.  The resulting node
and all the %options are passed to M<addSchemas()>. The schema node does
not need to be the top element: any schema node found in the data
will be decoded.

Returned is a list of M<XML::Compile::Schema::Instance> objects,
for each processed schema component.

If your program imports the same string or file definitions multiple
times, it will re-use the schema information from the first import.
This removal of duplications will not work for open files or pre-parsed
XML structures.

As an extension to the handling M<dataToXML()> provides, you can specify an
ARRAY of things which are acceptable to C<dataToXML>.  This way, you can
specify multiple resources at once, each of which will be processed with
the same %options.

=option  details HASH
=default details <from XMLDATA>
Overrule the details information about the source of the data.

=examples of use of importDefinitions
  my $schema = XML::Compile::Schema->new;
  $schema->importDefinitions('my-spec.xsd');

  my $other = "<schema>...</schema>";  # use 'HERE' documents!
  my @specs = ('my-spec.xsd', 'types.xsd', $other);
  $schema->importDefinitions(\@specs, @options);
=cut

# The cache will certainly avoid penalties by the average module user,
# which does not understand the sharing schema definitions between objects
# especially in SOAP implementations.
my (%schemaByFilestamp, %schemaByChecksum);

sub importDefinitions($@)
{   my ($self, $frags, %options) = @_;
    my @data = ref $frags eq 'ARRAY' ? @$frags : $frags;

    # this is a horrible hack, but by far the simpelest solution to
    # avoid dataToXML process the same info twice.
    local $self->{_use_cache} = 1;

    my @schemas;
    foreach my $data (@data)
    {   defined $data or next;
        my ($xml, %details) = $self->dataToXML($data);
        %details = %{delete $options{details}} if $options{details};

        if(defined $xml)
        {   my @added = $self->addSchemas($xml, %details, %options);
            if(my $checksum = $details{checksum})
            {   $self->{_cache_checksum}{$checksum} = \@added;
            }
            elsif(my $filestamp = $details{filestamp})
            {   $self->{_cache_file}{$filestamp} = \@added;
            }
            push @schemas, @added;
        }
        elsif(my $filestamp = $details{filestamp})
        {   my $cached = $self->{_cache_file}{$filestamp};
            $self->namespaces->add(@$cached);
        }
        elsif(my $checksum = $details{checksum})
        {   my $cached = $self->{_cache_checksum}{$checksum};
            $self->namespaces->add(@$cached);
        }
    }
    @schemas;
}

sub _parseScalar($)
{   my ($thing, $data) = @_;

    ref $thing && $thing->{_use_cache}
        or return $thing->SUPER::_parseScalar($data);

    my $self = $thing;
    my $checksum = md5_hex $$data;
    if($self->{_cache_checksum}{$checksum})
    {   trace "reusing string data with checksum $checksum";
        return (undef, checksum => $checksum);
    }

    trace "cache parsed scalar with checksum $checksum";

    ( $self->SUPER::_parseScalar($data)
    , checksum => $checksum
    );
}

sub _parseFile($)
{   my ($thing, $fn) = @_;

    ref $thing && $thing->{_use_cache}
        or return $thing->SUPER::_parseFile($fn);
    my $self = $thing;

    my ($mtime, $size) = (stat $fn)[9,7];
    my $filestamp = File::Spec->rel2abs($fn) . '-'. $mtime . '-' . $size;

    if($self->{_cache_file}{$filestamp})
    {   trace "reusing schemas from file $filestamp";
        return (undef, filestamp => $filestamp);
    }

    trace "cache parsed file $filestamp";

    ( $self->SUPER::_parseFile($fn)
    , filestamp => $filestamp
    );
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

=method printIndex [$fh], %options
Print all the elements which are defined in the schemas to the $fh
(by default the selected handle).  %options are passed to
M<XML::Compile::Schema::NameSpaces::printIndex()> and
M<XML::Compile::Schema::Instance::printIndex()>.

=cut

sub printIndex(@)
{   my $self = shift;
    $self->namespaces->printIndex(@_);
}

=method doesExtend $exttype, $basetype
Returns true when the $exttype extends the $basetype. See
M<XML::Compile::Schema::NameSpaces::doesExtend()>
=cut

sub doesExtend($$)
{   my $self = shift;
    $self->namespaces->doesExtend(@_);
}

=chapter DETAILS

=section Collecting definitions

When starting an application, you will need to read the schema
definitions.  This is done by instantiating an object via
M<XML::Compile::Schema::new()> or M<XML::Compile::WSDL11::new()>.
The WSDL11 object has a schema object internally.

Schemas may contains C<import> and C<include> statements, which
specify other resources for definitions.  In the idea of the XML design
team, those files should be retrieved automatically via an internet
connection from the C<schemaLocation>.  However, this is a bad concept; in
XML::Compile modules you will have to explicitly provide filenames on local
disk using M<importDefinitions()> or M<XML::Compile::WSDL11::addWSDL()>.

There are various reasons why I, the author of this module, think the
dynamic automatic internet imports are a bad idea.  First: you do not
always have a working internet connection (travelling with a laptop in
a train).  Your implementation should work the same way under all
environmental circumstances!  Besides, I do not trust remote files on
my system, without inspecting them.  Most important: I want to run my
regression tests before using a new version of the definitions, so I do
not want to have a remote server change the agreements without my
knowledge.

So: before you start, you will need to scan (recursively) the initial
schema or wsdl file for C<import> and C<include> statements, and
collect all these files from their C<schemaLocation> into files on
local disk.  In your program, call M<importDefinitions()> on all of
them -in any order- before you call M<compile()>.

=subsection Organizing your definitions

One nice feature to help you organize (especially useful when you
package your code in a distribution), is to add these lines to the
beginning of your code:

  package My::Package;
  XML::Compile->addSchemaDirs(__FILE__);
  XML::Compile->knownNamespace('http://myns' => 'myns.xsd', ...);

Now, if the package file is located at C<SomeThing/My/Package.pm>,
the definion of the namespace should be kept in
C<SomeThing/My/Package/xsd/myns.xsd>.

Somewhere in your program, you have to load these definitions:

  # absolute or relative path is always possible
  $schema->importDefinitions('SomeThing/My/Package/xsd/myns.xsd');

  # relative search path extended by addSchemaDirs
  $schema->importDefinitions('myns.xsd');

  # knownNamespace improves abstraction
  $schema->importDefinitions('http://myns');

Very probably, the namespace is already in some variable:

  use XML::Compile::Schema;
  use XML::Compile::Util  'pack_type';

  my $myns   = 'http://some-very-long-uri';
  my $schema = XML::Compile::Schema->new($myns);
  my $mytype = pack_type $myns, $myelement;
  my $reader = $schema->compileClient(READER => $mytype);

=section Addressing components

Normally, external users can only address elements within a schema,
and types are hidden to be used by other schemas only.  For this
reason, it is permitted to create an element and a type with the
same name.

The compiler requires a starting-point.  This can either be an
element name or an element's id.  The format of the element name
is C<{namespace-uri}localname>, for instance

 {http://library}book

You may also start with

 http://www.w3.org/2001/XMLSchema#float

as long as this ID refers to a top-level element, not a type.

When you use a schema without C<targetNamespace> (which is bad practice,
but sometimes people really do not understand the beneficial aspects of
the use of namespaces) then the elements can be addressed as C<{}name>
or simple C<name>.

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

=subsection simpleType

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

With reader hook C<< after => 'XML_NODE' >> hook applied, it will become

 test1 => { _ => 42
          , _XML_NODE => $obj
          }
 
=subsection complexType/simpleContent

In this case, the single value container may have attributes.  The number
of attributes can be endless, and the value is only one.  This value
has no name, and therefore gets a predefined name C<_>.

When passed to the writer, you may specify a single value (not the whole
HASH) when no attributes are used.

=example typical simpleContent example

In XML, this looks like this:

 <test2 question="everything">42</test2>

As a HASH, this shows as

 test2 => { _ => 42
          , question => 'everything'
          }

When specified in the writer, when no attributes are need, you can use
either form:

  test3 => { _ => 7 }
  test3 => 7

=subsection complexType and complexType/complexContent

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

=subsection Manually produced XML NODE

For a WRITER, you may also specify a XML::LibXML::Node anywhere.

 test1 => $doc->createTextNode('42');
 test3 => $doc->createElement('ariba');

This data-structure is used without validation, so you are fully on
your own with this one. Typically, nodes are produced by hooks to
implement work-arounds.

=subsection Occurence

A second factor which determines the data-structure is the element
occurrence.  Usually, elements have to appear once and exactly once
on a certain location in the XML data structure.  This order is
automatically produced by this module. But elements may appear multiple
times.

=over 4

=item usual case
The default behavior for an element (in a sequence container) is to
appear exactly once.  When missing, this is an error.

=item maxOccurs larger than 1
In this case, the element or particle block can appear multiple times.
Multiple values are kept in an ARRAY within the HASH.  Non-schema based
XML modules do not return a single value as an ARRAY, which makes that
code more complicated.  But in our case, we know the expected amount
beforehand.

When the maxOccurs larger than 1 is specified for an element, an ARRAY
of those elements is produced.  When it is specified for a block (sequence,
choice, all, group), then an ARRAY of HASHes is returned.  See the special
section about this subject.

An error is produced when the number of elements found is less than
C<minOccurs> (defaults to 1) or more than C<maxOccurs> (defaults to 1),
unless M<compile(check_occurs)> is C<false>.

Example elements with maxOccurs larger than 1. In the schema:

 <element name="a" type="int" maxOccurs="unbounded" />
 <element name="b" type="int" />

In the XML message:

 <a>12</a><a>13</a><b>14</b>

In the Perl representation:

 a => [12, 13], b => 14

=item value is C<NIL>
When an element is nillable, that is explicitly represented as a C<NIL>
constant string.

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

=subsection Default Values

[added in v0.91]
With M<compile(default_values)> you can control how much information about
default values defined by the schema will be passed into your program.

The choices, available for both READER and WRITER, are:

=over 4

=item C<IGNORE>   (the WRITER's standard behavior)
Only include element and attribute values in the result if they are in
the XML message.  Behaviorally, this treats elements with default values
as if they are just optional.  The WRITER does not try to be smarter than
you.

=item C<EXTEND>   (the READER's standard behavior)
If some element or attribute is not in the source but has a default in
the schema, that value will be produced.  This is very convenient for the
READER, because your application does not have to hard-code the same
constant values as defaults as well.

=item C<MINIMAL>
Only produce the values which differ from the defaults.  This choice is
useful when producing XML, to reduce the size of the output.
=back

=example use of default_values EXTEND

Let us process a schema using the schema schema.  A schema file can
contain lines like this:  

 <element minOccurs="0" ref="myelem"/>

In mode C<EXTEND> (the READER default), this gets translated into:

 element => { ref => 'myelem', maxOccurs => 1
            , minOccurs => 0, nillable => 0 };

With C<EXTEND> in the READER, all schema information is used to provide
a complete overview of available information.  Your code does not need
to check whether the attributes were available or not: attributes with
defaults or fixed values are automatically added.

Again mode C<EXTEND>, now for the writer:

 element => { ref => 'myelem', minOccurs => 0 };
 <element minOccurs="0" maxOccurs="1" ref="myelem" nillable="0"/>

=example use of default_values IGNORE

With option C<default_values> set to C<IGNORE> (the WRITER default), you
would get

 element => { ref => 'myelem', maxOccurs => 1, minOccurs => 0 }
 <element minOccurs="0" maxOccurs="1" ref="myelem"/>

The same in both translation directions.
The nillable attribute is not used, so will not be shown by the READER.  The
writer does not try to be smart, so does not add the nillable default.

=example use of default_values MINIMAL

With option C<default_values> set to C<MINIMAL>, the READER would do this:

 <element minOccurs="0" maxOccurs="1" ref="myelem"/>
 element => { ref => 'myelem', minOccurs => 0 }

The maxOccurs default is "1", so will not be included, minimalizing the
size of the HASH.

For the WRITER:

 element => { ref => 'myelem', minOccurs => 0, nillable => 0 }
 <element minOccurs="0" ref="myelem"/>

because the default value for nillable is '0', it will not show as attribute
value.

=subsection Repetative blocks

Particle blocks come in four shapes: C<sequence>, C<choice>, C<all>,
and C<group> (an indirect block).  This also affects C<substitutionGroups>.

=subsubsection repetative sequence, choice, all

In situations like this:

  <element name="example">
    <complexType>
      <sequence>
        <element name="a" type="int" />
        <sequence>
          <element name="b" type="int" />
        </sequence>
        <element name="c" type="int" />
      </sequence>
    </complexType>
  </element>

(yes, schemas are verbose) the data structure is

  <example> <a>1</a> <b>2</b> <c>3</c> </example>

the Perl representation is I<flattened>, into

  example => { a => 1, b => 2, c => 3 }

Ok, this is very simple.  However, schemas can use repetition:

  <element name="example">
    <complexType>
      <sequence>
        <element name="a" type="int" />
        <sequence minOccurs="0" maxOccurs="unbounded">
          <element name="b" type="int" />
        </sequence>
        <element name="c" type="int" />
      </sequence>
    </complexType>
  </element>

The XML message may be:

  <example> <a>1</a> <b>2</b> <b>3</b> <b>4</b> <c>5</c> </example>

Now, the perl representation needs to produce an array of the data in
the repeated block.  This array needs to have a name, because more of
these blocks may appear together in a construct.  The B<name of the
block> is derived from the I<type of block> and the name of the I<first
element> in the block, regardless whether that element is present in
the data or not.

So, our example data is translated into (and vice versa)

  example =>
    { a     => 1
    , seq_b => [ {b => 2}, {b => 3}, {b => 4} ]
    , c     => 5
    }

The following label is used, based on the name of the first element (say C<xyz>)
as defined in the schema (not in the actual message):
   seq_xyz    sequence with maxOccurs > 1
   cho_xyz    choice with maxOccurs > 1
   all_xyz    all with maxOccurs > 1

When you have M<compile(key_rewrite)> option PREFIXED, and you have explicitly
assigned the prefix C<xs> to the schema namespace (See M<compile(prefixes)>),
then those names will respectively be C<seq_xs_xyz>, C<cho_xs_xyz>,
C<all_xs_xyz>.

=example always an array with maxOccurs larger than 1
Even when there is only one element found, it will be returned as
ARRAY (of one element).  Therefore, you can write

 my $data = $reader->($xml);
 foreach my $a ( @{$data->{a}} ) {...}

=example blocks with maxOccurs larger than 1
In the schema:
 <sequence maxOccurs="5">
   <element name="a" type="int" />
   <element name="b" type="int" />
 </sequence>

In the XML message:
 <a>15</a><b>16</b><a>17</a><b>18</b>

In Perl representation:
 seq_a => [ {a => 15, b => 16}, {a => 17, b => 18} ]

=subsubsection repetative groups

[behavioral change in 0.93]
In contrast to the normal particle blocks, as described above, do the
groups have names.  In this case, we do not need to take the name of
the first element, but can use the group name.  It will still have C<gr_>
appended, because groups can have the same name as an element or a type(!)

Blocks within the group definition cannot be repeated.

=example groups with maxOccurs larger than 1

 <element name="top">
   <complexType>
     <sequence>
       <group ref="ns:xyz" maxOccurs="unbounded">
     </sequence>
   </complexType>
 </element>

 <group name="xyz">
   <sequence>
     <element name="a" type="int" />
     <element name="b" type="int" />
   </sequence>
 </group>

translates into

  gr_xyz => [ {a => 42, b => 43}, {a => 44, b => 45} ]

=subsubsection repetative substitutionGroups

For B<substitutionGroup>s which are repeating, the I<name of the base
element> is used (the element which has attribute C<<abstract="true">>.
We do need this array, because the order of the elements within the group
may be important; we cannot group the elements based to the extended
element's name.

In an example substitutionGroup, the Perl representation will be
something like this:

  base-element-name =>
    [ { extension-name  => $data1 }
    , { other-extension => $data2 }
    ]

Each HASH has only one key.

=subsection List type

List simpleType objects are also represented as ARRAY, like elements
with a minOccurs or maxOccurs unequal 1.

=example with a list of ints

  <test5>3 8 12</test5>

as Perl structure:

  test5 => [3, 8, 12]

=subsection Using substitutionGroup constructs

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
 
=subsection Wildcards via any and anyAttribute

The C<any> and C<anyAttribute> elements are referred to as C<wildcards>:
they specify (huge, generic) groups of elements and attributes which
are accepted, instead of being explicit.

The author of this module advices B<against the use of wildcards> in
schemas: the purpose of schemas is to be I<explicit> about the
message in the interface, and that basic idea is simply thrown away by
these wildcards.  Let people cleanly extend the schema with inheritance!
There is always a substitutionGroup alternative possible.

Because wildcards are not explicit about the types to expect, the
C<XML::Compile> module can not prepare for them at run-time.  You need
to go read the documentation and do some tricky manual work to get it
to work.

Read about the processing of wildcards in the manual page for each of
the back-ends (M<XML::Compile::Translate::Reader>,
M<XML::Compile::Translate::Writer>, ...).

=subsection ComplexType with "mixed" attribute

[largely improved in 0.86, reader only]
ComplexType and ComplexContent components can be declared with the
C<<mixed="true">> attribute.  This implies that text is not limited
to the content of containers, but may also be used inbetween elements.
Usually, you will only find ignorable white-space between elements.

In this example, the C<a> container is marked to be mixed:
  <a> before <b>2</b> after </a>

Each back-end has its own way of handling mixed elements.  The
M<compile(mixed_elements)> currently only modifies the reader's
behavior; the writer's capabilities are limited.
See M<XML::Compile::Translate::Reader>.

=subsection hexBinary and base64Binary

These are used to include images and such in an XML message. Usually,
they are quite large with respect to the other elements. When you use
SOAP, you may wish to use M<XML::Compile::XOP> instead.

The element values which you need to pass for fields of these
types is a binary BLOB, something Perl does not have. So, it is
a string containing binary data but not specially marked that way.

If you need to store an integer in such a binary field, you first have
to promote it into a BLOB (string) like this

   { color => pack('N', $i) }          # writer
   my $i = unpack('N', $d->{color});   # reader

Module Geo::KML implemented a nice hook to avoid the explicit need
for this C<pack> and C<unpack>. The KML schema designers liked colors
to be written as C<ffc0c0c0> and abused C<hexBinary> for that purpose.
The C<colorType> fields in KML are treated as binary, but just represent
an int. Have a look in that Geo::KML code if your schema has some of
those tricks.  Only available in Backpan, withdrawn from CPAN.

=section Schema hooks

You can use hooks, for instance, to block processing parts of the message,
to create work-arounds for schema bugs, or to extract more information
during the process than done by default.

=subsection Defining hooks

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
 $wsdl->addHook(HOOKDATA | HOOK);

B<local> hooks are only used for one reader or writer.  They are
evaluated before the global hooks.

 my $reader = $schema->compile(READER => $type
  , hook => HOOK, hooks => [ HOOK, HOOK, ...]);

=examples of HOOKs:

 my $hook = { type    => '{my_ns}my_type'
            , before  => sub { ... }
            , action  => 'WRITER'
            };

 my $hook = { path    => qr/\(volume\)/
            , replace => 'SKIP'
            , action  => 'READER'
            };

 # path contains "volume" or id is 'aap' or id is 'noot'
 my $hook = { path    => qr/\bvolume\b/
            , id      => [ 'aap', 'noot' ]
            , before  => [ sub {...}, sub { ... } ]
            , after   => sub { ... }
            };

=subsection General syntax

Each hook has three kinds of parameters:
=over 4
=item . selectors
=item . processors
=item . action ('READER' or 'WRITER', defaults to both)
=back

Selectors define the schema component of which the processing is modified.
When one of the selectors matches, the processing information for the hook
is used.  When no selector is specified, then the hook will be used on all
elements.

Available selectors (see below for details on each of them):
=over 4
=item . type
=item . extends
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

=subsection Hooks on matching types

The C<type> selector specifies a complexType of simpleType by name.
Best is to base the selection on the full name, like C<{ns}type>,
which will avoid all kinds of name-space conflicts in the future.
However, you may also specify only the C<local type> (in any name-space).
Any REGEX will be matched to the full type name. Be careful with the
pattern archors.

If you use M<XML::Compile::Cache> [release 0.90], then you can use
C<prefix:type> as type specification as well.  You have to explicitly
define prefix to namespace beforehand.

=examples use of the type selector

 type => 'int'
 type => '{http://www.w3.org/2000/10/XMLSchema}int'
 type => qr/\}xml_/   # type start with xml_
 type => [ qw/int float/ ];

 use XML::Compile::Util qw/pack_type SCHEMA2000/;
 type => pack_type(SCHEMA2000, 'int')

 # with XML::Compile::Cache
 $schema->addPrefixes(xsd => SCHEMA2000);
 type => 'xsd:int'

=examples type hook with XML::Compile::Cache

 use XML::Compile::Util qw/SCHEMA2001/;
 my $schemas = XML::Compile::Cache->new(...);
 $schemas->addPrefixes(xsd => SCHEMA2001, mine => 'http://somens');
 $schemas->addHook(type => 'xsd:int', ...);
 $schemas->addHook(type => 'mine:sometype', ...);
 
=subsection Hooks on extended type

[1.48] This hook will match all elements which use a type which is equal or
based on the given type.  In the schema, you will find extension and
restriction constructs.  You may only pass a single full type (no arrays
of types or local names) per 'extend' hook.

Using a hooks on extended types is quite expensive for the compiler.

example:

 $schemas->addHook(extends => "{ns}local", ...);
 $schemas->addHook(extends => 'mine:sometype', ...);  # need ::Cache

=subsection Hooks on matching ids

Matching based on IDs can reach more schema elements: some types are
anonymous but still have an ID.  Best is to base selection on the full
ID name, like C<ns#id>, to avoid all kinds of name-space conflicts in
the future.

=examples use of the ID selector

 # default schema types have id's with same name
 id => 'ABC'
 id => 'http://www.w3.org/2001/XMLSchema#int'
 id => qr/\#xml_/   # id which start with xml_
 id => [ qw/ABC fgh/ ];

 use XML::Compile::Util qw/pack_id SCHEMA2001/;
 id => pack_id(SCHEMA2001, 'ABC')

=subsection Hooks on matching paths

When you see error messages, you always see some representation of
the path where the problem was discovered.  You can use this path
as selector, when you know what it is... BE WARNED, that the current
structure of the path is not really consequent hence will be 
improved in one of the future releases, breaking backwards compatibility.

=section Typemaps

Often, XML will be used in object oriented programs, where the facts
which are transported in the XML message are attributes of Perl objects.
Of course, you can always collect the data from each of the Objects into
the required (huge) HASH manually, before triggering the reader or writer.
As alternative, you can connect types in the XML schema with Perl objects
and classes, which results in cleaner code.

You can also specify typemaps with M<new(typemap)>, M<addTypemaps()>, and
M<compile(typemap)>. Each type will only refer to the last map for that
type.  When an C<undef> is given for a type, then the older definition
will be cancelled.  Examples of the three ways to specify typemaps:

  my %map = ($x1 => $p1, $x2 => $p2);
  my $schema = XML::Compile::Schema->new(...., typemap => \%map);

  $schema->addTypemaps($x3 => $p3, $x4 => $p4, $x1 => undef);

  my $call = $schema->compile(READER => $type, typemap => \%map);

The latter only has effect for the type being compiled.  The definitions
are cumulative.  In the second example, the C<$x1> gets disabled.

Objects can come in two shapes: either they do support the connection
with XML::Compile (implementing two methods with predefined names), or
they don't, in which case you will need to write a little wrapper.

  use XML::Compile::Util qw/pack_type/;
  my $t1 = pack_type $myns, $mylocal;
  $schema->typemap($t1 => 'My::Perl::Class');
  $schema->typemap($t1 => $some_object);
  $schema->typemap($t1 => sub { ... });

The implementation of the READER and WRITER differs.  In the READER case,
the typemap is implemented as an 'after' hook which calls a C<fromXML>
method.  The WRITER is a 'before' hook which calls a C<toXML> method.
See respectively the M<XML::Compile::Translate::Reader> and
M<XML::Compile::Translate::Writer>.

=subsection Private variables in objects

When you design a new object, it is possible to store the information
exactly like the corresponding XML type definition.  The only thing
the C<fromXML> has to do, is bless the data-structure into its class:

  $schema->typemap($xmltype => 'My::Perl::Class');
  package My::Perl::Class;
  sub fromXML { bless $_[1], $_[0] } # for READER
  sub toXML   { $_[0] }              # for WRITER

However... the object may also need so need some private variables.
If you store them in the same HASH for your object, you will get
"unused tags" warnings from the writer.  To avoid that, choose one
of the following alternatives:

  # never complain about unused tags
  ::Schema->new(..., ignore_unused_tags => 1);

  # only complain about unused tags not matching regexp
  my $not_for_xml = qr/^[A-Z]/;  # my XML only has lower-case
  ::Schema->new(..., ignore_unused_tags => $not_for_xml);

  # only for one compiled WRITER (not used with READER)
  ::Schema->compile(..., ignore_unused_tags => 1);
  ::Schema->compile(..., ignore_unused_tags => $not_for_xml);

=subsection Typemap limitations

There are some things you need to know:

=over 4

=item .
Many schemas define very complex types.  These may often not translate
cleanly into objects.  You may need to create a typemap relation for
some parent type.  The CODE reference may be very useful in this case.

=item .
A same kind of problem appears when you have a list in your object,
which often is not named in the schema.

=back

=section Handling xsi:type

[1.10] The C<xsi:type> is an old-fashioned mechanism, and should be avoided!
In this case, the schema does tell you that a certain element has
a certrain type, but at run-time(!) that is changed. When an XML
element has a C<xsi:type> attribute, it tells you simply to have an
extension of the original type.  This whole mechanism does bite the
"compilation" idea of M<XML::Compile>... however with some help, it
will work.

To make C<xsi:type> work at run-time, you have to pass a table of
which types you expect at compile-time.  Example:

  my %xsi_type_table =
    ( $base_type1 => [ $ext1_of_type1, $ext2_of_type2 ]
    , $base_type2 => [ $ext1_of_type2 ]
    );

  my $r = $schema->compile(READER => $type
    , xsi_type => \%xsi_type_table
    );

When your schema is an M<XML::Compile::Cache> (version at least 0.93),
your types look like C<prefix:local>.  With a plain M<XML::Compile::Schema>,
they will look like C<{namespace}local>, typically produced with
M<XML::Compile::Util::pack_type()>.

When used in a reader, the resulting data-set will contain a C<XSI_TYPE>
key inbetween the facts which were taken from the element.  The type is
is long syntax C<"{$ns}$type">.  See M<XML::Compile::Util::unpack_type()>

With the writer, you have to provide such an C<XSI_TYPE> value or the
element's base type will be used (and no C<xsi:type> attribute created).
This will probably cause warnings about unused tags.  The type can be
provided in full (see M<XML::Compile::Util::pack_type()>) or [1.31]
prefixed.

[1.25] then the value is not an ARRAY, but only the keyword C<AUTO>,
the parser will try to auto-detect all types which are valid alternatives.
This currently only works for non-builtin types.  The auto-detection might
be slow and (because many schemas are broken) not produce a complete list.
When debugging is enabled ("use Log::Report mode => 3;") you will see to
which list this AUTO gets expanded.

  xsi_type => { $base_type => 'AUTO' }   # requires X::C v1.25

M<XML::Compile::Cache> (since v1.01) makes using C<xsi:type> easier.  When
you have a ::Cache based object (for instance a M<XML::Compile::WSDL11>)
you can simply say

  $wsdl->addXsiType( $base_type => 'AUTO' )

Now, you do not need to pass the xsi table to each compilation call.

=section Key rewrite

[improved with release 1.10]
The standard practice is to use the localName of the XML elements as
key in the Perl HASH; the key rewrite mechanism is used to change that,
sometimes to separate elements which have the same localName within
different name-spaces, or when an element and an attribute share a name
(key rewrite is applied to elements AND attributes) in other cases just
for fun or convenience.

Rewrite rules are interpreted at "compile-time", which means that they
B<do not slow-down> the XML construction or deconstruction.  The rules
work the same for readers and writers, because they are applied to
name found in the schema.

Key rewrite rules can be set during schema object initiation
with M<new(key_rewrite)> and to an existing schema object with
M<addKeyRewrite()>.  These rules will be used in all calls to
M<compile()>.

Next, you can use M<compile(key_rewrite)> to add rules which
are only used for a single compilation.  These are applied before
the global rules.  All rules will always be attempted, and the
rulle will me applied to the result of the previous change.

The last defined rewrite rules will be applied first, with one major
exception: the C<PREFIXED> rules will be executed before any other
rule.

=subsection key_rewrite via table

When a HASH is provided as rule, then the XML element name is looked-up.
If found, the value is used as translated key.

First full name of the element is tried, and then the localName of
the element.  The full name can be created with
M<XML::Compile::Util::pack_type()> or by hand:

  use XML::Compile::Util qw/pack_type/;

  my %table =
    ( pack_type($myns, 'el1') => 'nice_name1'
    , "{$myns}el2" => 'alsoNice'
    , el3          => 'in any namespace'
    );
  $schema->addKeyRewrite( \%table );

=subsection Rewrite via function

When a CODE reference is provided, it will get called for each key
which is found in the schema.  Passed are the name-space of the
element and its local-name.  Returned is the key, which may be the
local-name or something else.

For instance, some people use capitals in element names and personally
I do not like them:

  sub dont_like_capitals($$)
  {   my ($ns, $local) = @_;
      lc $local;
  }
  $schema->addKeyRewrite( \&dont_like_capitals );

for short:

  my $schema = XML::Compile::Schema->new( ..., 
      key_rewrite => sub { lc $_[1] } );

=subsection key_rewrite when localNames collide

Let's start with an apology: we cannot auto-detect when these rewrite
rules are needed, because the colliding keys are within the same HASH,
but the processing is fragmented over various (sequence) blocks: the
parser does not have the overview on which keys of the HASH are used
for which elements.

The problem occurs when one complex type or substitutionGroup contains
multiple elements with the same localName, but from different name-spaces.
In the perl representation of the data, the name-spaces get ignored
(to make the programmer's life simple) but that may cause these nasty
conflicts.

=subsection Rewrite for convenience

In XML, we often see names like C<my-elem-name>, which in Perl
would be accessed as

  $h->{'my-elem-name'}

In this case, you cannot leave-out the quotes in your perl code, which is
quite inconvenient, because only 'barewords' can be used as keys unquoted.
When you use option C<key_rewrite> for M<compile()> or M<new()>, you
could decide to map dashes onto underscores.

  key_rewrite
     => sub { my ($ns, $local) = @_; $local =~ s/\-/_/g; $local }

  key_rewrite => sub { $_[1] =~ s/\-/_/g; $_[1] }

then C<< my-elem-name >> in XML will get mapped onto C<< my_elem_name >>
in Perl, both in the READER as the WRITER.  Be warned that the substitute
command returns the success, not the modified value!

=subsection Pre-defined key_rewrite rules

=over 4
=item UNDERSCORES
Replace dashes (-) with underscores (_).

=item SIMPLIFIED
Rewrite rule with the constant name (STRING) C<SIMPLIFIED> will replace
all dashes with underscores, translate capitals into lowercase, and
remove all other characters which are none-bareword (if possible, I am
too lazy to check)

=item PREFIXED
This requires a table for prefix to name-space translations, via
M<compile(prefixes)>, which defines at least one non-empty (default)
prefix.  The keys which represent elements in any name-space which has
a prefix defined will have that prefix and an underscore prepended.

Be warned that the name-spaces which you provide are used, not the
once used in the schema.  Example:

  my $r = $schema->compile
    ( READER => $type
    , prefixes    => [ mine => $myns ]
    , key_rewrite => 'PREFIXED'
    );

  my $xml = $r->( <<__XML );
<data xmlns="$myns"><x>42</x></data>
__XML

  print join ' => ', %$xml;    #   mine_x => 42

=item PREFIXED(...)

Like the previous, but now only use a selected sub-set of the available
prefixes.  This is particular useful in writers, when explicit prefixes
are also used to beautify the output.

The prefixes are not checked against the prefix list, and may have
surrounding blanks.

  key_rewrite => 'PREFIXED(opt,sar)'

Above is equivalent to:

  key_rewrite => [ 'PREFIXED(opt)', 'PREFIXED(sar)' ]

Special care is taken that the prefix will not be added twice.  For instance,
if the same prefix appears twice, or a C<PREFIXED> rule is provided as well,
then still only one prefix is added.

=back

=cut

1;
