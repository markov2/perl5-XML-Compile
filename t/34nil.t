#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use XML::Compile::Schema;

use Test::More tests => 22;

my $schema   = XML::Compile::Schema->new( <<__SCHEMA__ );
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

</schema>
__SCHEMA__

ok(defined $schema);

push @run_opts, (check_occurs => 1, invalid => 'WARN');

#
# simple element type
#

run_test($schema, test1 => <<__XML__, {e1 => 42, e2 => 43, e3 => 44} );
<test1><e1>42</e1><e2>43</e2><e3>44</e3></test1>
__XML__

{   my @errors;
    push @run_opts, invalid => sub {no warnings; push @errors, "@_\n"; undef };

    my %t1b = (e1 => undef, e2 => undef, e3 => 45);
    run_test($schema, test1 => <<__XML__, \%t1b, <<__XML__);
<test1><e1></e1><e2 nil="true"/><e3>45</e3></test1>
__XML__
<test1><e2 nil="true"/><e3>45</e3></test1>
__XML__

     splice @run_opts, -2;

     cmp_ok(scalar(@errors), '==', 2, "read and write error");
     like($errors[0], qr!/el\(e1\)  illegal value!);
     like($errors[1], qr!/e1  one value required!);
}
