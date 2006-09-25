use ExtUtils::MakeMaker;

WriteMakefile
 ( NAME	 => 'XML::Compile'
 , VERSION_FROM => 'version'
 , PREREQ_PM    =>
   { XML::LibXML               => 1.60
   , Test::More                => 0.54
   , Test::Deep                => 0.095
   , Math::BigInt              => 1.77
   }
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'Compilation based XML processing'
 );
