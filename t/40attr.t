#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 61;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<!-- sequence with one element -->

<element name="test1" type="me:t1" />
<complexType name="t1">
  <complexContent>
    <sequence>
      <element name="t1_a" type="int" />
      <element name="t1_b" type="int" />
    </sequence>
  </complexContent>
  <attribute name="a1_a" type="int" />
  <attribute name="a1_b" type="int" use="required" />
</complexType>

<element name="test2" type="me:t2" />
<complexType name="t2">
  <complexContent>
    <sequence>
      <element name="t2_a" type="int" minOccurs="0" />
      <element name="t2_b" type="int" minOccurs="0" />
    </sequence>
  </complexContent>
  <attribute name="a2_a" type="int" />
  <attributeGroup ref="me:a2" />
  <attribute name="a2_b" type="int" />
</complexType>
<attributeGroup name="a2">
  <attribute name="a2_c" type="int" use="required" />
  <attribute name="a2_d" type="int" use="optional" />
  <attribute name="a2_e" type="int" use="prohibited" />
</attributeGroup>

</schema>
__SCHEMA__

ok(defined $schema);

#
# simple attributes
#

ok(1, "** Testing attributes");

my %t1 = (t1_a => 10, t1_b => 9, a1_a => 11, a1_b => 12);
run_test($schema, test1 => <<__XML__, \%t1);
<test1 a1_a="11" a1_b="12">
  <t1_a>10</t1_a>
  <t1_b>9</t1_b>
</test1>
__XML__

my %t1_b = (t1_a => 20, t1_b => 21, a1_b => 23);
run_test($schema, test1 => <<__XML__, \%t1_b);
<test1 a1_b="23">
  <t1_a>20</t1_a>
  <t1_b>21</t1_b>
</test1>
__XML__

{   my $error;
    @run_opts =
     ( invalid => sub {no warnings;$error = "@_"; 24}
     );

my %t1_c = (a1_b => 24, t1_a => 25, t1_b => 26);
run_test($schema, test1 => <<__XML__, \%t1_c, <<__XML__);
<test1>
  <t1_a>25</t1_a>
  <t1_b>26</t1_b>
</test1>
__XML__
<test1 a1_b="24">
  <t1_a>25</t1_a>
  <t1_b>26</t1_b>
</test1>
__XML__

   like($error, qr/ required$/);

   @run_opts = ();
}

ok(1, "** Testing attributeGroups");

my %t2_a = (a2_a => 30, a2_b => 31, a2_c => 29);
run_test($schema, test2 => <<__XML__, \%t2_a);
<test2 a2_a="30" a2_c="29" a2_b="31"/>
__XML__

my %t2_b = (a2_a => 32, a2_b => 33, a2_c => 34, a2_d => 35);
run_test($schema, test2 => <<__XML__, \%t2_b);
<test2 a2_a="32" a2_c="34" a2_d="35" a2_b="33"/>
__XML__

{   my @errors;
    @run_opts =
     ( invalid => sub {no warnings;push @errors, "$_[2] ($_[1])"; 24}
     );

   my %t2_a = (a2_c => 29);
   my %t2_b = (a2_c => 29, a2_e => 666);
   run_test($schema, test2 => <<__XML__, \%t2_a, <<__XML__, \%t2_b);
<test2 a2_c="29" a2_e="666" />
__XML__
<test2 a2_c="29"/>
__XML__

   is(shift @errors, "attribute a2_e prohibited (666)");
   is(shift @errors, "attribute a2_e prohibited (666)");
   ok(!@errors);

   @run_opts = ();
}
