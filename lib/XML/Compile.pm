
use warnings;
use strict;

package XML::Compile;

use Log::Report 'xml-compile', syntax => 'SHORT';
use XML::LibXML;

my %namespace_defs =
 ( 'http://www.w3.org/XML/1998/namespace'    => '1998-namespace.xsd'

 # XML Schema's
 , 'http://www.w3.org/1999/XMLSchema'        => '1999-XMLSchema.xsd'
 , 'http://www.w3.org/1999/part2.xsd'        => '1999-XMLSchema-part2.xsd'
 , 'http://www.w3.org/2000/10/XMLSchema'     => '2000-XMLSchema.xsd'
 , 'http://www.w3.org/2001/XMLSchema'        => '2001-XMLSchema.xsd'

 # WSDL 1.1
 , 'http://schemas.xmlsoap.org/wsdl/'        => 'wsdl.xsd'
 , 'http://schemas.xmlsoap.org/wsdl/soap/'   => 'wsdl-soap.xsd'
 , 'http://schemas.xmlsoap.org/wsdl/http/'   => 'wsdl-http.xsd'
 , 'http://schemas.xmlsoap.org/wsdl/mime/'   => 'wsdl-mime.xsd'

 # SOAP 1.1
 , 'http://schemas.xmlsoap.org/soap/encoding/' => 'soap-encoding.xsd'
 , 'http://schemas.xmlsoap.org/soap/envelope/' => 'soap-envelope.xsd'

 # SOAP 1.2
 , 'http://www.w3.org/2003/05/soap-encoding' => '2003-soap-encoding.xsd'
 , 'http://www.w3.org/2003/05/soap-envelope' => '2003-soap-envelope.xsd'
 , 'http://www.w3.org/2003/05/soap-rpc'      => '2003-soap-rpc.xsd'
 );

=chapter NAME

XML::Compile - Compilation based XML processing

=chapter SYNOPSIS

 # See XML::Compile::Schema

=chapter DESCRIPTION

Many professional applications which process XML do that based on a formal
specification, expressed as XML Schema.  XML::Compile processes
<b>data-centric XML</b> with the help of such schema's.  On the Perl side,
this module creates a tree of nested hashes with the same structure as
the XML.

Where other Perl modules, like M<SOAP::WSDL> help you using these schema's
(often with a lot of run-time [XPath] searches), XML::Compile takes a
different approach: in stead of run-time processing of the specification,
it will first compile the expected structure into a pure Perl code
reference, and then use that to process the data.

There are many perl modules with the same intention as this one:
translate between XML and nested hashes.  However, there are a few
serious differences:  because the schema is used here (and not in the
other modules), we can validate the data.  XML requires validation but
quite a number of modules simply ignore that.  Next to this, data-types
are formatted and processed correctly; for instance, the specification
prescribes that the C<Integer> data-type must accept values of at
least 18 digits... not just longs.  Also more complex data-types like
C<list>, C<union>, C<substitutionGroup> (unions on complex type level),
and C<any>/C<anyAttribute> are supported, which is rarely the case for
the other modules.

In general two WARNINGS:

=over 4

=item .

The compiler does not support non-namespace schema's and mixed elements.

=item .

The provided B<schema is not validated>!  In some cases,
compile-time and run-time errors will be reported, but typically only
in cases that the parser has no idea what to do with such a mistake.
On the other hand, the processed B<data is validated>: the output will
follow the specs closely.

=back

For end-users, the following packages are interesting (the other
are support packages):

=over 4

=item M<XML::Compile::Schema>
Interpret schema elements and types.

=item M<XML::Compile::WSDL>
Interpret WSDL files.

=item M<XML::Compile::Dumper>
Save pre-compiled converters in pure perl packages.

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

    panic "you should instantiate a sub-class, $class is base only"
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

=method dataToXML NODE|REF-XML-STRING|XML-STRING|FILENAME|KNOWN
Collect XML data.  Either a preparsed NODE is provided, which
is returned unchanged.  A SCALAR reference is interpreted as reference
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
    defined $thing
        or return undef;

    return $thing
        if ref $thing && UNIVERSAL::isa($thing, 'XML::LibXML::Node');

    return $self->_parse($thing)
        if ref $thing eq 'SCALAR'; # XML string as ref

    return $self->_parse(\$thing)
        if $thing =~ m/^\s*\</;    # XML starts with '<', rare for files

    if(my $known = $self->knownNamespace($thing))
    {   my $fn = $self->findSchemaFile($known)
            or error "cannot find pre-installed name-space files";

        return $self->_parseFile($fn);
    }

    return $self->_parseFile($thing)
        if -f $thing;

    my $data = "$thing";
    $data = substr($data, 0, 39) . '...' if length($data) > 40;
    mistake __x"don't known how to interpret XML data\n   {data}"
          , data => $data;
}

sub _parse($)
{   my ($thing, $data) = @_;
    my $xml = XML::LibXML->new->parse_string($$data);
    defined $xml ? $xml->documentElement : undef;
}

sub _parseFile($)
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
