package XML::Compile::Schema::XmlReader;

use strict;
use warnings;
no warnings 'once';

use Log::Report 'xml-compile', syntax => 'SHORT';
use List::Util qw/first/;

use XML::Compile::Util     qw/pack_type odd_elements block_label/;
use XML::Compile::Iterator ();

=chapter NAME

XML::Compile::Schema::XmlReader - bricks to translate XML to HASH

=chapter SYNOPSIS

 my $schema = XML::Compile::Schema->new(...);
 my $code   = $schema->compile(READER => ...);

=chapter DESCRIPTION
The translator understands schemas, but does not encode that into
actions.  This module implements those actions to translate from XML
into a (nested) Perl HASH structure.

=cut

# Each action implementation returns a code reference, which will be
# used to do the run-time work.  The mechanism of `closures' is used to
# keep the important information.  Be sure that you understand closures
# before you attempt to change anything.

# The returned reader subroutines will always be called
#      my @pairs = $reader->($tree);

# Some error messages are labeled with 'misfit' which is used to indicate
# that the structure of found data is not conforming the needs. For optional
# blocks, these errors are caught and un-done.

sub tag_unqualified
{   my $name = $_[3];
    $name =~ s/.*?\://;   # strip prefix, that's all
    $name;
}
*tag_qualified = \&tag_unqualified;

sub element_wrapper
{   my ($path, $args, $processor) = @_;
    # no copy of $_[0], because it may be a large string
    sub { my $tree;
          if(ref $_[0] && UNIVERSAL::isa($_[0], 'XML::LibXML::Iterator'))
          {   $tree = $_[0];
          }
          else
          {   my $xml = XML::Compile->dataToXML($_[0])
                  or return ();
              $xml    = $xml->documentElement
                  if $xml->isa('XML::LibXML::Document');
              $tree   = XML::Compile::Iterator->new($xml, 'top',
                  sub { $_[0]->isa('XML::LibXML::Element') } );
          }

          $processor->($tree);
        };
}

sub attribute_wrapper
{   my ($path, $args, $processor) = @_;

    sub { my $attr = shift;
          ref $attr && $attr->isa('XML::LibXML::Attr')
              or error __x"expects an attribute node, but got `{something}' at {path}"
                    , something => (ref $attr || $attr), path => $path;

          my $node = XML::LibXML::Element->new('dummy');
          $node->addChild($attr);

          $processor->($node);
        };
}

sub wrapper_ns        # no namespaces in the HASH
{   my ($path, $args, $processor, $index) = @_;
    $processor;
}

#
## Element
#

sub sequence($@)
{   my ($path, $args, @pairs) = @_;
    bless
    sub { my $tree = shift;
          my @res;
          my @do = @pairs;
          while(@do)
          {   my ($take, $do) = (shift @do, shift @do);
              push @res
                , ref $do eq 'BLOCK'           ? $do->($tree)
                : ref $do eq 'ANY'             ? $do->($tree)
                : ! defined $tree              ? $do->($tree)
                : $tree->currentLocal eq $take ? $do->($tree)
                :                                $do->(undef);
                # is missing permitted? otherwise crash
          }

          @res;
        }, 'BLOCK';
}

sub choice($@)
{   my ($path, $args, %do) = @_;

    bless
    sub { my $tree  = shift;
          my $local = defined $tree  ? $tree->currentLocal : undef;
          my $elem  = defined $local ? $do{$local} : undef;

          return $elem->($tree) if $elem;

          # very silly situation: some people use a minOccurs within
          # a choice, instead on choice itself.
          foreach my $some (values %do)
          {   try { $some->(undef) };
              $@ or return ();
          }

          $local
              or error __x"no elements left for choice at {path}"
                   , path => $path, _class => 'misfit';

          defined $elem
              or error __x"no alternative for choice before `{tag}' at {path}"
                   , tag => $local, path => $path, _class => 'misfit';
    }, 'BLOCK';
}

sub all($@)
{   my ($path, $args, @pairs) = @_;

    bless
    sub { my $tree = shift;
          my %do   = @pairs;
          my @res;
          while(1)
          {   my $local = $tree->currentLocal or last;
              my $do    = delete $do{$local}  or last; # already seen?
              push @res, $do->($tree);
          }

          # saw all of all?
          push @res, $_->(undef)
              for values %do;

          @res;
        }, 'BLOCK';
}

sub block_handler
{   my ($path, $args, $label, $min, $max, $process, $kind) = @_;
    my $multi = block_label $kind, $label;

    # flatten the HASH: when a block appears only once, there will
    # not be an additional nesting in the output tree.
    if($max ne 'unbounded' && $max==1)
    {   return $process if $min==1;
        return bless     # $min==0
        sub { my $tree    = shift or return ();
              my $starter = $tree->currentChild or return;
              my @pairs   = try { $process->($tree) };
              if($@->wasFatal(class => 'misfit'))
              {   # error is ok, if nothing consumed
                  my $ending = $tree->currentChild;
                  $@->reportAll if !$ending || $ending!=$starter;
                  return ();
              }
              elsif($@) {$@->reportAll};

              @pairs;
            }, 'BLOCK';
    }

    if($max ne 'unbounded' && $min>=$max)
    {   return bless
        sub { my $tree = shift;
              my @res;
              while(@res < $min)
              {   my @pairs = $process->($tree);
                  push @res, {@pairs};
              }
              ($multi => \@res);
            }, 'BLOCK';
    }

    if($min==0)
    {   return bless
        sub { my $tree = shift or return ();
              my @res;
              while($max eq 'unbounded' || @res < $max)
              {   my $starter = $tree->currentChild or last;
                  my @pairs   = try { $process->($tree) };
                  if($@->wasFatal(class => 'misfit'))
                  {   # misfit error is ok, if nothing consumed
                      my $ending = $tree->currentChild;
                      $@->reportAll if !$ending || $ending!=$starter;
                      last;
                  }
                  elsif($@) {$@->reportAll}

                  @pairs or last;
                  push @res, {@pairs};
              }

              @res ? ($multi => \@res) : ();
            }, 'BLOCK';
    }

    bless
    sub { my $tree = shift or error __xn
             "block with `{name}' is required at least once at {path}"
           , "block with `{name}' is required at least {_count} times at {path}"
           , $min, name => $label, path => $path;

          my @res;
          while(@res < $min)
          {   my @pairs = $process->($tree);
              push @res, {@pairs};
          }
          while($max eq 'unbounded' || @res < $max)
          {   my $starter = $tree->currentChild or last;
              my @pairs   = try { $process->($tree) };
              if($@->wasFatal(class => 'misfit'))
              {   # misfit error is ok, if nothing consumed
                  my $ending = $tree->currentChild;
                  $@->reportAll if !$ending || $ending!=$starter;
                  last;
              }
              elsif($@) {$@->reportAll};

              @pairs or last;
              push @res, {@pairs};
          }
          ($multi => \@res);
        }, 'BLOCK';
}

sub element_handler
{   my ($path, $args, $label, $min, $max, $required, $optional) = @_;

    if($max ne 'unbounded' && $max==1)
    {   return $min==1
        ? sub { my $tree  = shift;
                my @pairs = $required->(defined $tree ? $tree->descend :undef);
                $tree->nextChild if defined $tree;
                ($label => $pairs[1]);
              }
        : sub { my $tree  = shift or return ();
                $tree->currentChild or return ();
                my @pairs = $optional->($tree->descend);
                @pairs or return ();
                $tree->nextChild;
                ($label => $pairs[1]);
              };
    }
        
    if($max ne 'unbounded' && $min>=$max)
    {   return
        sub { my $tree = shift;
              my @res;
              while(@res < $min)
              {   my @pairs = $required->(defined $tree ? $tree->descend:undef);
                  push @res, $pairs[1];
                  $tree->nextChild if defined $tree;
              }
              @res ? ($label => \@res) : ();
            };
    }

    if(!defined $required)
    {   return
        sub { my $tree = shift or return ();
              my @res;
              while($max eq 'unbounded' || @res < $max)
              {   $tree->currentChild or last;
                  my @pairs = $optional->($tree->descend);
                  @pairs or last;
                  push @res, $pairs[1];
                  $tree->nextChild;
              }
              @res ? ($label => \@res) : ();
            };
    }

    sub { my $tree = shift;
          my @res;
          while(@res < $min)
          {   my @pairs = $required->(defined $tree ? $tree->descend : undef);
              push @res, $pairs[1];
              $tree->nextChild if defined $tree;
          }
          while(defined $tree && ($max eq 'unbounded' || @res < $max))
          {   $tree->currentChild or last;
              my @pairs = $optional->($tree->descend);
              @pairs or last;
              push @res, $pairs[1];
              $tree->nextChild;
          }
          ($label => \@res);
        };
}

sub required
{   my ($path, $args, $label, $do) = @_;
    my $req =
    sub { my $tree  = shift;  # can be undef
          my @pairs = $do->($tree);
          @pairs
              or error __x"data for `{tag}' missing at {path}"
                     , tag => $label, path => $path, _class => 'misfit';
          @pairs;
        };
    bless $req, 'BLOCK' if ref $do eq 'BLOCK';
    $req;
}

sub element
{   my ($path, $args, $ns, $childname, $do) = @_;
    sub { my $tree  = shift;
          my $value = defined $tree && $tree->nodeLocal eq $childname
            ? $do->($tree) : $do->(undef);
          defined $value ? ($childname => $value) : ();
        };
}

sub element_default
{   my ($path, $args, $ns, $childname, $do, $default) = @_;
    my $def  = $do->($default);

    sub { my $tree = shift;
          defined $tree && $tree->nodeLocal eq $childname
              or return ($childname => $def);
          $do->($tree);
        };
}

sub element_fixed
{   my ($path, $args, $ns, $childname, $do, $fixed) = @_;
    my $fix  = $do->($fixed);

    sub { my $tree = shift;
          my ($label, $value)
            = $tree && $tree->nodeLocal eq $childname ? $do->($tree) : ();

          defined $value
              or error __x"element `{name}' with fixed value `{fixed}' missing at {path}"
                     , name => $childname, fixed => $fix, path => $path;

          $value eq $fix
              or error __x"element `{name}' must have fixed value `{fixed}', got `{value}' at {path}"
                     , name => $childname, fixed => $fix, value => $value
                     , path => $path;

          ($label => $value);
        };
}

sub element_nillable
{   my ($path, $args, $ns, $childname, $do) = @_;

    sub { my $tree = shift;
          my $value;
          if(defined $tree && $tree->nodeLocal eq $childname)
          {   my $nil  = $tree->node->getAttribute('nil') || 'false';
              return ($childname => 'NIL')
                  if $nil eq 'true' || $nil eq '1';
              $value = $do->($tree);
          }
          else
          {   $value = $do->(undef);
          }

          defined $value ? ($childname => $value) : ();
        };
}

#
# complexType and complexType/ComplexContent
#

sub complex_element
{   my ($path, $args, $tag, $elems, $attrs, $attrs_any) = @_;
    my @elems = odd_elements @$elems;
    my @attrs = (odd_elements(@$attrs), @$attrs_any);

    sub { my $tree    = shift; # or return ();
          my $node    = $tree->node;
          my %complex
           = ( (map {$_->($tree)} @elems)
             , (map {$_->($node)} @attrs)
             );

          defined $tree->currentChild
              and error __x"element `{name}' not processed at {path}"
                      , name => $tree->currentLocal, path => $path
                      , _class => 'misfit';

          ($tag => \%complex);
        };
}

#
# complexType/simpleContent
#

sub tagged_element
{   my ($path, $args, $tag, $st, $attrs, $attrs_any) = @_;
    my @attrs = (odd_elements(@$attrs), @$attrs_any);

    sub { my $tree   = shift or return ();
          my $simple = $st->($tree);
          my $node   = $tree->node;
          my @pairs  = map {$_->($node)} @attrs;
          defined $simple or @pairs or return ();
          defined $simple or $simple = 'undef';
          ($tag => {_ => $simple, @pairs});
        };
}

#
# simpleType
#

sub simple_element
{   my ($path, $args, $tag, $st) = @_;
    sub { my $value = $st->(@_);
          defined $value ? ($tag => $value) : ();
        };
}

sub builtin
{   my ($path, $args, $node, $type, $def, $check_values) = @_;
    my $check = $check_values ? $def->{check} : undef;
    my $parse = $def->{parse};
    my $err   = $path eq $type
      ? N__"illegal value `{value}' for type {type}"
      : N__"illegal value `{value}' for type {type} at {path}";

    $check
    ? ( defined $parse
      ? sub { my $value = ref $_[0] ? $_[0]->textContent : $_[0];
              defined $value or return undef;
              return $parse->($value, $_[0])
                  if $check->($value);
              error __x$err, value => $value, type => $type, path => $path;
            }
      : sub { my $value = ref $_[0] ? $_[0]->textContent : $_[0];
              defined $value or return undef;
              return $value if $check->($value);
              error __x$err, value => $value, type => $type, path => $path;
            }
      )

    : ( defined $parse
      ? sub { my $value = ref $_[0] ? shift->textContent : $_[0];
              defined $value or return undef;
              $parse->($value);
            }
      : sub { ref $_[0] ? shift->textContent : $_[0] }
      );
}

# simpleType

sub list
{   my ($path, $args, $st) = @_;
    sub { my $tree = shift or return undef;
          my $v = $tree->textContent;
          my @v = grep {defined} map {$st->($_) } split(" ",$v);
          \@v;
        };
}

sub facets_list
{   my ($path, $args, $st, $early, $late) = @_;
    sub { defined $_[0] or return undef;
          my $v = $st->(@_);
          for(@$early) { defined $v or return (); $v = $_->($v) }
          my @v = defined $v ? split(" ",$v) : ();
          my @r;
      EL: for my $e (@v)
          {   for(@$late) { defined $e or next EL; $e = $_->($e) }
              push @r, $e;
          }
          @r ? \@r : ();
        };
}

sub facets
{   my ($path, $args, $st, @do) = @_;
    sub { defined $_[0] or return undef;
          my $v = $st->(@_);
          for(@do) { defined $v or return (); $v = $_->($v) }
          $v;
        };
}

sub union
{   my ($path, $args, @types) = @_;
    sub { my $tree = shift or return undef;
          for(@types) { my $v = try { $_->($tree) }; $@ or return $v }
          my $text = $tree->textContent;

          substr $text, 20, -1, '...' if length($text) > 73;
          error __x"no match for `{text}' in union at {path}"
             , text => $text, path => $path;
        };
}

# Attributes

sub attribute_required
{   my ($path, $args, $ns, $tag, $do) = @_;
    sub { my $node = $_[0]->getAttributeNodeNS($ns, $tag);
          defined $node
             or error __x"attribute `{name}' is required at {path}"
                    , name => $tag, path => $path;

          defined $node or return ();
          my $value = $do->($node);
          defined $value ? ($tag => $value) : ();
        };
}

sub attribute_prohibited
{   my ($path, $args, $ns, $tag, $do) = @_;
    sub { my $node = $_[0]->getAttributeNodeNS($ns, $tag);
          defined $node or return ();
          error __x"attribute `{name}' is prohibited at {path}"
              , name => $tag, path => $path;
          ();
        };
}

sub attribute
{   my ($path, $args, $ns, $tag, $do) = @_;
    sub { my $node = $_[0]->getAttributeNodeNS($ns, $tag);
          defined $node or return ();;
          my $val = $do->($node);
          defined $val ? ($tag => $val) : ();
        };
}

sub attribute_default
{   my ($path, $args, $ns, $tag, $do, $default) = @_;
    my $def  = $do->($default);

    sub { my $node = $_[0]->getAttributeNodeNS($ns, $tag);
          ($tag => (defined $node ? $do->($node) : $def))
        };
}

sub attribute_fixed
{   my ($path, $args, $ns, $tag, $do, $fixed) = @_;
    my $def  = $do->($fixed);

    sub { my $node = $_[0]->getAttributeNodeNS($ns, $tag);
          my $value = defined $node ? $do->($node) : undef;

          defined $value && $value eq $def
              or error __x"value of attribute `{tag}' is fixed to `{fixed}', not `{value}' at {path}"
                  , tag => $tag, fixed => $def, value => $value, path => $path;

          ($tag => $def);
        };
}

sub attribute_fixed_optional
{   my ($path, $args, $ns, $tag, $do, $fixed) = @_;
    my $def  = $do->($fixed);

    sub { my $node  = $_[0]->getAttributeNodeNS($ns, $tag)
              or return ($tag => $def);

          my $value = $do->($node);
          defined $value && $value eq $def
              or error __x"value of attribute `{tag}' is fixed to `{fixed}', not `{value}' at {path}"
                  , tag => $tag, fixed => $def, value => $value, path => $path;

          ($tag => $def);
        };
}

# SubstitutionGroups

sub substgroup
{   my ($path, $args, $type, %do) = @_;

    bless
    sub { my $tree  = shift;
          my $local = ($tree ? $tree->currentLocal : undef)
              or error __x"no data for substitution group {type} at {path}"
                    , type => $type, path => $path;

          my $do    = $do{$local}
              or error __x"no substitute for {type} found at {path}"
                    , type => $type, path => $path;

          my @subst = $do->($tree->descend);
          $tree->nextChild;
          @subst;
        }, 'BLOCK';
}

# anyAttribute

sub anyAttribute
{   my ($path, $args, $handler, $yes, $no, $process) = @_;
    return () unless defined $handler;

    my %yes = map { ($_ => 1) } @{$yes || []};
    my %no  = map { ($_ => 1) } @{$no  || []};

    # Takes all, before filtering
    my $all =
    sub { my @result;
          foreach my $attr ($_[0]->attributes)
          {   $attr->isa('XML::LibXML::Attr') or next;
              my $ns = $attr->namespaceURI || $_[0]->namespaceURI;
              next if keys %yes && !$yes{$ns};
              next if keys %no  &&   $no{$ns};
              my $local = $attr->localName;
              push @result, pack_type($ns, $local) => $attr;
          }
          @result;
        };

    # Create filter if requested
    my $run = $handler eq 'TAKE_ALL'
    ? $all
    : sub { my @attrs = $all->(@_);
            my @result;
            while(@attrs)
            {   my ($type, $data) = (shift @attrs, shift @attrs);
                my ($label, $out) = $handler->($type, $data, $path, $args);
                push @result, $label, $out if defined $label;
            }
            @result;
          };

     bless $run, 'BLOCK';
}

# anyElement

sub anyElement
{   my ($path, $args, $handler, $yes, $no, $process, $min, $max) = @_;

    $handler ||= 'SKIP_ALL';

    my %yes = map { ($_ => 1) } @{$yes || []};
    my %no  = map { ($_ => 1) } @{$no  || []};

    # Takes all, before filtering
    my $all = bless
    sub { my $tree  = shift or return ();
          my $count = 0;
          my %result;
          while(   (my $child = $tree->currentChild)
                && ($max eq 'unbounded' || $count < $max))
          {   my $ns = $child->namespaceURI;
              $yes{$ns} or last if keys %yes;
              $no{$ns} and last if keys %no;

              my ($k, $v) = (pack_type($ns, $child->localName) => $child);
              $count++;
              push @{$result{$k}}, $v;
              $tree->nextChild;
          }

          $count >= $min
              or error __x"too few any elements, requires {min} and got {found}"
                    , min => $min, found => $count;

          %result;
        }, 'ANY';

    # Create filter if requested
    my $run
     = $handler eq 'TAKE_ALL' ? $all
     : $handler eq 'SKIP_ALL' ? sub { $all->(@_); () }
     : sub { my @elems = $all->(@_);
             my @result;
             while(@elems)
             {   my ($type, $data) = (shift @elems, shift @elems);
                 my ($label, $out) = $handler->($type, $data, $path, $args);
                 push @result, $label, $out if defined $label;
             }
             @result;
           };

     bless $run, 'ANY';
}

# any kind of hook

sub hook($$$$$$)
{   my ($path, $args, $r, $tag, $before, $replace, $after) = @_;
    return $r unless $before || $replace || $after;

    return sub { ($_[0]->node->localName => 'SKIPPED') }
        if $replace && grep {$_ eq 'SKIP'} @$replace;

    my @replace = $replace ? map {_decode_replace($path,$_)} @$replace : ();
    my @before  = $before  ? map {_decode_before($path,$_) } @$before  : ();
    my @after   = $after   ? map {_decode_after($path,$_)  } @$after   : ();

    sub
     { my $tree = shift or return ();
       my $xml  = $tree->node;
       foreach (@before)
       {   $xml = $_->($xml, $path);
           defined $xml or return ();
       }
       my @h = @replace
             ? map {$_->($xml,$args,$path,$tag)} @replace
             : $r->($tree->descend($xml));
       @h or return ();
       my $h = @h==1 ? {_ => $h[0]} : $h[1];  # detect simpleType
       foreach (@after)
       {   $h = $_->($xml, $h, $path);
           defined $h or return ();
       }
       $h;
     }
}

sub _decode_before($$)
{   my ($path, $call) = @_;
    return $call if ref $call eq 'CODE';

      $call eq 'PRINT_PATH' ? sub {print "$_[1]\n"; $_[0] }
    : error __x"labeled before hook `{call}' undefined", call => $call;
}

sub _decode_replace($$)
{   my ($path, $call) = @_;
    return $call if ref $call eq 'CODE';

    error __x"labeled replace hook `{call}' undefined", call => $call;
}

sub _decode_after($$)
{   my ($path, $call) = @_;
    return $call if ref $call eq 'CODE';

      $call eq 'PRINT_PATH' ? sub {print "$_[2]\n"; $_[1] }
    : $call eq 'XML_NODE'  ?
      sub { my $h = $_[1];
            ref $h eq 'HASH' or $h = { _ => $h };
            $h->{_XML_NODE} = $_[0];
            $h;
          }
    : $call eq 'ELEMENT_ORDER' ?
      sub { my ($xml, $h) = @_;
            ref $h eq 'HASH' or $h = { _ => $h };
            my @order = map {$_->nodeName}
               grep { $_->isa('XML::LibXML::Element') }
                  $xml->childNodes;
            $h->{_ELEMENT_ORDER} = \@order;
            $h;
          }
    : $call eq 'ATTRIBUTE_ORDER' ?
      sub { my ($xml, $h) = @_;
            ref $h eq 'HASH' or $h = { _ => $h };
            my @order = map {$_->nodeName} $xml->attributes;
            $h->{_ATTRIBUTE_ORDER} = \@order;
            $h;
          }
    : error __x"labeled after hook `{call}' undefined", call => $call;
}

=chapter DETAILS

=section Processing Wildcards

If you want to collect information from the XML structure, which is
permitted by C<any> and C<anyAttribute> specifications in the schema,
you have to implement that yourself.  The problem is C<XML::Compile>
has less knowledge than you about the possible data.

=subsection anyAttribute

By default, the C<anyAttribute> specification is ignored.  When C<TAKE_ALL>
is given, all attributes which are fulfilling the name-space requirement
added to the returned data-structure.  As key, the absolute element name
will be used, with as value the related unparsed XML element.

In the current implementation, if an explicit attribute is also
covered by the name-spaces permitted by the anyAttribute definition,
then it will also appear in that list (and hence the handler will
be called as well).

Use M<XML::Compile::Schema::compile(anyAttribute)> to write your
own handler, to influence the behavior.  The handler will be called for
each attribute, and you must return list of pairs of derived information.
When the returned is empty, the attribute data is lost.  The value may
be a complex structure.

=example anyAttribute in XmlReader
Say your schema looks like this:

 <schema targetNamespace="http://mine"
    xmlns:me="http://mine" ...>
   <element name="el">
     <complexType>
       <attribute name="a" type="xs:int" />
       <anyAttribute namespace="##targetNamespace"
          processContents="lax">
     </complexType>
   </element>
   <simpleType name="non-empty">
     <restriction base="NCName" />
   </simpleType>
 </schema>

Then, in an application, you write:

 my $r = $schema->compile
  ( READER => pack_type('http://mine', 'el')
  , anyAttribute => 'ALL'
  );
 # or lazy: READER => '{http://mine}el'

 my $h = $r->( <<'__XML' );
   <el xmlns:me="http://mine">
     <a>42</a>
     <b type="me:non-empty">
        everything
     </b>
   </el>
 __XML

 use Data::Dumper 'Dumper';
 print Dumper $h;
 __XML__

The output is something like

 $VAR1 =
  { a => 42
  , '{http://mine}a' => ... # XML::LibXML::Node with <a>42</a>
  , '{http://mine}b' => ... # XML::LibXML::Node with <b>everything</b>
  };

You can improve the reader with a callback.  When you know that the
extra attribute is always of type C<non-empty>, then you can do

 my $read = $schema->compile
  ( READER => '{http://mine}el'
  , anyAttribute => \&filter
  );

 my $anyAttRead = $schema->compile
  ( READER => '{http://mine}non-empty'
  );

 sub filter($$$$)
 {   my ($fqn, $xml, $path, $translator) = @_;
     return () if $fqn ne '{http://mine}b';
     (b => $anyAttRead->($xml));
 }

 my $h = $r->( see above );
 print Dumper $h;

Which will result in

 $VAR1 =
  { a => 42
  , b => 'everything'
  };

The filter will be called twice, but return nothing in the first
case.  You can implement any kind of complex processing in the filter.

=subsection any element

By default, the C<any> definition in a schema will ignore all elements
from the container which are not used.  Also in this case C<TAKE_ALL>
is required to produce C<any> results.  C<SKIP_ALL> will ignore all
results, although this are being processed for validation needs.

The C<minOccurs> and C<maxOccurs> of C<any> are ignored: the amount of
elements is always unbounded.  Therefore, you will get an array of
elements back per type. 

=section Schema hooks

=subsection hooks executed before the XML is being processed
The C<before> hooks receives an M<XML::LibXML::Node> object and
the path string.  It must return a new (or same) XML node which
will be used from then on.  You probably can best modify a node
clone, not the original as provided by the user.  When C<undef>
is returned, the whole node will disappear.

This hook offers a predefined C<PRINT_PATH>.

=example to trace the paths
 $schema->addHook(path => qr/./, before => 'PRINT_PATH');

=subsection hooks executed as replacement
Your C<replace> hook should return a list of key-value pairs. To
produce it, it will get the M<XML::LibXML::Node>, the translator settings
as HASH, the path, and the localname.

This hook has a predefined C<SKIP>, which will not process the
found element, but simply return the string C<SKIPPED> as value.
This way, a whole tree of unneeded translations can be avoided.

=subsection hooks for post-processing, after the data is collected

The data is collect, and passed as second argument after the XML
node.  The third argument is the path.  Be careful that the
collected data might be a SCALAR (for simpleType).

This hook also offers a predefined C<PRINT_PATH>.  Besides, it
has C<XML_NODE>, C<ELEMENT_ORDER>, and C<ATTRIBUTE_ORDER>, which will
result in additional fields in the HASH, respectively containing the
CODE which was processed, the element names and the attribute names.
The keys start with an underscore C<_>.

=cut

1;
