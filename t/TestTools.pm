use warnings;
use strict;

use lib '../XMLCompile/lib'  # test environment at home
      , '../XMLTester/lib';

package TestTools;
use base 'Exporter';

use XML::LibXML;
use XML::Compile::Util qw/SCHEMA2001/;
use XML::Compile::Tester;

use Test::More;
use Test::Deep   qw/cmp_deeply/;
use Log::Report;
use Data::Dumper qw/Dumper/;

our @EXPORT = qw/
 $TestNS
 $SchemaNS
 $dump_pkg
 test_rw
 /;

our $TestNS   = 'http://test-types';
set_default_namespace $TestNS;

our $SchemaNS = SCHEMA2001;
our $dump_pkg = 't::dump';

sub test_rw($$$$;$$)
{   my ($schema, $test, $xml, $hash, $expect, $h2) = @_;

    my $type = $test =~ m/\{/ ? $test : "{$TestNS}$test";

    # reader

    my $r = reader_create $schema, $test, $type;
    defined $r or return;

    my $h = $r->($xml);

#warn Dumper $h;
    unless(defined $h)   # avoid crash of is_deeply
    {   if(defined $expect && length($expect))
        {   ok(0, "failure: nothing read from XML");
        }
        else
        {   ok(1, "empty result");
        }
        return;
    }

#warn Dumper $h, $hash;
    cmp_deeply($h, $hash, "from xml");

    # Writer

    my $writer = writer_create $schema, $test, $type;
    defined $writer or return;

    my $msg  = defined $h2 ? $h2 : $h;
    my $tree = writer_test $writer, $msg;

    compare_xml($tree, $expect || $xml);
}

1;
