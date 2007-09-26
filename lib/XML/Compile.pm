
use warnings;
use strict;

package XML::Compile;

use Log::Report 'xml-compile', syntax => 'SHORT';
use XML::LibXML;

use File::Spec     qw();

__PACKAGE__->knownNamespace
 ( 'http://www.w3.org/XML/1998/namespace' => '1998-namespace.xsd'
 , 'http://www.w3.org/1999/XMLSchema'     => '1999-XMLSchema.xsd'
 , 'http://www.w3.org/1999/part2.xsd'     => '1999-XMLSchema-part2.xsd'
 , 'http://www.w3.org/2000/10/XMLSchema'  => '2000-XMLSchema.xsd'
 , 'http://www.w3.org/2001/XMLSchema'     => '2001-XMLSchema.xsd'
 );

__PACKAGE__->addSchemaDirs($ENV{SCHEMA_DIRECTORIES});
__PACKAGE__->addSchemaDirs(__FILE__);

=chapter NAME

XML::Compile - Compilation based XML processing

=chapter SYNOPSIS

 # See XML::Compile::Schema / ::WSDL / ::SOAP

=chapter DESCRIPTION

Many (professional) applications process XML based on a formal
specification, expressed as XML Schema.  XML::Compile processes XML with
the help of such schemas.  The Perl program only handles a tree of nested
HASHes and ARRAYs.

Three serious WARNINGS:

=over 4

=item .

The compiler does only support B<namespace schemas>.  It is possible,
but generally seen as weakness, to make schemas which do not use
namespaces, but for the moment XML::Compile does not handle those.
Check for a C<targetNamespace> attribute on C<schema> in your C<xsd>
file.

=item .

The focus is on B<data-centric XML>, which means that mixed elements
are not understood automatically.  However, with using hooks, you can
work around this.

=item .

The provided B<schema is not validated>!  In many cases, compile-time
and run-time errors will get reported.  On the other hand, the processed
B<data is strictly validated>: both input and output will follow the
specs closely.

=back

For end-users, the following packages are of interest (the other
are support packages):

=over 4

=item M<XML::Compile::Schema>
Interpret schema elements and types: process XML messages.

=item M<XML::Compile::WSDL> and M<XML::Compile::SOAP>
Use the SOAP protocol. (implementation in progress)

=item M<XML::Compile::Dumper>
Save pre-compiled converters in pure perl packages.

=back

=chapter METHODS

Methods found in this manual page are shared by the end-user modules,
and should not be used directly: objects of type C<XML::Compile> do not
exist.

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

    $class ne __PACKAGE__
       or panic "you should instantiate a sub-class, $class is base only";

    (bless {}, $class)->init( {top => $top, @_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->addSchemaDirs($args->{schema_dirs});
    $self;
}

=section Accessors

=ci_method addSchemaDirs DIRECTORIES
Each time this method is called, the specified DIRECTORIES will be added
in front of the list of already known schema directories.  Initially,
the value of the environment variable C<SCHEMA_DIRECTORIES> is added
(therefore used last), then the constructor option C<schema_dirs>
is processed.

If a pm filename is provided, then the directory to be used is
calculated from it (platform independent).  So, C<lib/XML/Compile.pm>
becomes C<lib/XML/Compile/xsd/>.  This way, modules can simply add
their definitions via C<< XML::Compile->addSchemaDirs(__FILE__) >>

Values which are C<undef> are skipped.  ARRAYs are flattened.  
Arguments are split on colons (only when on UNIX) after flattening.
The list of directories is returned, in all but VOID context.
=cut

my @schema_dirs;
sub addSchemaDirs(@)
{   my $thing = shift;
    foreach (@_)
    {   my $dir  = shift;
        my @dirs = grep {defined} ref $dir eq 'ARRAY' ? @$dir : $dir;
        foreach ($^O eq 'MSWin32' ? @dirs : map { split /\:/ } @dirs)
        {   my $el = $_;
            $el = File::Spec->catfile($el, 'xsd') if $el =~ s/\.pm$//i;
            push @schema_dirs, $el;
        }
    }
    defined wantarray ? @schema_dirs : ();
}

=ci_method knownNamespace NAMESPACE|PAIRS
If used with only one NAMESPACE, it returns the filename in the
distribution (not the full path) which contains the definition.

When PAIRS of NAMESPACE-FILENAME are given, then those get defined.
This is typically called during the initiation of modules, like
XML::Compile and XML::Compile::SOAP.  The definitions are global.
=cut

my %namespace_file;
sub knownNamespace($;@)
{   my $thing = shift;
    return $namespace_file{ $_[0] } if @_==1;

    while(@_)
    {  my $ns = shift;
       $namespace_file{$ns} = shift;
    }
    undef;
}

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

    foreach my $dir (@schema_dirs)
    {   my $full = File::Spec->catfile($dir, $fn);
        next unless -e $full;
        return -r $full ? $full : undef;
    }

    undef;
}

=section Read XML

=method dataToXML NODE|REF-XML-STRING|XML-STRING|FILENAME|KNOWN
Collect XML data.  When a ready M<XML::LibXML> NODE is provided, it is
returned immediately and unchanged.  A SCALAR reference is interpreted
as reference to XML as plain text (XML texts can be large, and you can
improve performance by passing it around by reference instead of copy).
Any value which starts with blanks followed by a 'E<lt>' is interpreted
as XML text.

You may also specify a pre-defined I<known> name-space URI.  A set of
definition files is included in the distribution, and installed somewhere
when this all gets installed.  Either define an environment variable
named SCHEMA_LOCATION or use M<new(schema_dirs)> (option available to
all end-user objects) to inform the library where to find these files.

=error cannot find pre-installed name-space files
Use C<$ENV{SCHEMA_LOCATION}> or M<new(schema_dirs)> to express location
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
            or error __x"cannot find pre-installed name-space files named {path} for {name}"
                 , path => $known, name => $thing;

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

=chapter DETAILS

=section Comparison

Where other Perl modules, like M<SOAP::WSDL> help you using these schemas
(often with a lot of run-time [XPath] searches), XML::Compile takes a
different approach: instead of run-time processing of the specification,
it will first compile the expected structure into a pure Perl CODE
reference, and then use that to process the data as often as needed.

There are many Perl modules with the same intention as this one:
translate between XML and nested hashes.  However, there are a few
serious differences:  because the schema is used here (and not by the
other modules), we can validate the data.  XML requires validation but
quite a number of modules simply ignore that.

Next to this, data-types are formatted and processed correctly; for
instance, the specification prescribes that the C<Integer> data-type
must accept values of at least 18 digits... not just Perl's idea of longs.

XML::Compile suppoer the more complex data-types like C<list>, C<union>,
C<substitutionGroup> (unions on complex type level), and even the
nasty C<any> and C<anyAttribute>, which is rarely the case for the
other modules.
=cut

1;
