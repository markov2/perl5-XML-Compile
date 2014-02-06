
use warnings;
use strict;

package XML::Compile;

use Log::Report 'xml-compile';
use XML::LibXML;
use XML::Compile::Util qw/:constants type_of_node/;

use File::Spec  qw();

my $parser;

__PACKAGE__->knownNamespace
 ( &XMLNS       => '1998-namespace.xsd'
 , &SCHEMA1999  => '1999-XMLSchema.xsd'
 , &SCHEMA2000  => '2000-XMLSchema.xsd'
 , &SCHEMA2001  => '2001-XMLSchema.xsd'
 , &SCHEMA2001i => '2001-XMLSchema-instance.xsd'
 , 'http://www.w3.org/1999/part2.xsd'
                => '1999-XMLSchema-part2.xsd'
 );

__PACKAGE__->addSchemaDirs($ENV{SCHEMA_DIRECTORIES});
__PACKAGE__->addSchemaDirs(__FILE__);

=chapter NAME

XML::Compile - Compilation based XML processing

=chapter SYNOPSIS

 # See XML::Compile::Schema / ::WSDL / ::SOAP11 etc

=chapter DESCRIPTION

Many (professional) applications process XML messages based on a formal
specification, expressed in XML Schemas.  XML::Compile translates
between XML and Perl with the help of such schemas.  Your Perl program
only handles a tree of nested HASHes and ARRAYs, and does not need to
understand namespaces and other general XML and schema nastiness.

Three serious WARNINGS:

=over 4

=item *
The focus is on B<data-centric XML>, which means that mixed elements
are not handler automatically: you need to work with XML::LibXML nodes
yourself, on these spots.

=item *
The B<data is not strictly validated>, still a large number of
compile-time errors can be reported.  Values are checked quite thoroughly.
Structure as well.

=item *
Imports and includes, as used in the schemas, are NOT performed
automatically.  Schema's and such are NOT collected from internet
dynamically; you have to call M<XML::Compile::Schema::importDefinitions()>
explicitly with filenames of locally stored copies. Includes do only
work if they have a targetNamespace defined, which is the same as that
of the schema it is included into.

=back

=chapter METHODS

Methods found in this manual page are shared by the end-user modules,
and should not be used directly: objects of type C<XML::Compile> do not
exist!

=section Constructors
These constructors are base class methods to be extended,
and therefore should not be accessed directly.

=c_method new [$xmldata], %options

The $xmldata is a source of XML. See M<dataToXML()> for valid ways,
for example as filename, string or C<undef>.

If you have compiled all readers and writers you need, you may simply
terminate the compiler object: that will clean-up (most of) the
XML::LibXML objects.

=option  schema_dirs DIRECTORY|ARRAY-OF-DIRECTORIES
=default schema_dirs C<undef>
Where to find schema's.  This can be specified with the
environment variable C<SCHEMA_DIRECTORIES> or with this option.
See M<addSchemaDirs()> for a detailed explanation.

=option  parser_options HASH|ARRAY
=default parser_options <many>
See M<XML::LibXML::Parser> for a list of available options which can be
used to create an XML parser (the new method). The default will set you
in a secure mode.  See M<initParser()>.

=cut

sub new($@)
{   my $class = shift;
    my $top   = @_ % 2 ? shift : undef;

    $class ne __PACKAGE__
       or panic "you should instantiate a sub-class, $class is base only";

    (bless {}, $class)->init( {top => $top, @_} );
}

sub init($)
{   my ($self, $args) = @_;

    my $popts = $args->{parser_options} || [];
    $self->initParser(ref $popts eq 'HASH' ? %$popts : @$popts);

    $self->addSchemaDirs($args->{schema_dirs});
    $self;
}

#-------------------
=section Accessors

=ci_method addSchemaDirs $directories|$filename
Each time this method is called, the specified $directories will be added
in front of the list of already known schema directories.  Initially,
the value of the environment variable C<SCHEMA_DIRECTORIES> is added
(therefore tried as last resort). The constructor option C<schema_dirs>
is a little more favorite.

Values which are C<undef> are skipped.  ARRAYs are flattened.  Arguments
are split at colons (on UNIX) or semi-colons (windows) after flattening.
The list of directories is returned, in all but VOID context.

When a C<.pm> package $filename is given, then the directory
to be used is calculated from it (platform independently).  So,
C<something/XML/Compile.pm> becomes C<something/XML/Compile/xsd/>.
This way, modules can simply add their definitions via C<<
XML::Compile->addSchemaDirs(__FILE__) >> in a BEGIN block or in main.
M<ExtUtils::MakeMaker> will install everything what is found in the
C<lib/> tree, so also your xsd files.  Probably, you also want to use
M<knownNamespace()>.

=example adding xsd's from your own distribution
  # file xxxxx/lib/My/Package.pm
  package My::Package;

  use XML::Compile;
  XML::Compile->addSchemaDirs(__FILE__);
  # now xxxxx/lib/My/Package/xsd/ is also in the search path

  use constant MYNS => 'http://my-namespace-uri';
  XML::Compile->knownNamespace(&MYNS => 'my-schema-file.xsd');
  $schemas->importDefinitions(MYNS);
=cut

my @schema_dirs;
sub addSchemaDirs(@)
{   my $thing = shift;
    foreach (@_)
    {   my $dir  = shift;
        my @dirs = grep {defined} ref $dir eq 'ARRAY' ? @$dir : $dir;
        my $sep  = $^O eq 'MSWin32' ? qr/\;/ : qr/\:/;
        foreach (map { split $sep } @dirs)
        {   my $el = $_;
            $el = File::Spec->catfile($el, 'xsd') if $el =~ s/\.pm$//i;
            push @schema_dirs, $el;
        }
    }
    defined wantarray ? @schema_dirs : ();
}

#----------------------

=section Compilers

=ci_method initParser %options
Create a new parser, an M<XML::LibXML::Parser> object. By default, the
parsing is set in a safe mode, avoiding exploits. You may explicitly
overrule it, especially if you need to process entities.
=cut

sub initParser(@)
{   my $thing = shift;
    $parser = XML::LibXML->new
      ( line_numbers    => 1
      , no_network      => 1
      , expand_xinclude => 0
      , expand_entities => 1                                                  
      , load_ext_dtd    => 0
      , ext_ent_handler =>
           sub { alert __x"parsing external entities disabled"; '' }
      , @_
      );
}

=ci_method dataToXML $node|REF-XML|XML-STRING|$filename|$fh|$known
Collect $xml data, from a wide variety of sources.  In SCALAR context,
an M<XML::LibXML::Element> or M<XML::LibXML::Document> is returned.
In LIST context, pairs of additional information follow the scalar result.

When a ready M<XML::LibXML::Node> (::Element or ::Document) $node is
provided, it is returned immediately and unchanged.  A SCALAR reference is
interpreted as reference to $xml as plain text ($xml texts can be large,
and you can improve performance by passing it around by reference
instead of copy).  Any value which starts with blanks followed by a
'E<lt>' is interpreted as $xml text.

You may also specify a pre-defined I<known> name-space URI.  A set of
definition files is included in the distribution, and installed somewhere
when this all gets installed.  Either define an environment variable
named SCHEMA_LOCATION or use M<new(schema_dirs)> (option available to
all end-user objects) to inform the library where to find these files.

According the M<XML::LibXML::Parser> manual page, passing a $fh
is much slower than pasing a $filename.  However, it may be needed to
open a file with an explicit character-set.

=example
  my $xml = $schema->dataToXML('/etc/config.xml');
  my ($xml, %details) = $schema->dataToXML($something);

  my $xml = XML::Compile->dataToXML('/etc/config.xml');
=cut

sub dataToXML($)
{   my ($thing, $raw) = @_;
    defined $raw or return;

    $parser ||= $thing->initParser;

    my ($xml, %details);
    if(ref $raw && UNIVERSAL::isa($raw, 'XML::LibXML::Node'))
    {   ($xml, %details) = $thing->_parsedNode($raw);
    }
    elsif(ref $raw eq 'SCALAR')   # XML string as ref
    {   ($xml, %details) = $thing->_parseScalar($raw);
    }
    elsif(ref $raw eq 'GLOB')     # from file-handle
    {   ($xml, %details) = $thing->_parseFileHandle($raw);
    }
    elsif($raw =~ m/^\s*\</)      # XML starts with '<', rare for files
    {   ($xml, %details) = $thing->_parseScalar(\$raw);
    }
    elsif(my $known = $thing->knownNamespace($raw))
    {   my $fn  = $thing->findSchemaFile($known)
            or error __x"cannot find pre-installed name-space file named {path} for {name}"
                 , path => $known, name => $raw;

        ($xml, %details) = $thing->_parseFile($fn);
        $details{source} = "known namespace $raw";
    }
    elsif(my $fn = $thing->findSchemaFile($raw))
    {   ($xml, %details) = $thing->_parseFile($fn);
        $details{source} = "filename in schema-dir $raw";
    }
    elsif(-f $raw)
    {   ($xml, %details) = $thing->_parseFile($raw);
    }
    elsif($raw !~ /[\n\r<]/ && $raw =~ m![/\\]|\.xsd$|\.wsdl!i)
    {   error __x"file {fn} does not exist", fn => $fn;
    }
    else
    {   my $data = "$raw";
        $data = substr($data, 0, 59) . '...' if length($data) > 60;
        error __x"don't known how to interpret XML data\n   {data}"
           , data => $data;
    }

    wantarray ? ($xml, %details) : $xml;
}

sub _parsedNode($)
{   my ($thing, $node) = @_;
    my $top = $node;

    if($node->isa('XML::LibXML::Document'))
    {   $top       = $node->documentElement;
        my $eltype = type_of_node($top || '(none)');
        trace "using preparsed XML document with element <$eltype>";
    }
    elsif($node->isa('XML::LibXML::Element'))
    {   trace 'using preparsed XML node <'.type_of_node($node).'>';
    }
    else
    {   my $text = $node->toString;
        $text =~ s/\s+/ /gs;
        substr($text, 70, -1, '...')
            if length $text > 75;
        error __x"dataToXML() accepts pre-parsed document or element\n  {got}"
          , got => $text;
    }

    ($top, source => ref $node);
}

sub _parseScalar($)
{   my ($thing, $data) = @_;
    trace "parsing XML from string $data";
    my $xml = $parser->parse_string($$data);

    ( (defined $xml ? $xml->documentElement : undef)
    , source => ref $data
    );
}

sub _parseFile($)
{   my ($thing, $fn) = @_;
    trace "parsing XML from file $fn";
    my $xml = $parser->parse_file($fn);

    ( (defined $xml ? $xml->documentElement : undef)
    , source   => 'file'
    , filename => $fn
    );
}

sub _parseFileHandle($)
{   my ($thing, $fh) = @_;
    trace "parsing XML from open file $fh";
    my $xml = $parser->parse_fh($fh);

    ( (defined $xml ? $xml->documentElement : undef)
    , source => ref $thing
    );
}

#--------------------------

=section Administration

=method walkTree $node, CODE
Walks the whole tree from $node downwards, calling the CODE reference
for each $node found.  When that routine returns false, the child
nodes will be skipped.
=cut

sub walkTree($$)
{   my ($self, $node, $code) = @_;
    if($code->($node))
    {   $self->walkTree($_, $code)
            for $node->getChildNodes;
    }
}

=ci_method knownNamespace $ns|PAIRS
If used with only one $ns, it returns the filename in the
distribution (not the full path) which contains the definition.

When PAIRS of $ns-FILENAME are given, then those get defined.
This is typically called during the initiation of modules, like
M<XML::Compile::WSDL11> and M<XML::Compile::SOAP>.  The definitions
are global: not related to specific instances.

The FILENAMES are relative to the directories as specified with some
M<addSchemaDirs()> call.
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

=ci_method findSchemaFile $filename
Runs through all defined schema directories (see M<addSchemaDirs()>)
in search of the specified $filename.  When the $filename is absolute,
that will be used, and no search is needed.  An C<undef> is returned when
the file is not found, otherwise a full path to the file is returned to
the caller.

Although the file may be found, it still could be unreadible.
=cut

sub findSchemaFile($)
{   my ($thing, $fn) = @_;

    return (-f $fn ? $fn : undef)
        if File::Spec->file_name_is_absolute($fn);

    foreach my $dir (@schema_dirs)
    {   my $full = File::Spec->catfile($dir, $fn);
        return $full if -f $full;
    }

    undef;
}

=chapter DETAILS

=section Distribution collection overview

For end-users, the following packages are of interest (the other
are support packages):

=over 4

=item * M<XML::Compile::Schema>
Interpret schema elements and types: create processors for XML messages.

=item * M<XML::Compile::Cache>
Helps you administer compiled readers and writers, especially useful it
there are a lot of them.  Extends M<XML::Compile::Schema>.

=item * M<XML::Compile::SOAP>
Implements the SOAP 1.1 protocol. client side.

=item * M<XML::Compile::SOAP12>
Implements the SOAP 1.2 protocol.

=item * M<XML::Compile::WSDL11>
Use SOAP with a WSDL version 1.1 communication specification file.

=item * M<XML::Compile::SOAP::Daemon>
Create a SOAP daemon, directly from a WSDL file.

=item * M<XML::Compile::Tester>
Helps you write regression tests.

=item * M<XML::Rewrite>
Clean-up XML structures: beautify, simplify, extract.

=item * M<XML::Compile::Dumper>
Enables you to save pre-compiled XML handlers, the results of any
C<compileClient>.  However, this results in huge files, so this may
not be worth the effort.

=back

=section Comparison

Where other Perl modules (like M<SOAP::WSDL>) help you using these schemas
(often with a lot of run-time XPath searches), XML::Compile takes a
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
must accept values of at least 18 digits... not fitting in Perl's idea
of longs.

XML::Compile also supports all more complex data-types like C<list>,
C<union>, C<substitutionGroup> (unions on complex type level), and even
the nasty C<any> and C<anyAttribute>, which is rarely the case for the
other modules.
=cut

1;
