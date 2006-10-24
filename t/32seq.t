#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 133;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

<!-- sequence with one element -->

<element name="test1">
  <complexType>
    <sequence>
       <element name="t1_a" type="int" />
    </sequence>
  </complexType>
</element>

<element name="test3" type="me:t3" />
<complexType name="t3">
  <sequence>
     <element name="t3_a" type="int" />
  </sequence>
</complexType>

<!-- sequence with two elements -->

<element name="test5">
  <complexType>
    <sequence>
      <element name="t5_a" type="int" />
      <element name="t5_b" type="int" />
    </sequence>
  </complexType>
</element>

<element name="test6" type="me:t6" />
<complexType name="t6">
  <sequence>
    <element name="t6_a" type="int" />
    <element name="t6_b" type="int" />
  </sequence>
</complexType>

<!-- choice with one element -->

<element name="test7" type="me:t7" />
<complexType name="t7">
  <choice>
    <element name="t7_a" type="int" />
  </choice>
</complexType>

<element name="test8">
  <complexType>
    <choice>
       <element name="t8_a" type="int" />
    </choice>
  </complexType>
</element>

<!-- choice with more elements -->

<element name="test10" type="me:t10" />
<complexType name="t10">
  <choice>
    <element name="t10_a" type="int" />
    <element name="t10_b" type="int" />
    <element name="t10_c" type="int" />
  </choice>
</complexType>

<!-- occurs -->

<element name="test11">
  <complexType>
    <sequence>
      <element name="t11_a" type="int" minOccurs="0" />
      <element name="t11_b" type="int" maxOccurs="2" />
      <element name="t11_c" type="int" minOccurs="2" maxOccurs="2" />
      <element name="t11_d" type="int" minOccurs="0" maxOccurs="2" />
      <element name="t11_e" type="int" minOccurs="0" maxOccurs="unbounded" />
    </sequence>
  </complexType>
</element>

</schema>
__SCHEMA__

ok(defined $schema);

#
# sequence as direct type
#

ok(1, "** Testing sequence with 1 element");

test_rw($schema, test1 => <<__XML__, {t1_a => 41});
<test1><t1_a>41</t1_a></test1>
__XML__

test_rw($schema, test3 => <<__XML__, {t3_a => 43});
<test3><t3_a>43</t3_a></test3>
__XML__

ok(1, "** Testing sequence with 2 elements");

test_rw($schema, test5 => <<__XML__, {t5_a => 47, t5_b => 48});
<test5><t5_a>47</t5_a><t5_b>48</t5_b></test5>
__XML__

test_rw($schema, test6 => <<__XML__, {t6_a => 48, t6_b => 49});
<test6><t6_a>48</t6_a><t6_b>49</t6_b></test6>
__XML__

{   my $error;
    @run_opts =
     ( invalid => sub {no warnings;$error = "@_"; 51}
     , check_occurs => 1
     );

    test_rw($schema, test6 => <<__XML__, {t6_a => 51, t6_b => 50}, <<__XML__);
<test6><t6_b>50</t6_b></test6>
__XML__
<test6><t6_a>51</t6_a><t6_b>50</t6_b></test6>
__XML__

   ok($error, "missing required element");
   @run_opts = ();
}

ok(1, "** Testing choice with one element");

test_rw($schema, test7 => <<__XML__, {t7_a => 10});
<test7><t7_a>10</t7_a></test7>
__XML__

test_rw($schema, test8 => <<__XML__, {t8_a => 11});
<test8><t8_a>11</t8_a></test8>
__XML__

ok(1, "** Testing choice with multiple elements");

test_rw($schema, test10 => <<__XML__, {t10_a => 13});
<test10><t10_a>13</t10_a></test10>
__XML__

test_rw($schema, test10 => <<__XML__, {t10_b => 14});
<test10><t10_b>14</t10_b></test10>
__XML__

test_rw($schema, test10 => <<__XML__, {t10_c => 15});
<test10><t10_c>15</t10_c></test10>
__XML__

# The next is not correct, but when we do not check occurrences it is...
{  push @run_opts, check_occurs => 0;

   test_rw($schema, test10 => <<__XML__, {t10_a => 16, t10_c => 17});
<test10><t10_a>16</t10_a><t10_c>17</t10_c></test10>
__XML__

   test_rw($schema, test11 => <<__XML__, {t11_b => [16], t11_c => [17]});
<test11>
  <t11_b>16</t11_b>
  <t11_c>17</t11_c>
</test11>
__XML__

   splice @run_opts, -2;
}

{   my $error = '';
    @run_opts = (invalid => sub {$error .= "@_\n"});

    test_rw($schema, test11 => <<__XML__, {t11_b => [16], t11_c => [17]});
<test11>
  <t11_b>16</t11_b>
  <t11_c>17</t11_c>
</test11>
__XML__

    ok(length $error);
}

my %r11 = (t11_a => 20, t11_b => [21,22], t11_c => [23,24], t11_d => [25],
           t11_e => [26,27,28]);
test_rw($schema, test11 => <<__XML__, \%r11);
<test11>
  <t11_a>20</t11_a>
  <t11_b>21</t11_b>
  <t11_b>22</t11_b>
  <t11_c>23</t11_c>
  <t11_c>24</t11_c>
  <t11_d>25</t11_d>
  <t11_e>26</t11_e>
  <t11_e>27</t11_e>
  <t11_e>28</t11_e>
</test11>
__XML__
