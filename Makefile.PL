use ExtUtils::MakeMaker;

WriteMakefile
 ( NAME	 => 'XML::Compile'
 , VERSION_FROM => 'version'
 , PREREQ_PM    =>
   { XML::LibXML               => 1.58
   , Regexp::Common            => 2.00
   , Test::More                => 0.54
   , Test::Deep                => 0.095
   }
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'Compilation based XML processing'
 );
