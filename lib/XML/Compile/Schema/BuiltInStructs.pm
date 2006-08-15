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

$reader{tag_unqualified} =
$reader{tag_qualified} =
  sub { my $name = $_[2];
        $name =~ s/.*?\://;   # strip prefix, that's all
        $name;
      };

$writer{tag_qualified} =
  sub { my ($args, $node, $name) = @_;
        my ($pref, $label)
                = index($name, ':') >=0 ? split(/\:/, $name) : ('',$name);

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

$writer{tag_unqualified} =
  sub { my ($args, $node, $name) = @_;
        $name =~ s/.*\://;
        $name;
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

$reader{element_repeated} =
 sub { my ($path, $args, $ns, $childname, $do, $min, $max) = @_;
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
 sub { my ($path, $args, $ns, $childname, $do, $min, $max) = @_;
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
 sub { my ($path, $args, $ns, $childname, $do) = @_;
       sub { my @r = map { $do->($_) } $_[0]->getChildrenByTagName($childname);
             @r ? ($childname => \@r) : ();
           }
     };

$writer{element_array} =
 sub { my ($path, $args, $ns, $childname, $do) = @_;
       sub { my ($doc, $values) = @_;
             map { $do->($doc, $_) }
                 ref $values eq 'ARRAY' ? @$values
               : defined $values ? $values : ();
           }
     };

$reader{element_obligatory} =
 sub { my ($path, $args, $ns, $childname, $do) = @_;
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
 sub { my ($path, $args, $ns, $childname, $do) = @_;
       my $err  = $args->{err};
       sub { my ($doc, $value) = @_;
             return $do->($doc, $value) if defined $value;
             $value = $err->($path, $value, "one value required");
             defined $value ? $do->($doc, $value) : undef;
           }
     };

$reader{element_default} =
 sub { my ($path, $args, $ns, $childname, $do, $min, $max, $default) = @_;
       my $err  = $args->{err};
       my $def  = $do->($default);

       sub { my @nodes = $_[0]->getChildrenByTagName($childname);
             my $node = shift @nodes;
             $node = $err->($path, 'found '.@nodes, "only one value expected")
                if @nodes;
             ( $childname => (defined $node ? $do->($node) : $def) );
           }
     };

$reader{element_fixed} =
 sub { my ($path, $args, $ns, $childname, $do, $min, $max, $fixed) = @_;
       my $err = $args->{err};
       my $def  = $do->($fixed);

       sub { my @nodes = $_[0]->getChildrenByTagName($childname);
             my $node = shift @nodes;
             $node = $err->($path, 'found '.@nodes, "only one value expected")
                 if @nodes;
             my $value = defined $node ? $do->($node) : undef;
             $err->($path, $value,"value fixed to '".$fixed->value."'")
                 if !defined $value || $value ne $def;
             ($childname => $def);
           }
     };

$writer{element_fixed} =
 sub { my ($path, $args, $ns, $childname, $do, $min, $max, $fixed) = @_;
       my $err  = $args->{err};
       $fixed   = $fixed->value;

       sub { my ($doc, $value) = @_;
             my $ret = defined $value ? $do->($doc, $value) : undef;
             return $ret if defined $ret && $ret->textContent eq $fixed;

             $err->($path, $value, "value fixed to '$fixed'");
             $do->($doc, $fixed);
           }
     };

$reader{element_nillable} =
 sub { my ($path, $args, $ns, $childname, $do) = @_;
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
 sub { my ($path, $args, $ns, $childname, $do) = @_;
       my $err  = $args->{err};
       sub { my ($doc, $value) = @_;
             return $do->($doc, $value) if defined $value;
             my $node = $doc->createElement($childname);
             $node->setAttribute(nil => 'true');
             $node;
           }
     };

$reader{element_optional} =
 sub { my ($path, $args, $ns, $childname, $do) = @_;
       my $err  = $args->{err};
       sub { my @nodes = $_[0]->getElementsByLocalName($childname)
                or return ();
             $err->($path, scalar @nodes, "only one value expected")
                if @nodes > 1;
             my $val = $do->($nodes[0]);
             defined $val ? ($childname => $val) : ();
           }
     };

$writer{element_default} =
$writer{element_optional} =
 sub { my ($path, $args, $ns, $childname, $do) = @_;
       sub { defined $_[1] ? $do->(@_) : (); };
     };

$reader{create_element} =
   sub {$_[3]};

$writer{create_element} =
   sub { my ($path, $args, $tag, $do) = @_;
         sub { my @values = $do->(@_) or return ();
               my $node = $_[0]->createElement($tag);
               $node->addChild
                 ( ref $_ && $_->isa('XML::LibXML::Node') ? $_
                 : $_[0]->createTextNode(defined $_ ? $_ : ''))
                    for @values;
               $node;
             }
       };

$reader{builtin_checked} =
 sub { my ($path, $args, $type, $def) = @_;
       my $check = $def->{check};
       defined $check
          or return $reader{builtin_unchecked}->(@_);

       my $parse = $def->{parse};
       my $err   = $args->{err};

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
 sub { my ($path, $args, $type, $def) = @_;
       my $check  = $def->{check};
       defined $check
          or return $writer{builtin_unchecked}->(@_);
       
       my $format = $def->{format};
       my $err    = $args->{err};

         defined $format
       ? sub { defined $_[1] or return undef;
               my $value = $format->($_[1]);
               return $value if defined $value && $check->($value);
               $value = $err->($path, $_[1], "illegal value for $type");
               defined $value ? $format->($value) : undef;
             }
       : sub { return $_[1] if !defined $_[1] || $check->($_[1]);
               my $value = $err->($path, $_[1], "illegal value for $type");
               defined $value ? $format->($value) : undef;
             };
     };

$reader{builtin_unchecked} =
 sub { my $parse = $_[3]->{parse};

         defined $parse
       ? sub { my $v = $_[0]->textContent; defined $v ? $parse->($v) : undef }
       : sub { $_[0]->textContent }
     };

$writer{builtin_unchecked} =
 sub { my $format = $_[3]->{format};
         defined $format
       ? sub { defined $_[1] ? $format->($_[1]) : undef }
       : sub { $_[1] }
     };

# simpleType

$reader{list} =
 sub { my ($path, $args, $do) = @_;
       sub { defined $_[0] or return undef;
             my @v = grep {defined} map {$do->($_)}
                 split " ", $_[0]->textContent;
             @v ? \@v : undef;
           }
     };

$writer{list} =
 sub { my ($path, $args, $do) = @_;
       sub { defined $_[1] or return undef;
             my @el = ref $_[1] eq 'ARRAY' ? (grep {defined} @{$_[1]}) : $_[1];
             my @r = grep {defined} map {$do->($_[0], $_)} @el;
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
 sub { splice @_, 0, 3;
       my @do;
       while(@_) {shift; push @do, shift};

       sub { my %h = map { $_->(@_) } @do;
             keys %h ? \%h : ();
           }
     };

$writer{complexType} =
 sub { my ($path, $args, $node, @do) = @_;
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
 sub { my ($path, $args, $tag, $do) = @_;
       my $err  = $args->{err};
       sub { my $node = $_[0]->getAttributeNode($tag)
                     || $err->($path, undef, "attribute $tag required");
             defined $node or return ();
             my $value = $do->($node);
             defined $value ? ($tag => $value) : ();
           }
     };

$writer{attribute_required} =
 sub { my ($path, $args, $tag, $do) = @_;
       my $err = $args->{err};

       sub { my $value = $do->(@_);
             $value = $err->($path, 'undef'
                        , "missing value for required attribute $tag")
                unless defined $value;
             defined $value or return ();
             $_[0]->createAttribute($tag, $value);
           }
     };

$reader{attribute_prohibited} =
 sub { my ($path, $args, $tag, $do) = @_;
       my $err  = $args->{err};
       sub { my $node = $_[0]->getAttributeNode($tag);
             defined $node or return ();
             $err->($path, $node->textContent, "attribute $tag prohibited");
             ();
           }
     };

$writer{attribute_prohibited} =
 sub { my ($path, $args, $tag, $do) = @_;
       my $err = $args->{err};

       sub { my $value = $do->(@_);
             $err->($path, $value, "attribute $tag prohibited")
                if defined $value;
             ();
           }
     };

$reader{attribute_optional} =
 sub { my ($path, $args, $tag, $do) = @_;
       my $err  = $args->{err};
       sub { my $node = $_[0]->getAttributeNode($tag)
                or return ();
             my $val = $do->($node);
             defined $val ? ($tag => $val) : ();
           }
     };

$writer{attribute_default} =
$writer{attribute_optional} =
 sub { my ($path, $args, $tag, $do) = @_;
       sub { my $value = $do->(@_);
             defined $value ? $_[0]->createAttribute($tag, $value) : ();
           }
     };

$reader{attribute_default} =
 sub { my ($path, $args, $tag, $do, $default) = @_;
       my $err  = $args->{err};
       my $def  = $do->($default);

       sub { my $node = $_[0]->getAttributeNode($tag);
             ($tag => defined $node ? $do->($node) : $def);
           }
     };

$reader{attribute_fixed} =
 sub { my ($path, $args, $tag, $do, $fixed) = @_;
       my $err = $args->{err};
       my $def  = $do->($fixed);

       sub { my $node  = $_[0]->getAttributeNode($tag);
             my $value = defined $node ? $do->($node) : undef;
             $err->($path, $value, "attr value fixed to '".$fixed->value."'")
                 if !defined $value || $value ne $def;
             ($tag => $def);
           }
     };

$writer{attribute_fixed} =
 sub { my ($path, $args, $tag, $do, $fixed) = @_;
       my $err  = $args->{err};
       $fixed   = $fixed->value;

       sub { my ($doc, $value) = @_;
             my $ret = defined $value ? $do->($doc, $value) : undef;
             return $doc->createAttribute($tag, $ret)
                 if defined $ret && $ret eq $fixed;

             $err->($path, $value, "attr value fixed to '$fixed'");
             $ret = $do->($doc, $fixed);
             defined $ret ? $doc->createAttribute($tag, $ret) : ();
           }
     };

1;

