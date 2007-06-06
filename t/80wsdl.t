#!/usr/bin/perl
# Test interpretation of WSDL.
# The definitions are copied frm the the WSDL 1.1 technical report,
# available from http://www.w3.org/TR/wsdl/
# with bugfix:
#  -  <port name="StockQuotePort" binding="tns:StockQuoteBinding">
#  +  <port name="StockQuotePort" binding="tns:StockQuoteSoapBinding">

use warnings;
use strict;

use lib 'lib','t';
use TestTools;
use Data::Dumper;
$Data::Dumper::Indent = 1;

use XML::Compile::WSDL;

use Test::More tests => 26;
my $wsdlns = 'http://schemas.xmlsoap.org/wsdl/';

my $xml_xsd = <<'__STOCKQUOTE_XSD';
<?xml version="1.0"?>
<schema targetNamespace="http://example.com/stockquote/schemas"
       xmlns="http://www.w3.org/2000/10/XMLSchema">
       
    <element name="TradePriceRequest">
        <complexType>
            <all>
                <element name="tickerSymbol" type="string"/>
            </all>
        </complexType>
    </element>
    <element name="TradePrice">
        <complexType>
            <all>
                <element name="price" type="float"/>
            </all>
        </complexType>
    </element>
</schema>
__STOCKQUOTE_XSD

my $xml_wsdl = <<'__STOCKQUOTE_WSDL';
<?xml version="1.0"?>
<definitions name="StockQuote"

targetNamespace="http://example.com/stockquote/definitions"
          xmlns:tns="http://example.com/stockquote/definitions"
          xmlns:xsd1="http://example.com/stockquote/schemas"
          xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
          xmlns="http://schemas.xmlsoap.org/wsdl/">

   <import namespace="http://example.com/stockquote/schemas"
           location="http://example.com/stockquote/stockquote.xsd"/>

    <message name="GetLastTradePriceInput">
        <part name="body" element="xsd1:TradePriceRequest"/>
    </message>

    <message name="GetLastTradePriceOutput">
        <part name="body" element="xsd1:TradePrice"/>
    </message>

    <portType name="StockQuotePortType">
        <operation name="GetLastTradePrice">
           <input message="tns:GetLastTradePriceInput"/>
           <output message="tns:GetLastTradePriceOutput"/>
        </operation>
    </portType>
</definitions>
__STOCKQUOTE_WSDL

my $servns    = 'http://example.com/stockquote/service';
my $servlocal = 'StockQuoteService';
my $servname  = "{$servns}$servlocal";

my $xml_service = <<'__STOCKQUOTESERVICE_WSDL';
<?xml version="1.0"?>
<definitions name="StockQuote"

targetNamespace="http://example.com/stockquote/service"
          xmlns:tns="http://example.com/stockquote/service"
          xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
          xmlns:defs="http://example.com/stockquote/definitions"
          xmlns="http://schemas.xmlsoap.org/wsdl/">

   <import namespace="http://example.com/stockquote/definitions"
           location="http://example.com/stockquote/stockquote.wsdl"/>

    <binding name="StockQuoteSoapBinding" type="defs:StockQuotePortType">
        <soap:binding style="document" transport="http://schemas.xmlsoap.org/soap/http"/>
        <operation name="GetLastTradePrice">
           <soap:operation soapAction="http://example.com/GetLastTradePrice"/>
           <input>
               <soap:body use="literal"/>
           </input>
           <output>
               <soap:body use="literal"/>
           </output>
        </operation>
    </binding>

    <service name="StockQuoteService">
        <documentation>My first service</documentation>
        <port name="StockQuotePort" binding="tns:StockQuoteSoapBinding">
           <soap:address location="http://example.com/stockquote"/>
        </port>
    </service>
</definitions>
__STOCKQUOTESERVICE_WSDL

###
### BEGIN OF TESTS
###

my $wsdl = XML::Compile::WSDL->new
 ( $xml_service
 , schema_dirs => 'xsd'
 );

ok(defined $wsdl, "created object");
isa_ok($wsdl, 'XML::Compile::WSDL');
is($wsdl->wsdlNamespace, $wsdlns);

my @services = $wsdl->find('service');
cmp_ok(scalar(@services), '==', 1, 'find service list context');
is($services[0]->{name}, $servlocal);

my $s   = eval { $wsdl->find(service => 'aap') };
my $err = $@; $err =~ s! at t/80.*\n$!!;
ok(!defined $s, 'find non-existing service');

is($err, <<'__ERR');
ERROR: no definition for 'aap' as service.  Defined is
    {http://example.com/stockquote/service}StockQuoteService
__ERR

$s = eval { $wsdl->find(service => $servname) };
$err = $@;
ok(defined $s, "request existing service $servlocal");
is($@, '', 'no errors');
ok(UNIVERSAL::isa($s, 'HASH'));

my $s2 = eval { $wsdl->find('service') };
$err = $@;
ok(defined $s, "request only service, not by name");
is($@, '', 'no errors');
cmp_ok($s, '==', $s2, 'twice same definition');

#warn Dumper $s;

$wsdl->importDefinitions($xml_xsd);
$wsdl->addWSDL($xml_wsdl);

my $op = eval { $wsdl->operation('noot') };
$err = $@; $err =~ s!\sat t/80.*\n$!\n!;
ok(!defined $op, "non-existing operation");
is($err, <<'__ERR');
ERROR: no operation 'noot' for portType '{http://example.com/stockquote/definitions}StockQuotePortType', pick from
    GetLastTradePrice
__ERR

$op = eval { $wsdl->operation('GetLastTradePrice') };
$err = $@ || '';
ok(defined $op, 'existing operation');
is($@, '', 'no errors');
isa_ok($op, 'XML::Compile::SOAP::Operation');
is($op->kind, 'request-response');

#delete $op->{schemas};
#warn Dumper $op;

my @addrs = $op->endPointAddresses;
cmp_ok(scalar @addrs, '==', 1, 'get endpoint address');
is($addrs[0], 'http://example.com/stockquote');

my $http1 = 'http://schemas.xmlsoap.org/soap/http';
ok($op->canTransport($http1, 'document'), 'can transport HTTP document');
ok(!$op->canTransport($http1, 'rpc'), 'cannot transport RPC (yet)');
ok(!$op->canTransport('http://', 'document'), 'only transport HTTP');

my ($action, $style) = $op->action;
is($action, 'http://example.com/GetLastTradePrice', 'action');
ok(!defined $style);
