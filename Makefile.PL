use ExtUtils::MakeMaker;

use 5.008;

WriteMakefile
 ( NAME	 	=> 'XML::Compile'
 , VERSION	=> '0.71'
 , PREREQ_PM    =>
   { XML::LibXML               => 1.65
   , Math::BigInt              => 1.78
   , IO                        => 1.22
   , Log::Report               => 0.09

   , Test::More                => 0.54
   , Test::Deep                => 0.095
   , Test::Pod                 => '1.00'
   }
 , EXE_FILES    =>
   [ 'bin/xml2yaml'
   ]
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'Compilation based XML processing'
 , LICENSE      => 'perl'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/xml-compile/raw
DISTDIR         = ../public_html/xml-compile/source
LICENSE         = artistic

# for POD
EXTENDS		= ../XMLSOAP:../XMLDaemon:../XMLDumper
FIRST_YEAR      = 2006
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/xml-compile/

# for HTML
HTML_OUTPUT     = ../public_html/xml-compile/html
HTML_DOCROOT    = /xml-compile/html
HTML_PACKAGE    = ../public_html/xml-compile/htmlpkg

__POSTAMBLE
