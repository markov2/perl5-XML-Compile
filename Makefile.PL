use ExtUtils::MakeMaker;

use 5.010;

WriteMakefile
 ( NAME	 	=> 'XML::Compile'
 , VERSION	=> '1.64'

 , PREREQ_PM    =>
   { XML::LibXML               => 2.0107
   , XML::Compile::Tester      => 0.90
   , IO                        => 1.22
   , Log::Report               => 1.20

   , Math::BigInt              => 1.77
   , Math::BigRat              => 0.10
   , bignum                    => 0.10
   , Digest::MD5               => 2.36
   , List::Util                => 0
   , MIME::Base64              => 3.10
   , Types::Serialiser         => 0

   , Test::More                => 0.54
   , Test::Deep                => 0.095
   }

 , EXE_FILES    =>
   [ 'bin/xml2yaml'
   , 'bin/xml2json'
   , 'bin/schema2example'
   ]
 , AUTHOR     => 'Mark Overmeer <markov@cpan.org>'
 , ABSTRACT   => 'Compilation based XML processing'
 , LICENSE    => 'perl_5'

 , META_MERGE =>
      { 'meta-spec' => { version => 2 }
      , resources  =>
          { repository =>
              { type => 'git'
              , url  => 'https://github.com/markov2/perl5-XML-Compile.git'
              , web  => 'https://github.com/markov2/perl5-XML-Compile'
              }
          , homepage => 'http://perl.overmeer.net/CPAN/'
          , license  => [ 'http://dev.perl.org/licenses/' ]
          }   
      }
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/xml-compile/raw
DISTDIR         = ../public_html/xml-compile/source
SKIP_LINKS      = XML::LibXML

# for POD
EXTENDS			= ../XML-Compile-SOAP:../XML-Compile-SOAP12:../XML-Compile-SOAP-Daemon:/p/XMLDumper:../XML-Compile-Cache:../XML-LibXML-Simple:../XML-Compile-Tester:../XML-Rewrite:../XML-Compile-RPC:../XML-Compile-SOAP-AnyEvent:../XML-Compile-C14N:../XML-Compile-WSS:../XML-Compile-WSS-Signature:../XML-Compile-WSDL11:../XML-Compile-SOAP-Mojolicious:../XML-Compile-Licensed
FIRST_YEAR      = 2006
EMAIL           = markov@cpan.org
WEBSITE         = http://perl.overmeer.net/xml-compile/

# for HTML
HTML_DOCROOT    = /xml-compile/html
HTML_OUTPUT     = ../public_html/xml-compile/html
HTML_PACKAGE    = ../public_html/xml-compile/htmlpkg

__POSTAMBLE
