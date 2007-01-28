use ExtUtils::MakeMaker;

WriteMakefile
 ( NAME	 	=> 'XML::Compile'
 , VERSION	=> 0.13
 , PREREQ_PM    =>
   { XML::LibXML               => 1.61
   , Test::More                => 0.54
   , Test::Deep                => 0.095
   , Math::BigInt              => 1.77
   }
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'Compilation based XML processing'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/xml-compile/raw
DISTDIR         = ../public_html/xml-compile/source
LICENSE         = artistic

# for POD
FIRST_YEAR      = 2006
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/xml-compile/

# for HTML
HTML_OUTPUT     = ../public_html/xml-compile/html
HTML_DOCROOT    = /xml-compile/html

__POSTAMBLE
