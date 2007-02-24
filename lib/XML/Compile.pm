
use warnings;
use strict;

package XML::Compile;

use XML::LibXML;
use Carp;

my %namespace_defs =
 ( 'http://www.w3.org/1999/XMLSchema'      => '1999-XMLSchema.xsd'
 , 'http://www.w3.org/1999/part2.xsd'      => '1999-XMLSchema-part2.xsd'
 , 'http://www.w3.org/2000/10/XMLSchema'   => '2000-XMLSchema.xsd'
 , 'http://www.w3.org/2001/XMLSchema'      => '2001-XMLSchema.xsd'
 , 'http://www.w3.org/XML/1998/namespace'  => '1998-namespace.xsd'
 , 'http://schemas.xmlsoap.org/wsdl/'      => 'wsdl.xsd'
 , 'http://schemas.xmlsoap.org/wsdl/soap/' => 'wsdl-soap.xsd'
 , 'http://schemas.xmlsoap.org/wsdl/http/' => 'wsdl-http.xsd'
 , 'http://schemas.xmlsoap.org/wsdl/mime/' => 'wsdl-mime.xsd'
 , 'http://schemas.xmlsoap.org/soap/encoding/' => 'soap-encoding.xsd'
 , 'http://schemas.xmlsoap.org/soap/envelope/' => 'soap-envelope.xsd'

 # bug-fixes/mis-features/work-arounds
 , 'http://schemas.xmlsoap.org/wsdl/#patch'=> 'wsdl-patch.xsd'
 );

=chapter NAME

XML::Compile - Compilation based XML processing

=chapter SYNOPSIS

 # See XML::Compile::Schema

=chapter DESCRIPTION

Many professional applications which process data-centric XML do that
based on a formal specification, expressed as XML Schema.  XML::Compile
reads and writes XML data with the help of such schema's.  On the Perl
side, the module uses a tree of nested hashes with the same structure.

Where other Perl modules, like M<SOAP::WSDL> help you using these schema's
(often with a lot of run-time [XPath] searches), this module takes a
different approach: in stead of run-time processing of the specification,
it will first compile the expected structure into real Perl, and then use
that to process the data.

There are many perl modules with the same intention as this one: translate
between XML and nested hashes.  However, there are a few serious
differences:  because the schema is used here (and not in the other
modules), we can validate the data.  XML requires validation.  Next to
this, data-types are formatted and processed correctly.  for instance,
the specification prescribes that the C<integer> data-type must accept
huge values of at least 18 digits.  Also more complex data-types like
C<list>, C<union>, and C<substitutionGroup> (unions on complex type level)
are supported, which is rarely the case in other modules.

In general two WARNINGS:

=over 4

=item .

The compiler is implemented in M<XML::Compile::Schema::Translate>,
which is B<not finished>.  See that manual page about the specific behavior
and its (current) limitations!  Please help to find missing pieces and
mistakes.

=item .

The provided B<schema is not validated>!  In some cases,
compile-time and run-time errors will be reported, but typically only
in cases that the parser has no idea what to do with such a mistake.
On the other hand, the processed B<data is validated>: the output will
follow the specs closely.

=back

=chapter METHODS

=section Constructors
These constructors are base class methods to be extended,
and therefore should not be accessed directly.

=c_method new TOP, OPTIONS

The TOP is the source of XML. See M<dataToXML()> for valid options.

If you have compiled/collected all readers and writers you need,
you may simply terminate the compiler object: that will clean-up
(most of) the XML::LibXML objects.

=option  schema_dirs DIRECTORY|ARRAY-OF-DIRECTORIES
=default schema_dirs C<undef>
Where to find schema's.  This can be specified with the
environment variable C<SCHEMA_DIRECTORIES> or with this option.
See M<addSchemaDirs()> for a detailed explanation.

=error no XML data specified
=cut

sub new($@)
{   my ($class, $top) = (shift, shift);

    croak "ERROR: you should instantiate a sub-class, $class is base only"
        if $class eq __PACKAGE__;

    (bless {}, $class)->init( {top => $top, @_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->addSchemaDirs($ENV{SCHEMA_DIRECTORIES});
    $self->addSchemaDirs($args->{schema_dirs});
    $self;
}

=section Accessors

=method addSchemaDirs DIRECTORIES
Each time this method is called, the specified DIRECTORIES will be added
in front of the list of already known schema directories.  Initially,
the value of the environment variable C<SCHEMA_DIRECTORIES> is added
(therefore used last), then the constructor option C<schema_dirs>
is processed.

Values which are C<undef> are skipped.  ARRAYs are flattened.  
Arguments are split on colons (only when on UNIX) after flattening.

=cut

sub addSchemaDirs(@)
{   my $self = shift;
    foreach (@_)
    {   my $dir  = shift;
        my @dirs = grep {defined} ref $dir eq 'ARRAY' ? @$dir : $dir;
        push @{$self->{schema_dirs}},
           $^O eq 'MSWin32' ? @dirs : map { split /\:/ } @dirs;
    }
    $self;
}

=ci_method knownNamespace NAMESPACE
Returns the file which contains the definition of a NAMESPACE, if it
is one of the set which is distributed with the M<XML::Compile>
module.
=cut

sub knownNamespace($) { $namespace_defs{$_[1]} }

=method findSchemaFile FILENAME
Runs through all defined schema directories (see M<addSchemaDirs()>)
in search of the specified FILENAME.  When the FILENAME is absolute,
that will be used, and no search will take place.  An C<undef> is returned
when the file is not found or not readible, otherwise a full path to
the file is returned to the caller.
=cut

sub findSchemaFile($)
{   my ($self, $fn) = @_;

    return (-r $fn ? $fn : undef)
        if File::Spec->file_name_is_absolute($fn);

    foreach my $dir (@{$self->{schema_dirs}})
    {   my $full = File::Spec->catfile($dir, $fn);
        next unless -e $full;
        return -r $full ? $full : undef;
    }

    undef;
}

=section Read XML

=method dataToXML NODE|REF-XML|XML|FILENAME|KNOWN
Collect XML data.  Either a preparsed NODE is provided, which
is returned unchanged.  A ref of SCALAR is interpreted as reference
to XML as plain text (XML texts can be large, hence you can improve
performance by passing it around as reference in stead of copy).
Any value which starts with blanks followed by a "E<lt>" is interpreted
as XML text.

You may also specify a pre-defined (KNOWN) name-space.  A set of definition
files is included in the distribution, and installed somewhere when the
modules got installed.  Either define an environmen variable SCHEMA_LOCATION
or use M<new(schema_dirs)> to inform the library where to find these
files.

=error cannot find pre-installed name-space files
Use $ENV{SCHEMA_LOCATION} or M<new(schema_dirs)> to express location
of installed name-space files, which came with the M<XML::Compile>
distribution package.

=error don't known how to interpret XML data
=cut

sub dataToXML($)
{   my ($self, $thing) = @_;

    return $thing
       if ref $thing && UNIVERSAL::isa($thing, 'XML::LibXML::Node');

    return $self->parse($thing)
       if ref $thing eq 'SCALAR'; # XML string as ref

    return $self->parse(\$thing)
       if $thing =~ m/^\s*\</;    # XML starts with '<', rare for files

    if(my $known = $self->knownNamespace($thing))
    {   my $fn = $self->findSchemaFile($known)
            or croak "ERROR: cannot find pre-installed name-space files.\n";

        return $self->parseFile($fn);
    }

    return $self->parseFile($thing)
         if -f $thing;

    my $data = "$thing";
    $data = substr($data, 0, 39) . '...' if length($data) > 40;
    croak "ERROR: don't known how to interpret XML data\n   $data\n";
}

=method parse STRING
Extract document element tree from the STRING, which represents XML.
This is a wrapper around M<XML::LibXML> method C<parse_string()>.
=cut

sub parse($)
{   my ($thing, $data) = @_;
    my $xml = XML::LibXML->new->parse_string($$data);
    defined $xml ? $xml->documentElement : undef;
}

=method parseFile FILENAME
Extract document element tree from a file, specified by FILENAME.
This is a wrapper around M<XML::LibXML> method C<parse_file()>.
=cut

sub parseFile($)
{   my ($thing, $fn) = @_;
    my $xml = XML::LibXML->new->parse_file($fn);
    defined $xml ? $xml->documentElement : undef;
}

=section Filters

=method walkTree NODE, CODE
Walks the whole tree from NODE downwards, calling the CODE reference
for each NODE found.  When that routine returns false, the child
nodes will be skipped.

=cut

sub walkTree($$)
{   my ($self, $node, $code) = @_;
    if($code->($node))
    {   $self->walkTree($_, $code)
            for $node->getChildNodes;
    }
}

1;
