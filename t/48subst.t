#!/usr/bin/perl
# SubstitutionGroups

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;
use XML::Compile::Tester;

use Test::More tests => 38;

my $TestNS2 = "http://second-ns";

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:one="$TestNS">

<element name="head" type="string" abstract="true" />

<element name="test1">
  <complexType>
    <sequence>
      <element name="t1" type="int"  />
      <element ref="one:head"        />
      <element name="t3" type="int"  />
    </sequence>
  </complexType>
</element>

<element name="test2">
  <complexType>
    <sequence>
      <element ref="one:head" minOccurs="0" maxOccurs="3" />
      <element name="id2" type="int" />
    </sequence>
  </complexType>
</element>

<!-- more schemas below -->
</schema>
__SCHEMA__

ok(defined $schema);

eval { test_rw($schema, test1 => <<__XML, undef) };
<test1><t1>42</t1><t2>43</t2><t3>44</t3></test1>
__XML

ok($@, 'compile-time error');
my $error = $@;
is($error, "error: no substitutionGroups found for {http://test-types}head at {http://test-types}test1#subst\n");

$schema->importDefinitions( <<__EXTRA__ );
<!-- alternatives in same namespace -->
<schemas>

<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:one="$TestNS">

<!-- this is not an extension of head's "string" but easier to recognize -->
<element name="alt1" substitutionGroup="one:head">
  <complexType>
    <sequence>
      <element name="a1" type="int" />
    </sequence>
  </complexType>
</element>

</schema>

<!-- alternatives in other namespace -->
<schema targetNamespace="$TestNS2"
        xmlns="$SchemaNS"
        xmlns:one="$TestNS">
        xmlns:two="$TestNS2">

<element name="alt2" substitutionGroup="one:head">
  <complexType>
    <sequence>
      <element name="a2" type="int" />
    </sequence>
  </complexType>
</element>

</schema>

</schemas>
__EXTRA__

my %t1 = (t1 => 42, alt1 => {a1 => 43}, t3 => 44);
test_rw($schema, test1 => <<__XML, \%t1);
<test1><t1>42</t1><alt1><a1>43</a1></alt1><t3>44</t3></test1>
__XML

my %t2 = (t1 => 45, alt2 => {a2 => 46}, t3 => 47);
test_rw($schema, test1 => <<__XML, \%t2);
<test1><t1>45</t1><alt2><a2>46</a2></alt2><t3>47</t3></test1>
__XML

### test2

my %t3 =
 ( head =>
   [ {alt1 => {a1 => 50}}
   , {alt1 => {a1 => 51}}
   , {alt2 => {a2 => 52}}
   ]
 , id2 => 53
 );

test_rw($schema, test2 => <<__XML, \%t3);
<test2>
  <alt1><a1>50</a1></alt1>
  <alt1><a1>51</a1></alt1>
  <alt2><a2>52</a2></alt2>
  <id2>53</id2>
</test2>
__XML

my %t4 = (id2 => 54);
test_rw($schema, test2 => <<__XML, \%t4);
<test2>
  <id2>54</id2>
</test2>
__XML

my %t5 =
 ( head =>
   [ {alt2 => {a2 => 55}}
   , {alt1 => {a1 => 56}}
   ]
 , id2 => 57
 );

test_rw($schema, test2 => <<__XML, \%t5);
<test2>
  <alt2><a2>55</a2></alt2>
  <alt1><a1>56</a1></alt1>
  <id2>57</id2>
</test2>
__XML
