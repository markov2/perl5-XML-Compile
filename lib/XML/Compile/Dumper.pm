
use warnings;
use strict;

package XML::Compile::Dumper;

use Data::Dump::Streamer;
use POSIX 'asctime';
use Carp;
use IO::File;

# I have no idea why the next is needed, but without it, the
# tests are failing.
use XML::Compile::Schema;

=chapter NAME

XML::Compile::Dumper - Translate Schema or WSDL to code

=chapter SYNOPSIS

 # create readers and writers or soap things
 my $reader = $schema->compile(READER => '{myns}mytype');
 my $writer = $schema->compile(WRITER => ...);

 # then dump them into a package
 my $dumper = XML::Compile::Dumper->new
   (package => 'My::Package', filename => 'My/Package.pm');
 $dumper->freeze(foo => $reader, bar => $writer);
 $dumper->close;

 # later, they can get recalled using
 use My::Package;
 my $hash = foo($xml);
 my $doc  = bar($doc, $xml);
 
=chapter DESCRIPTION

This module simplifies the task of saving and loading pre-compiled
translators.  Schema's can get huge, and when you are not creating a
daemon to do the XML communication, you may end-up compiling and
interpreting these large schema's often, just to be able to process
simple data-structures.

Based on the excellent module M<Data::Dump::Streamer>, this module
helps you create standard Perl packages which contain the reader
and writer code references.

WARNING: this feature was introduced in release 0.17.  Using perl
5.8.8, libxml 2.6.26, XML::LibXML 2.60, and Data::Dump::Streamer
2.03, Perl complains about C<"PmmREFCNT_dec: REFCNT decremented below
0! during global destruction."> when the tests are run.  This bug
can be anywhere. Therefore, these tests are disabled by default in
t/TestTools.pm.  If you have time, could you please run the tests with
C<$skip_dumper = 0;> and report the results to the author?

=chapter METHODS

=section Constructors

=c_method new OPTIONS
Create an object which will collect the information for the output
file.  You have to specify either a C<filehandle> or a C<filename>.
A filehandle will be closed after processing.

=option  filehandle M<IO::Handle>
=default filehandle C<undef>

=option  filename FILENAME
=default filename C<undef>
The file will be written using utf8 encoding, using M<IO::File>.  If
you want something else, open your filehandle first, and provide that
as argument.

=requires package PACKAGE
The name-space which will be used: it will produce a C<package>
line in the output.

=error either filename or filehandle required

=error package name required
The perl module which is produced is cleanly encapsulating the
produced program text in a perl package name-space.  The name
has to be provided.

=cut

sub new(@)
{   my ($class, %opts) = @_;
    (bless {}, $class)->init(\%opts);
}

sub init($)
{   my ($self, $opts) = @_;

    my $fh      = $opts->{filehandle};
    unless($fh)
    {   my $fn  = $opts->{filename}
            or croak "ERROR: either filename or filehandle required";

        $fh     = IO::File->new($fn, '>:utf8')
            or die "ERROR: cannot write to $fn: $!";
    }
    $self->{XCD_fh} = $fh;

    my $package = $opts->{package}
        or croak "ERROR: package name required";

    $self->header($fh, $package);
    $self;
}

=method close
Finalize the produced file.  This will be called automatically
if the objects goes out-of-scope.
=cut

sub close()
{   my $self = shift;
    my $fh = $self->file or return 1;

    $self->footer($fh);
    delete $self->{XCD_fh};
    $fh->close;
}

sub DESTROY()
{   my $self = shift;
    $self->close;
}

=section Accessors

=method file
Returns the output file-handle, which you may use to add extensions to
the module.
=cut

sub file() {shift->{XCD_fh}}

=section Producers

=method header FILEHANDLE, PACKAGE
Prints the header text to the file.
=cut

sub header($$)
{   my ($self, $fh, $package) = @_;
    my $date = asctime localtime;
    $date =~ s/\n.*//;

    $fh->print( <<__HEADER );
#crash
# This module has been generated using
#    XML::Compile         $XML::Compile::VERSION
#    Data::Dump::Streamer $Data::Dump::Streamer::VERSION
# Created with a script
#    named $0
#    on    $date

use warnings;
no  warnings 'once';
no  strict;   # sorry

package $package;
use base 'Exporter';

use XML::LibXML   ();

our \@EXPORT;
__HEADER
}

=method freeze PAIRS|HASH

Produce the dump for a group of code references, which will be
made available under a normal subroutine name.  This method
can only be called once.

=error freeze can only be called once
The various closures may have related variables, and therefore
need to be dumped in one go.

=error value with $name is not a code reference
=error freeze needs PAIRS or a HASH
=cut

sub freeze(@)
{   my $self = shift;

    croak "ERROR: freeze needs PAIRS or a HASH"
        if (@_==1 && ref $_[0] ne 'HASH') || @_ % 2;

    croak "ERROR: freeze can only be called once"
        if $self->{XCD_freeze}++;

    my (@names, @data);
    if(@_==1)   # Hash
    {   my $h  = shift;
        @names = keys %$h;
        @data  = values %$h;
    }
    else        # Pairs
    {   while(@_)
        {   push @names, shift;
            push @data, shift;
        }
    }

    my $fh = $self->file;
    my $export = join "\n    ", sort @names;
    $fh->print("push \@EXPORT, qw/\n    $export/;\n\n");

    Data::Dump::Streamer->new->To($fh)->Data(@data)->Out;

    for(my $i = 0; $i < @names; $i++)
    {   ref $data[$i] eq 'CODE'
            or croak "ERROR: value with '$names[$i]' is not a code reference";
        my $code  = '$CODE'.($i+1);
        $fh->print("*${names[$i]} = $code;\n");
    }
}

=method footer FILEHANDLE
=cut

sub footer($)
{   my ($self, $fh) = @_;
    $fh->print( "\n1;\n" );
}

1;
