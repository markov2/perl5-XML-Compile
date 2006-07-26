use warnings;
use strict;

package XML::Compile::Schema::BuiltInStructs;
use base 'Exporter';

our @EXPORT = qw/builtin_structs/;

my %reader;
my %writer;

use XML::Compile;
use Carp;
use List::Util    qw/first/;

=chapter NAME

XML::Compile::Schema::BuiltInStructs - handling of built-in data-structures

=chapter SYNOPSIS

 # Not for end-users
 use XML::Compile::Schema::BuiltInStructs;
 my $run = builtin_structs('READER');

=chapter DESCRIPTION
The translator understands schema's, but does not encode that into
actions.  This module implements those actions, which are different
for the reader and the writer.

In a later release, this module will probably be split in a separate
READER and WRITER module, because we usually do not need both reader
and writer within one program.

=chapter METHODS

=c_method builtin_structs 'READER'|'WRITER'
Returns a hash which defines the code to produce the code which
will do the job... code which produces code... I know, it is not
that simple.

=cut

sub builtin_structs($)
{   my $direction = shift;
      $direction eq 'READER' ? \%reader
    : $direction eq 'WRITER' ? \%writer
    : croak "Run either 'READER' or 'WRITER', not '$direction'";
}

# Each action implementation returns a code reference, which will be
# used to do the run-time work.  The principle of closures is used to
# keep the important information.  Be sure that you understand closures
# before you attempt to change anything.
#
# The returned reader subroutines will always be called
#       $reader->($xml_node)
# The returned writer subroutines will always be called
#       $writer->($doc, $value)

$reader{translate_tag} =
  sub { my $name = $_[1];
        $name =~ s/.*?\://;   # strip prefix, that's all
        $name;
      };

$writer{translate_tag} =
  sub { my ($node, $name, $args) = @_;
        my ($pref, $label)
                = index($name, ':') >=0 ? split(/\:/, $name) : ('',$name);
        return $label if $args->{ignore_namespaces};

        my $ns  = length($pref)? $node->lookupNamespaceURI($pref) :$args->{tns};

        my $out_ns = $args->{output_namespaces};
        my $out = $out_ns->{$ns};

        unless($out)   # start new name-space
        {   if(first {$pref eq $_->{prefix}} values %$out_ns)
            {   # avoid name clashes
                length($pref) or $pref = 'x';
                my $trail = '0';
                $trail++ while first {"$pref$trail" eq $_->{prefix}}
                                 values %$out_ns;
                $pref .= $trail;
            }
            $out_ns->{$ns} = $out = {uri => $ns, prefix => $pref};
        }

        $out->{used}++;
        my $prefix = $out->{prefix};
        length($prefix) ? "$prefix:$name" : $name;
    };

# all readers are called: $run->($node);
# all writers are called: $run->($data);
$reader{wrapper} =
 sub { my $processor = shift;
       sub { my $xml = ref $_[0] && $_[0]->isa('XML::LibXML::Node')
                     ? $_[0]
                     : XML::Compile->parse(\$_[0]);
             $xml ? $processor->($xml) : ();
           }
     };

$writer{wrapper} =
 sub { my $processor = shift;
       sub { my ($doc, $data) = @_;
             my $top = $processor->(@_);
             $doc->indexElements;
             $top;
           }
     };

$reader{wrapper_ns} =
 sub { $_[0] };        # no namespaces

$writer{wrapper_ns} =
 sub { my ($processor, $index) = @_;
#use Data::Dumper;
#warn Dumper $index;
       my @entries = map { $_->{used} ? [ $_->{uri}, $_->{prefix} ] : () }
           values %$index;

       sub { my $node = $processor->(@_);
             $node->setNamespace(@$_, 0) foreach @entries;
             $node;
           }
     };

#
## Element
#

$reader{element_fixed} =
 sub { my ($path, $fixed, $args) = @_;
       my $err = $args->{err};
       sub { $_[0]->textContent eq $fixed
             or $err->($path,$_[0]->textContent, "value fixed to '$fixed'");
             $fixed;
           }
     };

$writer{element_fixed} =
 sub { my ($path, $fixed, $args) = @_;
       my $err  = $args->{err};
       sub { $err->($path, $_[1], "value fixed to '$fixed'")
                if defined $_[1] && $_[1] ne $fixed;
             $_[0]->createTextNode($fixed);
           }
     };

$reader{element_repeated} =
 sub { my ($path, $ns, $childname, $do, $args, $min, $max) = @_;
       my $err  = $args->{err};
       sub { my @nodes = $_[0]->getChildrenByTagName($childname);
             $err->($path,scalar @nodes,"too few values (need $min)")
                if @nodes < $min;
             $err->($path,scalar @nodes,"too many values (max $max)")
                if $max ne 'unbounded' && @nodes > $max;
             my @r = map { $do->($_) } @nodes;
             @r ? ($childname => \@r) : (); 
           }
     };

$writer{element_repeated} =
 sub { my ($path, $ns, $childname, $do, $args, $min, $max) = @_;
       my $err  = $args->{err};
       sub { my ($doc, $values) = @_;
             my @values = ref $values eq 'ARRAY' ? @$values
                        : defined $values ? $values : ();
             $err->($path,scalar @values,"too few values (need $min)")
                if @values < $min;
             $err->($path,scalar @values,"too many values (max $max)")
                if $max ne 'unbounded' && @values > $max;
             map { $do->($doc, $_) } @values;
           }
     };

$reader{element_array} =
 sub { my ($path, $ns, $childname, $do, $args) = @_;
       sub { my @r = map { $do->($_) } $_[0]->getChildrenByTagName($childname);
             @r ? ($childname => \@r) : ();
           }
     };

$writer{element_array} =
 sub { my ($path, $ns, $childname, $do, $args) = @_;
       sub { my ($doc, $values) = @_;
             map { $do->($doc, $_) }
                 ref $values eq 'ARRAY' ? @$values
               : defined $values ? $values : ();
           }
     };

$reader{element_obligatory} =
 sub { my ($path, $ns, $childname, $do, $args) = @_;
       my $err  = $args->{err};
       sub {
# This should work with namespaces (but doesn't yet)
# my @nodes = $_[0]->getElementsByTagNameNS($ns,$childname);
             my @nodes = $_[0]->getChildrenByTagName($childname);
             my $node
              = (@nodes==0 || !defined $nodes[0])
              ? $err->($path, undef, "one value required")
              : shift @nodes;
             $node = $err->($path, 'found '.@nodes, "only one value expected")
                if @nodes;
             defined $node ? ($childname => $do->($node)) : ();
           }
     };

$writer{element_obligatory} =
 sub { my ($path, $ns, $childname, $do, $args) = @_;
       my $err  = $args->{err};
       sub { my ($doc, $value) = @_;
             return $do->($doc, $value) if defined $value;
             $value = $err->($path, $value, "one value required");
             defined $value ? $do->($doc, $value) : undef;
           }
     };

$reader{element_nillable} =
 sub { my ($path, $ns, $childname, $do, $args) = @_;
       my $err  = $args->{err};
       sub { my @nodes = $_[0]->getChildrenByTagName($childname);
             my $node
              = (@nodes==0 || !defined $nodes[0])
              ? $err->($path, undef, "one value required")
              : shift @nodes;
             $err->($path, 'found '.@nodes, "only one value expected")
                if @nodes;
             my $nil = $node->getAttribute('nil') || 'false';
             $childname => ($nil eq 'true' ? undef : $do->($node));
           }
     };

$writer{element_nillable} =
 sub { my ($path, $ns, $childname, $do, $args) = @_;
       my $err  = $args->{err};
       sub { my ($doc, $value) = @_;
             return $do->($doc, $value) if defined $value;
             my $node = $doc->createElement($childname);
             $node->setAttribute(nil => 'true');
             $node;
           }
     };

$reader{element_optional} =
 sub { my ($path, $ns, $childname, $do, $args) = @_;
       my $err  = $args->{err};
       sub { my @nodes = $_[0]->getElementsByLocalName($childname)
                or return ();
             $err->($path, scalar @nodes, "only one value expected")
                if @nodes > 1;
             my $val = $do->($nodes[0]);
             defined $val ? ($childname => $val) : ();
           }
     };

$writer{element_optional} =
 sub { my ($path, $ns, $childname, $do, $args) = @_;
       sub { defined $_[1] ? $do->(@_) : (); };
     };

$reader{create_element} =
   sub {$_[2]};

$writer{create_element} =
   sub { my ($path, $tag, $do, $args) = @_;
         sub { my @values = $do->(@_) or return ();
               my $node = $_[0]->createElement($tag);
               $node->addChild
                 ( ref $_ && $_->isa('XML::LibXML::Node') ? $_
                 : $_[0]->createTextNode(defined $_ ? $_ : ''))
                    for @values;
               $node;
             }
       };

$reader{rename_element} =
   sub {$_[1]};

$writer{rename_element} =
   sub { my ($tag, $do) = @_;
         sub { my $node = $do->(@_) or return ();
               $node->setNodeName($tag);
               $node;
             }
       };

# handle built-in types
# call->($path, $type, $code, $args)
# implementations can be sped-up: no check, no parse, no format

$reader{builtin_checked} =
 sub { my ($path, $type) = @_;
       my $check = $_[2]->{check};
       defined $check
          or return $reader{builtin_unchecked}->(@_);

       my $parse = $_[2]->{parse};
       my $err   = $_[3]->{err};

         defined $parse
       ? sub { my $value = ref $_[0] ? $_[0]->textContent : $_[0];
               defined $value or return undef;
                 $check->($value)
               ? $parse->($value)
               : $err->($path, $value, "illegal value for $type");
             }
       : sub { my $value = ref $_[0] ? $_[0]->textContent : $_[0];
               defined $value or return undef;
                 $check->($value)
               ? $value
               : $err->($path, $value, "illegal value for $type");
             };
      };

$writer{builtin_checked} =
 sub { my ($path, $type) = @_;
       my $check  = $_[2]->{check};
       defined $check
          or return $writer{builtin_unchecked}->(@_);
       
       my $format = $_[2]->{format};
       my $err    = $_[3]->{err};

         defined $format
       ? sub { defined $_[1] or return undef;
               my $value = $format->($_[1]);
               return $value if defined $value && $check->($value);
               $value = $err->($path, $_[1], "illegal value for $type");
               defined $value ? $format->($value) : undef;
             }
       : sub {
               return $_[1] if !defined $_[1] || $check->($_[1]);
               my $value = $err->($path, $_[1], "illegal value for $type");
               defined $value ? $format->($value) : undef;
             };
     };

$reader{builtin_unchecked} =
 sub { my (undef, undef, $code, undef) = @_;
       my $parse = $code->{parse};

         defined $parse
       ? sub { my $v = $_[0]->textContent; defined $v ? $parse->($v) : undef }
       : sub { $_[0]->textContent }
     };

$writer{builtin_unchecked} =
 sub { my $format = $_[2]->{format};
         defined $format
       ? sub { defined $_[1] ? $format->($_[1]) : undef }
       : sub { $_[1] }
     };

# simpleType

$reader{list} =
 sub { my ($path, $do, $args) = @_;
       sub { defined $_[0] or return undef;
             my @v = grep {defined} map {$do->($_)}
                 split " ", $_[0]->textContent;
             @v ? \@v : undef;
           }
     };

$writer{list} =
 sub { my ($path, $do, $args) = @_;
       sub { defined $_[1] && @{$_[1]} or return undef;
             my @r = grep {defined} map {defined $_ ? $do->($_[0], $_) : ()}
                 @{$_[1]};
             @r ? join(' ', @r) : undef;
           };
     };

$reader{union} =
 sub { my ($path, $args, $err, @types) = @_;
       sub { defined $_[0] or return undef;
             for(@types) {my $v = $_->($_[0]); defined $v and return $v }
             my $text = $_[0]->textContent;
             substr $text, 10, -1, '...' if length($text) > 13;
             $err->($path, $text, "no match in union");
           }
     };

$writer{union} =
 sub { my ($path, $args, $err, @types) = @_;
       sub { defined $_[1] or return undef;
             for(@types) {my $v = $_->(@_); defined $v and return $v }
             $err->($path, $_[1], "no match in union");
           };
     };

# complexType

$reader{complexType} =
 sub { shift; shift;
       my @do;
       while(@_) {shift; push @do, shift};

       sub { my %h = map { $_->(@_) } @do;
             keys %h ? \%h : ();
           }
     };

$writer{complexType} =
 sub { my ($path, $args, @do) = @_;
       my $err = $args->{err};
       sub { my ($doc, $data) = @_;
             unless(UNIVERSAL::isa($data, 'HASH'))
             {   $data = defined $data ? "$data" : 'undef';
                 $err->($path, $data, 'expected hash of input data');
                 return ();
             }
             my @elems = @do;
             my @res;
             while(@elems)
             {   my $childname = shift @elems;
                 push @res, (shift @elems)
                            ->($doc, delete $data->{$childname});
             }
             $err->($path, join(' ', sort keys %$data), 'unused data')
                 if keys %$data;
             @res;
          }
     };

# Attributes

$reader{attribute_required} =
 sub { my ($path, $tag, $do, $args) = @_;
       my $err  = $args->{err};
       sub { my $node = $_[0]->getAttributeNode($tag)
                     || $err->($path, undef, "attribute required");
             defined $node or return ();
             my $value = $do->($node);
             defined $value ? ($tag => $value) : ();
           }
     };

$writer{attribute_required} =
 sub { my ($path, $tag, $do, $args) = @_;
       my $err = $args->{err};

       sub { my $value = $do->(@_);
             $value = $err->($path, 'undef'
                        , "missing value for required attribute $tag")
                unless defined $value;
             defined $value or return ();
             $_[0]->createAttribute($tag, $value);
           }
     };

$reader{attribute_optional} =
 sub { my ($path, $tag, $do, $args) = @_;
       my $err  = $args->{err};
       sub { my $node = $_[0]->getAttributeNode($tag)
                or return ();
             my $val = $do->($node);
             defined $val ? ($tag => $val) : ();
           }
     };

$writer{attribute_optional} =
 sub { my ($path, $tag, $do, $args) = @_;
       sub { my $value = $do->(@_) or return ();
             $_[0]->createAttribute($tag, $value);
           }
     };

1;

