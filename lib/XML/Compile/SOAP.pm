use warnings;
use strict;

package XML::Compile::SOAP;

use Log::Report 'xml-compile', syntax => 'SHORT';
use XML::Compile::Util  qw/pack_type/;

=chapter NAME
XML::Compile::SOAP - base-class for SOAP implementations

=chapter SYNOPSIS

 use XML::Compile::SOAP::SOAP11;
 use XML::Compile::Util qw/pack_type/;

 # There are quite some differences between SOAP1.1 and 1.2
 my $soap   = XML::Compile::SOAP::SOAP11->new;

 # load extra schemas always explicitly
 $soap->schemas->importDefinitions(...);

 my $h1type = pack_type $myns, $sometype;
 my $b1type = "{$myns}$othertype";  # less clean

 # Request, answer, and call usually created via WSDL
 my $request = $soap->compile
   ('CLIENT', 'INPUT'               # client to server
   , header   => [ h1 => $h1type ]
   , body     => [ b1 => $b1type ]
   , destination    => [ h1 => 'NEXT' ]
   , mustUnderstand => 'h1'
   );

 my $answer = $soap->compile
   ('CLIENT', 'OUTPUT'              # server to client
   , header   => [ h2 => $h2type ]
   , body     => [ b2 => $b2type ]
   , headerfault => [ ... ]
   , fault    => [ ... ]
   );

 my $call  = $soap->call($request, $answer, address => $endpoint);

 my $result = $call->(h1 => ..., b1 => ...);
 print $result->{h2}->{...};
 print $result->{b2}->{...};

=chapter DESCRIPTION
**WARNING** Implementation not finished: not usable!!

This module handles the SOAP protocol.  The first implementation is
SOAP1.1 (F<http://www.w3.org/TR/2000/NOTE-SOAP-20000508/>), which is still
most often used.  The SOAP1.2 definition (F<http://www.w3.org/TR/soap12/>)
are different; this module tries to define a sufficiently
abstract interface to hide the protocol differences.

=section Limitations

On the moment, the following limitations exist:

=over 4

=item .
Only qualified header and body elements are supported.

=item .
Only document/literal use is supported, not XML-RPC.

=back

=chapter METHODS

=section Constructors

=method new OPTIONS

=requires envelope_ns URI
=requires encoding_ns URI

=option   media_type MIMETYPE
=default  media_type C<application/soap+xml>

=option   schemas    C<XML::Compile::Schema> object
=default  schemas    created internally
Use this when you have already processed some schema definitions.  Otherwise,
you can add schemas later with C<< $soap->schames->importDefinitions() >>
=cut

sub new($@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{env}     = $args->{envelope_ns} || panic "no envelope namespace";
    $self->{enc}     = $args->{encoding_ns} || panic "no encoding namespace";
    $self->{mime}    = $args->{media_type}  || 'application/soap+xml';
    $self->{schemas} = $args->{schemas}     || XML::Compile::Schema->new;
    $self;
}

=section Accessors
=method envelopeNS
=method encodingNS
=cut

sub envelopeNS() {shift->{env}}
sub encodingNS() {shift->{enc}}

=method schemas
Returns the M<XML::Compile::Schema> object which contains the
knowledge about the types.
=cut

sub schemas()    {shift->{schemas}}

=section SOAPAction

=method compile ('CLIENT'|'SERVER'),('INPUT'|'OUTPUT'), OPTIONS
The payload is defined explicitly, where all headers and bodies are
specified as ARRAY containing key-value pairs (ENTRIES).  When you
have a WSDL file, these ENTRIES are generated automatically.

As role, you specify whether your application is a C<CLIENT> (creates
INPUT messages to the server, accepts OUTPUT messages), or a
C<SERVER> (accepting INPUT queries, producing OUTPUT messages).
The combination of the first and second parameter determine whether
an XML reader or XML writer is to be created.
NB: a C<CLIENT> C<INPUT> message is a message which is sent by
the client as input to the server, according the WSDL terminology
definition.

To make your life easy, the ENTRIES use a label (a free to choose key,
the I<part> in WSDL terminology), to ease relation of your data with
the type where it belongs to.  The type of an entry (the value) is
defines as an C<any> type in the schema and therefore you will need
to explicitly specify the type of the element to be processed.

=option  header ENTRIES
=default header C<undef>
ARRAY of PAIRS, defining a nice LABEL (free of choice but unique)
and an element reference.  The LABEL will appear in your code only, to
refer to the element in a simple way.

=option  body   ENTRIES
=default body   C<undef>

=option  fault  ENTRIES
=default fault  []
The SOAP1.1 and SOAP1.2 protocols define fault entries in the
answer.  Both have a location to add your own additional
information: the type(-processor) is to specified here, but the
returned information structure is larger and differs per SOAP
implementation.

=option  mustUnderstand STRING|ARRAY-OF-STRING
=default mustUnderstand []
Writers only.  The specified header entry labels specify which elements
must be understood by the destination.  These elements will get the
C<mustUnderstand> attribute set to C<1> (soap1.1) or C<true> (soap1.2).

=option  destination ARRAY
=default destination []
Writers only.  Indicate who the target of the header entry is.
By default, the end-point is the destination of each header element.

The ARRAY contains a LIST of key-value pairs, specifing an entry label
followed by an I<actor> (soap1.1) or I<role> (soap1.2) URI.  You may use
the predefined actors/roles, like 'NEXT'.  See M<roleAbbreviation()>.

=option  role URI|ARRAY-OF-URI
=default role C<ULTIMATE>
Readers only.
One or more URIs, specifying the role(s) you application has in the
process.  Only when your role contains C<ULTIMATE>, the body is
parsed.  Otherwise, the body is returned as uninterpreted XML tree.
You should not use the role C<NEXT>, because every intermediate
node is a C<NEXT>.

All understood headers are parsed when the C<actor> (soap1.1) or
C<role> (soap1.2) attribute address the specified URI.  When other
headers emerge which are not understood but carry the C<mustUnderstood>
attribute, an fault is returned automatically.  In that case, the
call to the compiled subroutine will return C<undef>.

=option  roles ARRAY-OF-URI
=default roles []
Alternative for option C<role>

=error an input message does not have faults
=error headerfault does only exist in SOAP1.1

=error option 'role' only for readers
=error option 'roles' only for readers
=error option 'destination' only for writers
=error option 'mustUnderstand' only for writers
=cut

sub compile($@)
{   my ($self, $role, $inout, %args) = @_;

    my $action = $self->direction($role, $inout);

    die "ERROR: an input message does not have faults\n"
        if $inout eq 'INPUT'
        && ($args{headerfault} || $args{fault});

      $action eq 'WRITER'
    ? $self->_writer(\%args)
    : $self->_reader(\%args);
}

###
### WRITER internals
###

sub _writer($)
{   my ($self, $args) = @_;

    die "ERROR: option 'role' only for readers"  if $args->{role};
    die "ERROR: option 'roles' only for readers" if $args->{roles};

    my $schema = $self->schemas;
    my $envns  = $self->envelopeNS;

    my %allns;
    my @allns  = @{ $args->{prefix_table} || [] };
    while(@allns)
    {   my ($prefix, $uri) = splice @allns, 0, 2;
        $allns{$uri} = {uri => $uri, prefix => $prefix};
    }

    my $understand = $args->{mustUnderstand};
    my %understand = map { ($_ => 1) }
        ref $understand eq 'ARRAY' ? @$understand
      : defined $understand ? "$understand" : ();

    my $destination = $args->{destination};
    my %destination = ref $destination eq 'ARRAY' ? @$destination : ();

    #
    # produce header parsing
    #

    my @header;
    my @h = @{$args->{header} || []};
    while(@h)
    {   my ($label, $element) = splice @h, 0, 2;

        my $code = $schema->compile
           ( WRITER => $element
           , output_namespaces  => \%allns
           , include_namespaces => 0
           , elements_qualified => 'TOP'
           );

        push @header, $label => $self->_writer_header_env($code, \%allns
             , delete $understand{$label}, delete $destination{$label});
    }

    keys %understand
        and error __x"mustUnderstand for unknown header {headers}"
                , headers => [keys %understand];

    keys %destination
        and error __x"actor for unknown header {headers}"
                , headers => [keys %destination];

    my $headerhook = $self->_writer_hook($envns, 'Header', @header);

    #
    # Produce body parsing
    #

    my @body;
    my @b = @{$args->{body} || []};
    while(@b)
    {   my ($label, $element) = splice @b, 0, 2;

        my $code = $schema->compile
           ( WRITER => $element
           , output_namespaces  => \%allns
           , include_namespaces => 0
           , elements_qualified => 'TOP'
           );

        push @body, $label => $code;
    }

    my $bodyhook   = $self->_writer_hook($envns, 'Body', @body);

    #
    # Handle encodingStyle
    #

    my $encstyle = $self->_writer_encstyle_hook(\%allns);

    my $envelope = $self->schemas->compile
     ( WRITER => pack_type($envns, 'Envelope')
     , hooks  => [ $encstyle, $headerhook, $bodyhook ]
     , output_namespaces    => \%allns
     , elements_qualified   => 1
     , attributes_qualified => 1
     );

    sub { my ($values, $charset) = @_;
          my $doc = XML::LibXML::Document->new('1.0', $charset);
          $envelope->($doc, $values);
        };
}

sub _writer_hook($$@)
{   my ($self, $ns, $local, @do) = @_;
 
   +{ type    => pack_type($ns, $local)
    , replace =>
         sub { my ($doc, $data, $path, $tag) = @_;
               my %data = %$data;
               my @h = @do;
               my @childs;
               while(@h)
               {   my ($k, $c) = (shift @h, shift @h);
                   if(my $v = delete $data{$k})
                   {    my $g = $c->($doc, $v);
                        push @childs, $g if $g;
                   }
               }
               warn "ERROR: unused values @{[ keys %data ]}\n"
                   if keys %data;

               @childs or return ();
               my $node = $doc->createElement($tag);
               $node->appendChild($_) for @childs;
               $node;
             }
    };
}

sub _writer_encstyle_hook($)
{   my ($self, $allns) = @_;
    my $envns   = $self->envelopeNS;
    my $style_w = $self->schemas->compile
     ( WRITER => pack_type($envns, 'encodingStyle')
     , output_namespaces    => $allns
     , include_namespaces   => 0
     , attributes_qualified => 1
     );
    my $style;

    my $before  = sub {
	my ($doc, $values, $path) = @_;
        ref $values eq 'HASH' or return $values;
        $style = $style_w->($doc, delete $values->{encodingStyle});
        $values;
      };

    my $after = sub {
        my ($doc, $node, $path) = @_;
        $node->addChild($style) if defined $style;
        $node;
      };

   { before => $before, after => $after };
}

###
### READER internals
###

sub _reader($)
{   my ($self, $args) = @_;

    die "ERROR: option 'destination' only for writers"
        if $args->{destination};

    die "ERROR: option 'mustUnderstand' only for writers"
        if $args->{understand};

    my $schema = $self->schemas;
    my $envns  = $self->envelopeNS;

    my $roles  = $args->{roles} || $args->{role} || 'ULTIMATE';
    my @roles  = ref $roles eq 'ARRAY' ? @$roles : $roles;

    #
    # produce header parsing
    #

    my @header;
    my @h = @{$args->{header} || []};
    while(@h)
    {   my ($label, $element) = splice @h, 0, 2;
        push @header, [$label, $element, $schema->compile(READER => $element)];
    }

    my $headerhook = $self->_reader_hook($envns, 'Header', @header);

    #
    # Produce body parsing
    #

    my @body;
    my @b = @{$args->{body} || []};
    while(@b)
    {   my ($label, $element) = splice @b, 0, 2;
        push @body, [$label, $element, $schema->compile(READER => $element)];
    }

    my $bodyhook   = $self->_reader_hook($envns, 'Body', @body);

    #
    # Handle encodingStyle
    #

    my $encstyle = $self->_reader_encstyle_hook;

    my $envelope = $self->schemas->compile
     ( READER => pack_type($envns, 'Envelope')
     , hooks  => [ $encstyle, $headerhook, $bodyhook ]
     );

    $envelope;
}

sub _reader_hook($$@)
{   my ($self, $ns, $local, @do) = @_;
    my %trans = map { ($_->[1] => [ $_->[0], $_->[2] ]) } @do; # we need copies
 
   +{ type    => pack_type($ns, $local)
    , replace =>
        sub
          { my ($xml, $trans, $path, $label) = @_;
            my %h;
            foreach my $child ($xml->childNodes)
            {   next unless $child->isa('XML::LibXML::Element');
                my $type = pack_type $child->namespaceURI, $child->localName;
                if(my $t = $trans{$type})
                {   my $v = $t->[1]->($child);
                    $h{$t->[0]} = $v if defined $v;
                }
                else
                {   $h{$type} = $child;
                }
            }
            ($label => \%h);
          }
    };
}

sub _reader_encstyle_hook()
{   my $self     = shift;
    my $envns    = $self->envelopeNS;
    my $style_r = $self->schemas->compile
      ( READER => pack_type($envns, 'encodingStyle')
      );
    my $encstyle;

    my $before = sub
      { my $xml   = $_[0];
        $encstyle = $style_r->(@_);
        $xml->removeAttribute('encodingStyle');
        $xml;
      };

   my $after   = sub
      { defined $encstyle or return $_[1];
        my $h = $_[1];
        ref $h eq 'HASH' or $h = { _ => $h };
        $h->{encodingStyle} = $encstyle;
        $h;
      };

   { before => $before, after => $after };
}

=method direction ROLE, INOUT
Based on the ROLE of the application (C<CLIENT> or C<SERVER>) and the 
direction indication (C<INPUT> or C<OUTPUT> from the WSDL), this
returns whether a C<READER> or C<WRITER> needs to be generated.

=error role must be CLIENT or SERVER, not $role
=error message is INPUT or OUTPUT, not $inout
=cut

sub direction($$)
{   my ($self, $role, $inout) = @_;

    my $direction
      = $role  eq 'CLIENT' ?  1
      : $role  eq 'SERVER' ? -1
      : die "ERROR: role must be CLIENT or SERVER, not $role\n";

    $direction
     *= $inout eq 'INPUT'  ?  1
      : $inout eq 'OUTPUT' ? -1
      : die "ERROR: message is INPUT or OUTPUT, not $inout\n" ;

    $direction==1 ? 'WRITER' : 'READER';
}

=method roleAbbreviation STRING
Translates actor/role/destination abbreviations into URIs. Various
SOAP protocol versions have different pre-defined URIs, which can
be abbreviated for readibility.  Returns the unmodified STRING in
all other cases.
=cut

sub roleAbbreviation($) { panic "not implemented" }

=chapter DETAILS

=section Do it yourself, no WSDL

Does this all look too complicated?  It isn't that bad.  The following
example is used as test-case t/82soap11.t, directly taken from the SOAP11
specs section 1.3 example 1.

 # for simplification
 my $TestNS   = 'http://test-types';
 my $SchemaNS = 'http://www.w3.org/2001/XMLSchema';

First, the schema (hopefully someone else created for you, because they
can be quite hard to create correctly) is in file C<myschema.xsd>

 <schema targetNamespace="$TestNS"
   xmlns="$SchemaNS">

 <element name="GetLastTradePrice">
   <complexType>
      <all>
        <element name="symbol" type="string"/>
      </all>
   </complexType>
 </element>

 <element name="GetLastTradePriceResponse">
   <complexType>
      <all>
         <element name="price" type="float"/>
      </all>
   </complexType>
 </element>

 <element name="Transaction" type="int"/>
 </schema>

Ok, now the program you create the request:

 use XML::Compile::SOAP::SOAP11;
 use XML::Compile::Util  qw/pack_type/;

 my $soap   = XML::Compile::SOAP::SOAP11->new;
 $soap->schemas->importDefinitions('myschema.xsd');

 my $get_price = $soap->compile
  ( 'CLIENT', 'INPUT'
  , header => [ transaction => pack_type($TestNS, 'Transaction') ]
  , body =>   [ request => pack_type($TestNS, 'GetLastTradePrice') ]
  , mustUnderstand => 'transaction'
  , destination => [ 'transaction' => 'NEXT http://actor' ]
  );

C<INPUT> is used in the WSDL terminology, indicating this message is
an input message for the server.  This C<$get_price> is a WRITER.  Above
is done only once in the initialization phase of your program.

At run-time, you have to call the CODE reference with a
data-structure which is compatible with the schema structure.
(See M<XML::Compile::Schema::template()> if you have no clue how it should
look)  So: let's send this:

 # insert your data
 my %data_in =
   ( Header => {transaction => 5}
   , Body   => {request => {symbol => 'DIS'}}
   );

 # create a XML::LibXML tree
 my $xml  = $get_price->(\%data_in, 'UTF-8');
 print $xml->toString;

And the output is:

 <SOAP-ENV:Envelope
    xmlns:x0="http://test-types"
    xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
   <SOAP-ENV:Header>
     <x0:Transaction
       mustUnderstand="1"
       actor="http://schemas.xmlsoap.org/soap/actor/next http://actor">
         5
     </x0:Transaction>
   </SOAP-ENV:Header>
   <SOAP-ENV:Body>
     <x0:GetLastTradePrice>
       <symbol>DIS</symbol>
     </x0:GetLastTradePrice>
   </SOAP-ENV:Body>
 </SOAP-ENV:Envelope>

Some transport protocol will sent this data from the client to the
server.  See M<XML::Compile::SOAP::HTTP>, as one example.

On the SOAP server side, we will parse the message.  The string C<$soap>
contains the XML.  The program looks like this:

 my $server = $soap->compile       # create once
  ( 'SERVER', 'INPUT'
  , header => [ transaction => pack_type($TestNS, 'Transaction') ]
  , body =>   [ request => pack_type($TestNS, 'GetLastTradePrice') ]
  );

 my $data_out = $server->($soap);  # call often

Now, the C<$data_out> reference on the server, is stucturally exactly 
equivalent to the C<%data_in> from the client.
=cut

1;
