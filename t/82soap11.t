#!/usr/bin/perl
# Test SOAP

use warnings;
use strict;

use lib 'lib','t';
use TestTools;
use Test::Deep   qw/cmp_deeply/;

use Data::Dumper;
$Data::Dumper::Indent = 1;

use XML::Compile::SOAP::SOAP11;

use Test::More tests => 5;
use XML::LibXML;

# elementFormDefault="qualified">
my $schema = <<__HELPERS;
<schema targetNamespace="$TestNS"
  xmlns="$SchemaNS">

# mimic types of SOAP1.1 section 1.3 example 1
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
__HELPERS

#
# Create and interpret a message
#

my $soap = XML::Compile::SOAP::SOAP11->new;
isa_ok($soap, 'XML::Compile::SOAP::SOAP11');

$soap->schemas->importDefinitions($schema);
#warn "$_\n" for sort $soap->schemas->elements;

my @msg1_struct = 
 ( header => [ transaction => "{$TestNS}Transaction" ]
 , body =>   [ request => "{$TestNS}GetLastTradePrice" ]
 );

my $msg1_data
 = { Header => {transaction => 5}
   , Body   => {request => {symbol => 'DIS'}}
   };

my $msg1_soap = <<__MESSAGE1;
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
__MESSAGE1

# Create

my $client1 = $soap->compile
 ( 'CLIENT', 'INPUT'
 , @msg1_struct
 , mustUnderstand => 'transaction'
 , destination => [ 'transaction' => 'NEXT http://actor' ]
 );

is(ref $client1, 'CODE', 'compiled a client');

my $xml1 = $client1->($msg1_data, 'UTF-8');

isa_ok($xml1, 'XML::LibXML::Node', 'produced XML');
compare_xml($xml1, $msg1_soap);

# Interpret incoming message

my $server1 = $soap->compile
 ( 'SERVER', 'INPUT'
 , @msg1_struct
 );

is(ref $server1, 'CODE', 'compiled a server');

__END__
WORK IN PROGRESS

my $hash1 = $server1->($msg1_soap);
is(ref $hash1, 'HASH', 'produced HASH');

#warn Dumper $hash1;
cmp_deeply($hash1, $msg1_data, "server parsed input");
