#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib';
use Test::More tests => 14;

# The versions of the following packages are reported to help understanding
# the environment in which the tests are run.  This is certainly not a
# full list of all installed modules.
my @show_versions =
 qw/Test::More
    Test::Deep
    XML::LibXML
    Math::BigInt
   /;

foreach my $package (@show_versions)
{   eval "require $package";

    my $report
      = !$@                    ? "version ". ($package->VERSION || 'unknown')
      : $@ =~ m/^Can't locate/ ? "not installed"
      : "reports error";

    warn "$package $report\n";
}

my $xml2_version = XML::LibXML::LIBXML_DOTTED_VERSION();
warn "libxml2 $xml2_version\n";

my @xv = split /\./, $xml2_version;
if($xv[0] < 2 || $xv[1] < 6 || $xv[2] < 23)
{   warn <<__WARN;

*
* WARNING:
* Your libxml2 version ($xml2_version) is quite old: you may
* have failing tests and poor functionality.
*
* Please install a new version of the library AND reinstall the
* XML::LibXML module.  Otherwise, you may need to install this
* module with force.
*

__WARN

    warn "Press enter to continue with the tests: \n";
    <STDIN>;
}

require_ok('XML::Compile');
require_ok('XML::Compile::Dumper');
require_ok('XML::Compile::Iterator');
require_ok('XML::Compile::Schema');
require_ok('XML::Compile::Schema::BuiltInFacets');
require_ok('XML::Compile::Schema::BuiltInTypes');
require_ok('XML::Compile::Schema::Instance');
require_ok('XML::Compile::Schema::NameSpaces');
require_ok('XML::Compile::Schema::Specs');
require_ok('XML::Compile::Schema::Translate');
require_ok('XML::Compile::Schema::XmlReader');
require_ok('XML::Compile::Schema::XmlWriter');
require_ok('XML::Compile::Schema::Template');
require_ok('XML::Compile::Util');
