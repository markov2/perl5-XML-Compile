
package XML::Compile::Schema::XmlWriter;

use strict;
use warnings;
no warnings 'once';

use Log::Report 'xml-compile', syntax => 'SHORT';
use List::Util    qw/first/;
use XML::Compile::Util qw/pack_type unpack_type odd_elements
   block_label type_of_node/;

=chapter NAME

XML::Compile::Schema::XmlWriter - bricks to translate HASH to XML

=chapter SYNOPSIS

 my $schema = XML::Compile::Schema->new(...);
 my $code   = $schema->compile(WRITER => ...);

=chapter DESCRIPTION
The translator understands schemas, but does not encode that into
actions.  This module implements those actions to translate from
a (nested) Perl HASH structure onto XML.

=cut

# Each action implementation returns a code reference, which will be
# used to do the run-time work.  The principle of closures is used to
# keep the important information.  Be sure that you understand closures
# before you attempt to change anything.
#
# The returned writer subroutines will always be called
#       $writer->($doc, $value) 

sub tag_qualified
{   my ($path, $args, $node, $name) = @_;
    my ($pref, $label)
       = index($name, ':') >=0 ? split(/\:/, $name) : ('',$name);

    my $ns  = length($pref)? $node->lookupNamespaceURI($pref) : $args->{tns};

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
}

sub tag_unqualified
{   my ($path, $args, $node, $name) = @_;
    $name =~ s/.*\://;
    $name;
}

sub element_wrapper
{   my ($path, $args, $processor) = @_;
    sub { my ($doc, $data) = @_;
          my $top = $processor->(@_);
          $doc->indexElements;
          $top;
        };
}
*attribute_wrapper = \&element_wrapper;

sub wrapper_ns
{   my ($path, $args, $processor, $index) = @_;
    my @entries;
    foreach my $entry (values %$index)
    {   $entry->{used} or next;
        push @entries, [ $entry->{uri}, $entry->{prefix} ];
#       $entry->{used} = 0;
    }

    @entries or return $processor;

    sub { my $node = $processor->(@_) or return ();
          $node->setNamespace(@$_, 0) foreach @entries;
          $node;
        };
}

sub sequence($@)
{   my ($path, $args, @pairs) = @_;

    bless
    sub { my ($doc, $values) = @_;
          defined $values or return ();

          my @res;
          my @do = @pairs;
          while(@do)
          {   my ($take, $do) = (shift @do, shift @do);
              push @res
                 , ref $do eq 'BLOCK' ? $do->($doc, $values)
                 : ref $do eq 'ANY'   ? $do->($doc, $values)
                 : $do->($doc, delete $values->{$take});
          }
          @res;
        }, 'BLOCK';
}

sub choice($@)
{   my ($path, $args, %do) = @_;
    my @specials;
    foreach my $el (keys %do)
    {   push @specials, delete $do{$el}
            if ref $do{$el} eq 'BLOCK' || ref $do{$el} eq 'ANY';
    }
 
    bless
    sub { my ($doc, $values) = @_;
          defined $values or return ();
          foreach my $take (keys %do)
          {  return $do{$take}->($doc, delete $values->{$take})
                 if $values->{$take};
          }
          
          foreach (@specials)
          {  my @d = try { $_->($doc, $values) };
             $@ or return @d;
          }
          ();
        }, 'BLOCK';
}

sub all($@)
{   my ($path, $args, @pairs) = @_;

    bless
    sub { my ($doc, $values) = @_;

          my @res;
          my @do = @pairs;
          while(@do)
          {   my ($take, $do) = (shift @do, shift @do);
              push @res
                 , ref $do eq 'BLOCK' || ref $do eq 'ANY'
                 ? $do->($doc, $values)
                 : $do->($doc, delete $values->{$take});
          }
          @res;
        }, 'BLOCK';
}
 
#
## Element
#

sub element_handler
{   my ($path, $args, $label, $min, $max, $required, $optional) = @_;
    $max eq "0" and return sub {};

    if($min==0 && $max eq 'unbounded')
    {   return
        sub { my ($doc, $values) = @_;
                ref $values eq 'ARRAY' ? map {$optional->($doc,$_)} @$values
              : defined $values        ? $optional->($doc, $values)
              :                          ();
            };
    }

    if($max eq 'unbounded')
    {   return
        sub { my ($doc, $values) = @_;
              my @values = ref $values eq 'ARRAY' ? @$values
                         : defined $values ? $values : ();
              ( (map { $required->($doc, shift @values) } 1..$min)
              , (map { $optional->($doc, $_) } @values)
              );
            };
    }

    if($min==0 && $max==1)
    {   return
        sub { my ($doc, $values) = @_;
              my @values = ref $values eq 'ARRAY' ? @$values
                         : defined $values ? $values : ();

              @values <= 1
                  or error __x"maximum only value needed for `{tag}', not {count} at {path}"
                        , tag => $label, count => scalar @values, path => $path;

              $optional->($doc, $values[0]);
            };
    }

    if($min==1 && $max==1)
    {   return
        sub { my ($doc, $values) = @_;
              my @values = ref $values eq 'ARRAY' ? @$values
                         : defined $values ? $values : ();

              if(@values!=1)
              {   @values
                     or error __x"required value for `{tag}' missing at {path}"
                          , tag => $label, path => $path;
                    
                  error __x"exactly one value needed for `{tag}', not {count} at {path}"
                    , tag => $label, count => scalar @values, path => $path;
              }

              $required->($doc, $values[0]);
            };
    }

    my $opt = $max - $min;
    sub { my ($doc, $values) = @_;
          my @values = ref $values eq 'ARRAY' ? @$values
                     : defined $values ? $values : ();

          ( (map { $required->($doc, shift @values) } 1..$min)
          , (map { $optional->($doc, shift @values) } 1..$opt)
          );
        };
}

sub block_handler
{   my ($path, $args, $label, $min, $max, $process, $kind) = @_;
    my $multi = block_label $kind, $label;

    if($min==0 && $max eq 'unbounded')
    {   my $code =
        sub { my $doc    = shift;
              my $values = delete shift->{$multi};
                ref $values eq 'ARRAY' ? (map {$process->($doc, $_)} @$values)
              : defined $values        ? $process->($doc, $values)
              :                          ();
            };
        return ($multi, bless($code, 'BLOCK'));
    }

    if($max eq 'unbounded')
    {   my $code =
        sub { my $doc    = shift;
              my $values = delete shift->{$multi};
              my @values = ref $values eq 'ARRAY' ? @$values
                         : defined $values ? $values : ();

              @values >= $min
                  or error __x"too few blocks specified for `{tag}', got {found} need {min} at {path}"
                        , tag => $label, found => scalar @values
                        , min => $min, path => $path;

              map { $process->($doc, $_) } @values;
            };
        return ($multi, bless($code, 'BLOCK'));
    }

    if($min==0 && $max==1)
    {   my $code =
        sub { my ($doc, $values) = @_;
              my @values = ref $values eq 'ARRAY' ? @$values
                         : defined $values ? $values : ();

              @values <= 1
                  or error __x"maximum only block needed for `{tag}', not {count} at {path}"
                        , tag => $label, count => scalar @values, path => $path;

              map { $process->($doc, $_) } @values;
            };
        return ($label, bless($code, 'BLOCK'));
    }

    if($min==1 && $max==1)
    {   my $code =
        sub { my ($doc, $values) = @_;
              my @values = ref $values eq 'ARRAY' ? @$values
                         : defined $values ? $values : ();

              @values==1
                  or error __x"exactly one block needed for `{tag}', not {count} at {path}"
                        , tag => $label, count => scalar @values, path => $path;

              map { $process->($doc, $_) } @values;
            };
        return ($label, bless($code, 'BLOCK'));
    }

    my $opt  = $max - $min;
    my $code =
    sub { my $doc    = shift;
          my $values = delete shift->{$multi};
          my @values = ref $values eq 'ARRAY' ? @$values
                     : defined $values ? $values : ();

          @values >= $min && @values <= $max
              or error __x"found {found} blocks for `{tag}', must be between {min} and {max} inclusive"
                   , tag => $label, min => $min, max => $max
                   , found => scalar @values;

          map { $process->($doc, $_) } @values;
        };
    ($multi, bless($code, 'BLOCK'));
}

sub required
{   my ($path, $args, $label, $do) = @_;
    my $req =
    sub { my @nodes = $do->(@_);
          return @nodes if @nodes;

          error __x"data for element or block starting with `{tag}' missing at {path}"
             , tag => $label, path => $path;
        };
    bless $req, 'BLOCK' if ref $do eq 'BLOCK';
    $req;
}

sub element
{   my ($path, $args, $ns, $childname, $do) = @_;
    sub { defined $_[1] ? $do->(@_) : () }
}

sub element_fixed
{   my ($path, $args, $ns, $childname, $do, $fixed) = @_;
    $fixed   = $fixed->value if ref $fixed;

    sub { my ($doc, $value) = @_;
          my $ret = defined $value ? $do->($doc, $value) : undef;
          return $ret if defined $ret && $ret->textContent eq $fixed;

          defined $ret
              or error __x"required element `{name}' with fixed value `{fixed}' missing at {path}"
                     , name => $childname, fixed => $fixed, path => $path;

          error __x"element `{name}' has value fixed to `{fixed}', got `{value}' at {path}"
             , name => $childname, fixed => $fixed
             , value => $ret->textContent, path => $path;
        };
}

sub element_nillable
{   my ($path, $args, $ns, $childname, $do) = @_;
    my $inas = $args->{interpret_nillable_as_optional};

    sub
    {   my ($doc, $value) = @_;
        return $do->($doc, $value)
            if !defined $value || $value ne 'NIL';

        return $doc->createTextNode('')
            if $inas;

        my $node = $doc->createElement($childname);
        $node->setAttribute(nil => 'true');
        $node;
    };
}

sub element_default
{   my ($path, $args, $ns, $childname, $do, $default) = @_;
    sub { defined $_[1] ? $do->(@_) : (); };
}

#
# complexType/ComplexContent
#

sub complex_element
{   my ($path, $args, $tag, $elems, $attrs, $any_attr) = @_;
    my @elems = odd_elements @$elems;
    my @attrs = @$attrs;
    my @anya  = @$any_attr;
    my $ignore_unused_tags = $args->{ignore_unused_tags};

    sub { my ($doc, $data) = @_;
          return $doc->importNode($data)
              if UNIVERSAL::isa($data, 'XML::LibXML::Element');

          unless(UNIVERSAL::isa($data, 'HASH'))
          {   defined $data
                  or error __x"complex `{tag}' requires data at {path}"
                        , tag => $tag, path => $path;

              error __x"complex `{tag}' requires a HASH of input data, not `{found}' at {path}"
                 , tag => $tag, found => $data, path => $path;
          }

          my $copy   = { %$data };  # do not destroy caller's hash
          my @childs = map {$_->($doc, $copy)} @elems;
          for(my $i=0; $i<@attrs; $i+=2)
          {   push @childs, $attrs[$i+1]->($doc, delete $copy->{$attrs[$i]});
          }

          push @childs, $_->($doc, $copy)
              for @anya;

          if(my @not_used = sort keys %$copy)
          {   mistake __xn "tag `{tags}' not used at {path}"
                , "unused tags {tags} at {path}"
                , scalar @not_used, tags => \@not_used, path => $path
                   unless $ignore_unused_tags;
          }

          my $node  = $doc->createElement($tag);
          $node->addChild
            ( ref $_ && $_->isa('XML::LibXML::Node') ? $_
            : $doc->createTextNode(defined $_ ? $_ : ''))
               for @childs;

          $node;
        };
}

#
# complexType/simpleContent
#

sub tagged_element
{   my ($path, $args, $tag, $st, $attrs, $attrs_any) = @_;
    my @attrs = @$attrs;
    my @anya  = @$attrs_any;

    sub { my ($doc, $data) = @_;
          return $doc->importNode($data)
              if UNIVERSAL::isa($data, 'XML::LibXML::Element');

          UNIVERSAL::isa($data, 'HASH')
             or error __x"tagged `{tag}' requires a HASH of input data, not `{found}' at {path}"
                   , tag => $tag, found => $data, path => $path;

          my $copy    = { %$data };
          my $content = $st->($doc, delete $copy->{_});
          my @childs;
          push @childs, $doc->createTextNode($content)
              if defined $content;

          for(my $i=0; $i<@attrs; $i+=2)
          {   push @childs, $attrs[$i+1]->($doc, delete $copy->{$attrs[$i]});
          }

          push @childs, $_->($doc, $copy)
              for @anya;

          if(my @not_used = sort keys %$copy)
          {   error __xn "tag `{tags}' not processed at {path}"
                       , "unprocessed tags {tags} at {path}"
                       , scalar @not_used, tags => \@not_used, path => $path;
          }

          @childs or return ();
          my $node  = $doc->createElement($tag);
          $node->addChild
            ( ref $_ && $_->isa('XML::LibXML::Node') ? $_
            : $doc->createTextNode(defined $_ ? $_ : ''))
               for @childs;
          $node;
       };
}

#
# simpleType
#

sub simple_element
{   my ($path, $args, $tag, $st) = @_;
    sub { my ($doc, $data) = @_;
          return $doc->importNode($data)
              if UNIVERSAL::isa($data, 'XML::LibXML::Element');
          
          my $value = $st->($doc, $data);
          my $node  = $doc->createElement($tag);
          error __x"expected single value for {tag}, but got {type}"
             , tag => $tag, type => ref($value)
              if ref $value eq 'ARRAY' || ref $value eq 'HASH';
          $node->addChild
            ( UNIVERSAL::isa($value, 'XML::LibXML::Node') ? $value
            : $doc->createTextNode(defined $value ? $value : ''));
          $node;
        };
}

sub builtin
{   my ($path, $args, $node, $type, $def, $check_values) = @_;
    my $check  = $check_values ? $def->{check} : undef;
    my $err    = $path eq $type
      ? N__"illegal value `{value}' for type {type}"
      : N__"illegal value `{value}' for type {type} at {path}";

    my $format = $def->{format};
    my $trans  = $args->{output_namespaces};

    $check
    ? ( defined $format
      ? sub { defined $_[1] or return undef;
              my $value = $format->($_[1], $trans);
              return $value if defined $value && $check->($value);
              error __x$err, value => $value, type => $type, path => $path;
            }
      : sub { return $_[1] if !defined $_[1] || $check->($_[1]);
              error __x$err, value => $_[1], type => $type, path => $path;
            }
      )
    : ( defined $format
      ? sub { defined $_[1] ? $format->($_[1], $trans) : undef }
      : sub { $_[1] }
      );
}

# simpleType

sub list
{   my ($path, $args, $st) = @_;
    sub { defined $_[1] or return undef;
          my @el = ref $_[1] eq 'ARRAY' ? (grep {defined} @{$_[1]}) : $_[1];
          my @r = grep {defined} map {$st->($_[0], $_)} @el;
          @r or return undef;
          join ' ', grep {defined} @r;
        };
}

sub facets_list
{   my ($path, $args, $st, $early, $late) = @_;
    sub { defined $_[1] or return undef;
          my @el = ref $_[1] eq 'ARRAY' ? (grep {defined} @{$_[1]}) : $_[1];

          my @r = grep {defined} map {$st->($_[0], $_)} @el;

      EL: for(@r)
          {   for my $l (@$late)
              { defined $_ or next EL; $_ = $l->($_) }
          }

          @r or return undef;
          my $r = join ' ', grep {defined} @r;

          my $v = $r;  # do not test with original
          for(@$early) { defined $v or return (); $v = $_->($v) }
          defined $v ? $r : ();
        };
}

sub facets
{   my ($path, $args, $st, @do) = @_;
    sub { defined $_[1] or return undef;
          my $v = $st->(@_);
          for(reverse @do)
          { defined $v or return (); $v = $_->($v) }
          $v;
        };
}

sub union
{   my ($path, $args, @types) = @_;
    sub { my ($doc, $value) = @_;
          defined $value or return undef;
          for(@types) {my $v = try { $_->($doc, $value) }; $@ or return $v }
          

          substr $value, 10, -1, '...' if length($value) > 13;
          error __x"no match for `{text}' in union at {path}"
             , text => $value, path => $path;
        };
}

sub substgroup
{   my ($path, $args, $type, %do) = @_;

    bless
    sub { my ($doc, $values) = @_;
          foreach my $take (keys %do)
          {   my $subst = delete $values->{$take}
                  or next;

              return $do{$take}->($doc, $subst);
          }
        }, 'BLOCK';
}



# Attributes

sub attribute_required
{   my ($path, $args, $ns, $tag, $do) = @_;

    sub { my $value = $do->(@_);
          return $_[0]->createAttributeNS($ns, $tag, $value)
              if defined $value;

          error __x"attribute `{tag}' is required at {path}"
             , tag => $tag, path => $path;
        };
}

sub attribute_prohibited
{   my ($path, $args, $ns, $tag, $do) = @_;

    sub { my $value = $do->(@_);
          defined $value or return ();

          error __x"attribute `{tag}' is prohibited at {path}"
             , tag => $tag, path => $path;
        };
}

sub attribute
{   my ($path, $args, $ns, $tag, $do) = @_;
    sub { my $value = $do->(@_);
          defined $value ? $_[0]->createAttributeNS($ns, $tag, $value) : ();
        };
}
*attribute_default = \&attribute;

sub attribute_fixed
{   my ($path, $args, $ns, $tag, $do, $fixed) = @_;
    $fixed   = $fixed->value if ref $fixed;

    sub { my ($doc, $value) = @_;
          defined $value
              or error __x"required fixed attribute `{tag}' missing at {path}"
                   , tag => $tag, path => $path;


          $value eq $fixed
              or error __x"value of attribute `{tag}' is fixed to `{fixed}', not `{got}' at {path}"
                   , tag => $tag, got => $value, fixed => $fixed, path => $path;

          $doc->createAttributeNS($ns, $tag, $fixed);
        };
}

sub attribute_fixed_optional
{   my ($path, $args, $ns, $tag, $do, $fixed) = @_;
    $fixed   = $fixed->value if ref $fixed;

    sub { my ($doc, $value) = @_;
          defined $value or return ();

          $value eq $fixed
              or error __x"value of attribute `{tag}' is fixed to `{fixed}', not `{got}' at {path}"
                   , tag => $tag, got => $value, fixed => $fixed, path => $path;

          $doc->createAttributeNS($ns, $tag, $fixed);
        };
}

# any

sub _split_any_list($$$)
{   my ($path, $type, $v) = @_;
    my @nodes = ref $v eq 'ARRAY' ? @$v : defined $v ? $v : return ([], []);
    my (@attrs, @elems);

    foreach my $node (@nodes)
    {   ref $node && !$node->isa('XML::LibXML')
            or error __x"elements for 'any' are XML::LibXML nodes, not {string} at {path}"
                  , string => $node, path => $path;

        if($node->isa('XML::LibXML::Attr'))
        {   push @attrs, $node;
            next;
        }

        if($node->isa('XML::LibXML::Element'))
        {   push @elems, $node;
            next;
        }

        error __x"an XML::LibXML::Element or ::Attr is expected as 'any' or 'anyAttribute value with {type}, but a {kind} was found at {path}"
           , type => $type, kind => ref $node, path => $path;
    }

    return (\@attrs, \@elems);
}

sub anyAttribute
{   my ($path, $args, $handler, $yes, $no, $process) = @_;
    my %yes = map { ($_ => 1) } @{$yes || []};
    my %no  = map { ($_ => 1) } @{$no  || []};

    bless
    sub { my ($doc, $values) = @_;

          my @res;
          foreach my $type (keys %$values)
          {   my ($ns, $local) = unpack_type $type;
              defined $ns or next;
              my @elems;

              $yes{$ns} or next if keys %yes;
              $no{$ns} and next if keys %no;

              my ($attrs, $elems)
                = _split_any_list $path, $type, delete $values->{$type};

              $values->{$type} = $elems if @$elems;
              @$attrs or next;

              foreach my $node (@$attrs)
              {   my $nodetype = type_of_node $node;
                  next if $nodetype eq $type;

                  error __x"provided 'anyAttribute' node has type {type}, but labeled with {other} at {path}"
                     , type => $nodetype, other => $type, path => $path
              }

              push @res, @$attrs;
          }
          @res;
        }, 'ANY';
}

sub anyElement
{   my ($path, $args, $handler, $yes, $no, $process, $min, $max) = @_;
    my %yes = map { ($_ => 1) } @{$yes || []};
    my %no  = map { ($_ => 1) } @{$no  || []};

    $handler ||= 'SKIP_ALL';

    bless
    sub { my ($doc, $values) = @_;
          my @res;

          foreach my $type (keys %$values)
          {   my ($ns, $local) = unpack_type $type;

              # name-spaceless Perl, then not for any(Attribute)
              defined $ns && length $ns or next;

              $yes{$ns} or next if keys %yes;
              $no{$ns} and next if keys %no;

              my ($attrs, $elems)
                 = _split_any_list $path, $type, delete $values->{$type};

              $values->{$type} = $attrs if @$attrs;
              @$elems or next;

              foreach my $node (@$elems)
              {   my $nodens = $node->namespaceURI;
                  defined $nodens or next; # see README.todo work-around

                  my $nodetype = type_of_node $node;
                  next if $nodetype eq $type;

                  error __x"provided 'any' element node has type {type}, but labeled with {other} at {path}"
                     , type => $nodetype, other => $type, path => $path
              }

              push @res, @$elems;
              $max eq 'unbounded' || @res <= $max
                  or error __x"too many 'any' elements after consuming {count} nodes of {type}, max {max} at {path}"
                       , count => scalar @$elems, type => $type
                       , max => $max, path => $path;
          }

          @res >= $min
              or error __x"too few 'any' elements, got {count} for minimum {min} at {path}"
                   , count => scalar @res, min => $min, path => $path;

          @res;
        }, 'ANY';
}

sub hook($$$$$$)
{   my ($path, $args, $r, $tag, $before, $replace, $after) = @_;
    return $r unless $before || $replace || $after;

    error __x"writer only supports one production (replace) hook"
        if $replace && @$replace > 1;

    return sub {()} if $replace && grep {$_ eq 'SKIP'} @$replace;

    my @replace = $replace ? map {_decode_replace($path,$_)} @$replace : ();
    my @before  = $before  ? map {_decode_before($path,$_) } @$before  : ();
    my @after   = $after   ? map {_decode_after($path,$_)  } @$after   : ();

    sub
    {  my ($doc, $val) = @_;
       foreach (@before)
       {   $val = $_->($doc, $val, $path);
           defined $val or return ();
       }

       my $xml = @replace
               ? $replace[0]->($doc, $val, $path, $tag)
               : $r->($doc, $val);
       defined $xml or return ();

       foreach (@after)
       {   $xml = $_->($doc, $xml, $path);
           defined $xml or return ();
       }

       $xml;
     }
}

sub _decode_before($$)
{   my ($path, $call) = @_;
    return $call if ref $call eq 'CODE';

      $call eq 'PRINT_PATH' ? sub { print "$_[2]\n"; $_[1] }
    : error __x"labeled before hook `{name}' undefined", name => $call;
}

sub _decode_replace($$)
{   my ($path, $call) = @_;
    return $call if ref $call eq 'CODE';

    # SKIP already handled
    error __x"labeled replace hook `{name}' undefined", name => $call;
}

sub _decode_after($$)
{   my ($path, $call) = @_;
    return $call if ref $call eq 'CODE';

      $call eq 'PRINT_PATH' ? sub { print "$_[2]\n"; $_[1] }
    : error __x"labeled after hook `{name}' undefined", name => $call;
}

=chapter DETAILS

=section Processing Wildcards

Complex elements can define C<any> (element) and C<anyAttribute> components,
with unpredictable content.  In this case, you are quite on your own in
processing those constructs.  The use of both schema components should
be avoided: please specify your data-structures explicit by clean type
extensions.

The procedure for the XmlWriter is simple: add key-value pairs to your
hash, in which the value is a fully prepared M<XML::LibXML::Attr>
or M<XML::LibXML::Element>.  The keys have the form C<{namespace}type>.
The I<namespace> component is important, because only spec conformant
namespaces will be used. The elements and attributes are added in
random order.

=example specify anyAttribute
 use XML::Compile::Util qw/pack_type/;

 my $attr = $doc->createAttributeNS($somens, $sometype, 42);
 my $h = { a => 12     # normal element or attribute
         , "{$somens}$sometype"        => $attr # anyAttribute
         , pack_type($somens, $mytype) => $attr # nicer
         };

=section Schema hooks

All writer hooks behave differently.  Be warned that the user values
can be a SCALAR or a HASH, dependent on the type.  You can intervene
on higher data-structure levels, to repair lower levels, if you want
to.

=subsection hooks executed before normal processing

The C<before> hook gives you the opportunity to fix the user
supplied data structure.  The XML generator will complain about
missing, superfluous, and erroneous values which you probably
want to avoid.

The C<before> hook returns new values.  Just must not interfere
with the user provided data.  When C<undef> is returned, the whole
node will be cancelled.

On the moment, the only predefined C<before> hook is C<PRINT_PATH>.

=example before hook on user-provided HASH.
 sub before_on_complex($$$)
 {   my ($doc, $values, $path) = @_;

     my %copy = %$values;
     $copy{extra} = 42;
     delete $copy{superfluous};
     $copy{count} =~ s/\D//g;    # only digits
     \%copy;
 }

=example before hook on simpleType data
 sub before_on_simple($$$)
 {   my ($doc, $value, $path) = @_;
     $value *= 100;    # convert euro to euro-cents
 }

=example before hook with object for complexType
 sub before_on_object($$$)
 {   my ($doc, $obj, $path) = @_;

     +{ name     => $obj->name
      , price    => $obj->euro
      , currency => 'EUR'
      };
 }

=subsection hooks replacing the usual XML node generation

Only one C<replace> hook can be defined.  It must return a
M<XML::LibXML::Node> or C<undef>.  The hook must use the
C<XML::LibXML::Document> node (which is provided as first
argument) to create a node.

On the moment, the only predefined C<replace> hook is C<SKIP>.

=example replace hook
 sub replace($$$)
 {  my ($doc, $values, $path, $tag) = @_
    my $node = $doc->createElement($tag);
    $node->appendText($values->{text});
    $node;
 }

=subsection hooks executed after the node was created

The C<after> hooks, will each get a chance to modify the
produced XML node, for instance to encapsulate it.  Each time,
the new XML node has to be returned.

On the moment, the only predefined C<after> hook is C<PRINT_PATH>.

=example add an extra sibbling after the usual process
 sub after($$$$)
 {   my ($doc, $node, $path) = @_;
     my $child = $doc->createAttributeNS($myns, earth => 42);
     $node->addChild($child);
     $node;
 }

=subsection fixing bad schemas

When a schema makes a mess out of things, we can fix that with hooks.
Also, when you need things that XML::Compile does not support (yet).

=example creating nodes with text

 {  my $text;

    sub before($$$)
    {   my ($doc, $values, $path) = @_;
        my %copy = %$values;
        $text = delete $copy{text};
        \%copy;
    }

    sub after($$$)
    {   my ($doc, $node, $path) = @_;
        $node->addChild($doc->createTextNode($text));
        $node;
    }

    $schema->addHook
     ( type   => 'mixed'
     , before => \&before
     , after  => \&after
     );
 }

=cut

1;

