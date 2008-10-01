#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 56;
use XML::Compile::Util  qw/SCHEMA2001i/;
my $xsi    = SCHEMA2001i;

my $schema = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<element name="test1">
  <complexType>
    <sequence>
      <element name="e1" type="int" />
      <element name="e2" type="int" nillable="true" />
      <element name="e3" type="int" />
    </sequence>
  </complexType>
</element>

#rt.cpan.org #39215
<simpleType name="ID">
  <restriction base="string">
     <length value="18"/>
     <pattern value="[a-zA-Z0-9]{18}"/>
   </restriction>
</simpleType>
<element name="roleId" type="me:ID" nillable="true"/>

<element name="test2">
  <complexType>
    <sequence>
      <element name="roleId" type="me:ID" nillable="true"/>
    </sequence>
  </complexType>
</element>

</schema>
__SCHEMA__

ok(defined $schema);

set_compile_defaults
   include_namespaces => 1;

#
# simple element type
#

test_rw($schema, test1 => <<__XML, {e1 => 42, e2 => 43, e3 => 44} );
<test1 xmlns:xsi="$xsi"><e1>42</e1><e2>43</e2><e3>44</e3></test1>
__XML

test_rw($schema, test1 => <<__XML, {e1 => 42, e2 => 'NIL', e3 => 44} );
<test1 xmlns:xsi="$xsi"><e1>42</e1><e2 xsi:nil="true"/><e3>44</e3></test1>
__XML

my %t1c = (e1 => 42, e2 => 'NIL', e3 => 44);
test_rw($schema, test1 => <<__XML, \%t1c, <<__XMLWriter);
<test1 xmlns:xsi="$xsi"><e1>42</e1><e2 xsi:nil="1" /><e3>44</e3></test1>
__XML
<test1 xmlns:xsi="$xsi"><e1>42</e1><e2 xsi:nil="true"/><e3>44</e3></test1>
__XMLWriter

{   my $error = reader_error($schema, test1 => <<__XML);
<test1 xmlns:xsi="$xsi"><e1></e1><e2 xsi:nil="true"/><e3>45</e3></test1>
__XML
   is($error,"illegal value `' for type {http://www.w3.org/2001/XMLSchema}int");
}

{   my %t1b = (e1 => undef, e2 => undef, e3 => 45);
    my $error = writer_error($schema, test1 => \%t1b);

    is($error, "required value for element `e1' missing at {http://test-types}test1");
}

{   my $error = reader_error($schema, test1 => <<__XML);
<test1><e1>87</e1><e3>88</e3></test1>
__XML
    is($error, "data for element or block starting with `e2' missing at {http://test-types}test1");
}

#
# fix broken specifications
#

set_compile_defaults
    interpret_nillable_as_optional => 1;

my %t1d = (e1 => 89, e2 => undef, e3 => 90);
my %t1e = (e1 => 91, e2 => 'NIL', e3 => 92);
test_rw($schema, test1 => <<__XML, \%t1d, <<__XML, \%t1e);
<test1><e1>89</e1><e3>90</e3></test1>
__XML
<test1><e1>91</e1><e3>92</e3></test1>
__XML

#
# rt.cpan.org #39215
#

set_compile_defaults
   include_namespaces => 1;  # reset

test_rw($schema, test2 => <<__XML, {roleId => 'NIL'});
<test2 xmlns:xsi="$xsi">
  <roleId xsi:nil="true"/>
</test2>
__XML

test_rw($schema, roleId => <<__XML, 'NIL');
<roleId xmlns:xsi="$xsi" xsi:nil="true"/>
__XML
