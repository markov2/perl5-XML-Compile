#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 166;

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

<!-- occurs -->

<element name="test7">
  <complexType>
    <sequence>
      <element name="t7_a" type="int" minOccurs="0" />
      <element name="t7_b" type="int" maxOccurs="2" />
      <element name="t7_c" type="int" minOccurs="2" maxOccurs="2" />
      <element name="t7_d" type="int" minOccurs="0" maxOccurs="2" />
      <element name="t7_e" type="int" minOccurs="0" maxOccurs="unbounded" />
    </sequence>
  </complexType>
</element>

<!-- nested -->

<element name="test8">
  <complexType>
    <sequence>
      <element name="t8_a" type="int" />
      <element name="t8_b" type="int" />
      <sequence>
        <element name="t8_c" type="int" />
        <element name="t8_d" type="int" />
      </sequence>
      <element name="t8_e" type="int" />
      <element name="t8_f" type="int" />
    </sequence>
  </complexType>
</element>

<element name="test9">
  <complexType>
    <sequence>
      <sequence>
        <element name="t9_a" type="int" />
        <element name="t9_b" type="int" />
      </sequence>
      <element name="t9_c" type="int" />
      <element name="t9_d" type="int" />
      <sequence>
        <element name="t9_e" type="int" />
        <element name="t9_f" type="int" />
      </sequence>
    </sequence>
  </complexType>
</element>

<element name="test2">
  <complexType>
    <sequence>
      <sequence>
        <sequence>
          <element name="t2_a" type="int" />
        </sequence>
        <element name="t2_b" type="int" />
        <sequence>
          <element name="t2_c" type="int" />
        </sequence>
      </sequence>
      <element name="t2_d" type="int" />
      <sequence>
        <sequence>
          <sequence>
            <element name="t2_e" type="int" />
          </sequence>
        </sequence>
        <element name="t2_f" type="int" />
      </sequence>
    </sequence>
  </complexType>
</element>

<element name="test4">
  <complexType>
    <sequence>
      <element name="t4_a" type="int" />
      <sequence minOccurs="0" maxOccurs="unbounded">
        <element name="t4_b" type="int" />
        <element name="t4_c" type="int" minOccurs="0" maxOccurs="unbounded" />
      </sequence>
      <element name="t4_d" type="int" />
    </sequence>
  </complexType>
</element>

<element name="test11">
  <complexType>
    <sequence>
      <element name="t11_a" type="int" minOccurs="0" />
      <sequence minOccurs="1" maxOccurs="unbounded">
        <element name="t11_b" type="int" minOccurs="0"/>
        <element name="t11_c" type="int" />
      </sequence>
    </sequence>
  </complexType>
</element>

<element name="test12">
  <complexType>
    <sequence>
      <element name="t12" type="int" minOccurs="0" />
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

test_rw($schema, test1 => <<__XML, {t1_a => 41});
<test1><t1_a>41</t1_a></test1>
__XML

test_rw($schema, test3 => <<__XML, {t3_a => 43});
<test3><t3_a>43</t3_a></test3>
__XML

ok(1, "** Testing sequence with 2 elements");

test_rw($schema, test5 => <<__XML, {t5_a => 47, t5_b => 48});
<test5><t5_a>47</t5_a><t5_b>48</t5_b></test5>
__XML

test_rw($schema, test6 => <<__XML, {t6_a => 48, t6_b => 49});
<test6><t6_a>48</t6_a><t6_b>49</t6_b></test6>
__XML

{   @run_opts = (check_occurs => 1);
    my $error = reader_error($schema, test6 => <<__XML);
<test6><t6_b>50</t6_b></test6>
__XML

    is($error, "data for `t6_a' missing at {http://test-types}test6");
    @run_opts = ();
}

# The next is not correct, but when we do not check occurrences it is...
{  push @run_opts, check_occurs => 0;

   test_rw($schema, test7 => <<__XML, {t7_b => [16], t7_c => [17]});
<test7>
  <t7_b>16</t7_b>
  <t7_c>17</t7_c>
</test7>
__XML

   splice @run_opts, -2;
}

{   my $error = reader_error($schema, test7 => <<__XML);
<test7>
  <t7_b>16</t7_b>
  <t7_c>17</t7_c>
</test7>
__XML

    is($error, "data for `t7_c' missing at {http://test-types}test7");
}

my %r7 = (t7_a => 20, t7_b => [21,22], t7_c => [23,24], t7_d => [25],
           t7_e => [26,27,28]);
test_rw($schema, test7 => <<__XML, \%r7);
<test7>
  <t7_a>20</t7_a>
  <t7_b>21</t7_b>
  <t7_b>22</t7_b>
  <t7_c>23</t7_c>
  <t7_c>24</t7_c>
  <t7_d>25</t7_d>
  <t7_e>26</t7_e>
  <t7_e>27</t7_e>
  <t7_e>28</t7_e>
</test7>
__XML

my %r8a = qw/t8_a 30 t8_b 31 t8_c 32 t8_d 33 t8_e 34 t8_f 35/;
test_rw($schema, test8 => <<__XML, \%r8a);
<test8>
  <t8_a>30</t8_a>
  <t8_b>31</t8_b>
  <t8_c>32</t8_c>
  <t8_d>33</t8_d>
  <t8_e>34</t8_e>
  <t8_f>35</t8_f>
</test8>
__XML

my %r9a = qw/t9_a 30 t9_b 31 t9_c 32 t9_d 33 t9_e 34 t9_f 35/;
test_rw($schema, test9 => <<__XML, \%r9a);
<test9>
  <t9_a>30</t9_a>
  <t9_b>31</t9_b>
  <t9_c>32</t9_c>
  <t9_d>33</t9_d>
  <t9_e>34</t9_e>
  <t9_f>35</t9_f>
</test9>
__XML

##### test 2

my %r2a = qw/t2_a 30 t2_b 31 t2_c 32 t2_d 33 t2_e 34 t2_f 35/;
test_rw($schema, test2 => <<__XML, \%r2a);
<test2>
  <t2_a>30</t2_a>
  <t2_b>31</t2_b>
  <t2_c>32</t2_c>
  <t2_d>33</t2_d>
  <t2_e>34</t2_e>
  <t2_f>35</t2_f>
</test2>
__XML

#### test 4

my %t4a =
  ( t4_a => 40
  , seq_t4_b => [ {t4_b => 41, t4_c => [42]} ]
  , t4_d => 43
  );

test_rw($schema, test4 => <<__XML, \%t4a);
<test4>
  <t4_a>40</t4_a>
  <t4_b>41</t4_b>
  <t4_c>42</t4_c>
  <t4_d>43</t4_d>
</test4>
__XML

my %t4b =
  ( t4_a => 50
  , seq_t4_b => [ {t4_b => 51, t4_c => [52, 53]}
                , {t4_b => 54}
                , {t4_b => 55, t4_c => [56]}
                ]
  , t4_d => 57
  );

test_rw($schema, test4 => <<__XML, \%t4b);
<test4>
  <t4_a>50</t4_a>
  <t4_b>51</t4_b>
  <t4_c>52</t4_c>
  <t4_c>53</t4_c>
  <t4_b>54</t4_b>
  <t4_b>55</t4_b>
  <t4_c>56</t4_c>
  <t4_d>57</t4_d>
</test4>
__XML

my %t4c = (t4_a => 60, t4_d => 61);

test_rw($schema, test4 => <<__XML, \%t4c);
<test4>
  <t4_a>60</t4_a>
  <t4_d>61</t4_d>
</test4>
__XML

##### test 11

my %t11a = (t11_a => 20, seq_t11_b => [ {t11_b => 21, t11_c => 22 } ] );
test_rw($schema, test11 => <<__XML, \%t11a);
<test11>
  <t11_a>20</t11_a>
  <t11_b>21</t11_b>
  <t11_c>22</t11_c>
</test11>
__XML

my %t11b = (seq_t11_b =>
 [ {t11_b => 30, t11_c => 31 }
 , {t11_b => 32, t11_c => 33 }
 , {t11_b => 34, t11_c => 35 }
 ]
);

test_rw($schema, test11 => <<__XML, \%t11b);
<test11>
  <t11_b>30</t11_b>
  <t11_c>31</t11_c>
  <t11_b>32</t11_b>
  <t11_c>33</t11_c>
  <t11_b>34</t11_b>
  <t11_c>35</t11_c>
</test11>
__XML

my %t11c = (seq_t11_b =>
 [ {             t11_c => 40 }
 , {t11_b => 41, t11_c => 42 }
 , {             t11_c => 43 }
 , {t11_b => 44, t11_c => 45 }
 , {             t11_c => 46 }
 ]
);

test_rw($schema, test11 => <<__XML, \%t11c);
<test11>
  <t11_c>40</t11_c>
  <t11_b>41</t11_b>
  <t11_c>42</t11_c>
  <t11_c>43</t11_c>
  <t11_b>44</t11_b>
  <t11_c>45</t11_c>
  <t11_c>46</t11_c>
</test11>
__XML

### test 12

test_rw($schema, test12 => <<__XML, {t12 => 50});
<test12>
  <t12>50</t12>
</test12>
__XML

test_rw($schema, test12 => <<__XML, {});
<test12/>
__XML
