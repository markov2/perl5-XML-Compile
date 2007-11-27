use warnings;
use strict;

use lib '../XMLCompile/lib';  # test environment at home

package TestTools;
use base 'Exporter';

use XML::LibXML;
use XML::Compile::Util qw/SCHEMA2001/;

use Test::More;
use Test::Deep   qw/cmp_deeply/;
use POSIX        qw/_exit/;
use Log::Report  qw/try/;
use Data::Dumper qw/Dumper/;

our @EXPORT = qw/
 $TestNS
 $SchemaNS
 $dump_pkg
 @run_opts
 reader
 reader_error
 writer
 writer_test
 writer_error
 compare_xml
 test_rw
 templ_xml
 templ_perl
 /;

our $TestNS   = 'http://test-types';
our $SchemaNS = SCHEMA2001;
our $dump_pkg = 't::dump';
our @run_opts = ();

sub reader($$$@)
{   my ($schema, $test, $type) = splice @_, 0, 3;

    my $read_t = $schema->compile
     ( READER             => $type
     , check_values       => 1
     , include_namespaces => 0
     , @run_opts
     , @_
     );

    ok(defined $read_t, "reader element $test");
    cmp_ok(ref($read_t), 'eq', 'CODE');
    $read_t;
}

sub reader_error($$$)
{   my ($schema, $test, $xml) = @_;
    my $type  = $test =~ m/\{/ ? $test : "{$TestNS}$test";
    my $r     = reader($schema, $test, $type);
    defined $r or return;

    my $tree  = try { $r->($xml) };
    my $error
       = ref $@ && $@->exceptions
       ? join("\n", map {$_->message} $@->exceptions)
       : '';
    undef $tree if $error;   # there is output if only warnings are produced

    ok(!defined $tree, "no return for $test");
    warn "RETURNED TREE=",Dumper $tree if defined $tree;
    ok(length $error, "ER=$error");
    $error;
}

sub writer($$$@)
{   my ($schema, $test, $type) = splice @_, 0, 3;

    my $write_t = $schema->compile
     ( WRITER             => $type
     , check_values       => 1
     , include_namespaces => 0
     , use_default_prefix => 1
     , @run_opts
     , @_
     );

    ok(defined $write_t, "writer element $test");
    defined $write_t or return;

    cmp_ok(ref($write_t), 'eq', 'CODE');
    $write_t;
}

sub writer_test($$;$)
{   my ($write_t, $data, $doc) = @_;

    $doc ||= XML::LibXML->createDocument('test doc', 'utf-8');
    isa_ok($doc, 'XML::LibXML::Document');

    my $tree = $write_t->($doc, $data);
    ok(defined $tree);
    defined $tree or return;

    isa_ok($tree, 'XML::LibXML::Node');
    $tree;
}

sub writer_error($$$)
{   my ($schema, $test, $data) = @_;
    my $type  = $test =~ m/\{/ ? $test : "{$TestNS}$test";

    my $write = writer($schema, $type, $type);
    ok(defined $write, "created writer $test");
    is(ref $write, 'CODE');
    my $node;
    try { my $doc = XML::LibXML->createDocument('test doc', 'utf-8');
          isa_ok($doc, 'XML::LibXML::Document');
          $node = $write->($doc, $data);
    };
 
    my $error
       = ref $@ && $@->exceptions
       ? join("\n", map {$_->message} $@->exceptions)
       : '';
    undef $node if $error;   # there is output if only warnings are produced

#   my $error = $@ ? $@->wasFatal->message : '';
    ok(!defined $node, "no return for $test");
    warn "RETURNED =", $node->toString if ref $node;
    ok(length $error, "EW=$error");
    $error;
}

sub test_rw($$$$;$$)
{   my ($schema, $test, $xml, $hash, $expect, $h2) = @_;

    my $type = $test =~ m/\{/ ? $test : "{$TestNS}$test";

    # reader

    my $r = reader($schema, $test, $type);
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

    my $writer = writer($schema, $test, $type);
    defined $writer or return;

    my $msg  = defined $h2 ? $h2 : $h;
    my $tree = writer_test($writer, $msg);

    compare_xml($tree, $expect || $xml);
}

sub compare_xml($$)
{   my ($tree, $expect) = @_;
    my $dump = ref $tree ? $tree->toString : $tree;

    if(!defined $dump) { ; }
    elsif($dump =~ m/\n|\s\s/)
    {   # output expects superfluous blanks
        $expect =~ s/\n\z//;
    }
    else
    {   for($expect)
        {   s/\>\s+/>/gs;
            s/\s+\</</gs;
            s/\>\s+\</></gs;
            s/\s*\n\s*/ /gs;
            s/\s{2,}/ /gs;
            s/\s+\z//gs;
        }
    }
    is($dump, $expect);
}

sub templ_xml($$$@)
{   my ($schema, $test, $xml, @opts) = @_;

    # Read testing
    my $abs = $test =~ m/\{/ ? $test : "{$TestNS}$test";

    my $output = $schema->template
     ( XML                => $abs
     , include_namespaces => 0
     , @opts
     );

   is($output."\n", $xml, "xml for $test");
}

sub templ_perl($$$@)
{   my ($schema, $test, $perl, @opts) = @_;

    # Read testing
    my $abs    = $test =~ m/\{/ ? $test : "{$TestNS}$test";

    my $output = $schema->template
     ( PERL               => $abs
     , include_namespaces => 0
     , @opts
     );

    is($output, $perl, "perl for $test");
}

1;
