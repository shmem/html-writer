package HTML::Writer;
use strict;

use XML::Writer;
use XML::DTDParser;
use LWP::Simple;
use File::Slurp;
use Carp qw(croak);

our $VERSION = 0.001;

our $DTD; # DTD structure, to trap errors e.g. illegal attributes
our %loaded; # hash for remembering loaded DTDs

# default DTD file
my $dtdfile = "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd";

my $public;     # PUBLIC part of DOCTYPE
my $system;     # SYSTEM part of DOCTYPE
my $vocabulary; # function ref hash for each DTD
my $savedcode;  # hash with saved subroutine references 

our $__frag = ''; # XXX how _not_ make that a package global?

sub import {
    my $package = shift;
    my $caller  = (caller)[0];
    my $dtd;
    if (@_) {
        $dtd = shift;
        $package->init($dtd) unless $loaded{$dtd};
    }
    if ($^H{"HTML::Writer/dtd"} && $dtd) {
        # unimport current DTD if $dtd to import isn't current
        __PACKAGE__->unimport unless $^H{"HTML::Writer/dtd"} eq $dtd;
    }
    if($^H{"HTML::Writer/dtd"} || $dtd) {
        $dtd = $^H{"HTML::Writer/dtd"};
        no strict 'refs';
        # functions derived from DTD
        for(keys %{$vocabulary->{$dtd}}) {
            my $sub = $caller."::$_";
            no warnings 'prototype';
            if (*{$sub}{CODE}) {
                $savedcode->{$caller}->{$_} = *{$sub}{CODE};
            }
            my $fn = __PACKAGE__."::$_";
            if(/_$/){
                *{$sub} = sub ($) { $fn->(@_) };
            } else {
                *{$sub} = sub (&) { $fn->(@_) };
            }
        }
        # regular functions to export
        # XXX should be treated as above
        for (qw(t render)) {
            my $sub = $caller."::$_";
            if (*{$sub}{CODE}) {
                $savedcode->{$caller}->{$_} = *{$sub}{CODE};
            }
            *{$sub} = \&{$_};
        }
        $^H{"HTML::Writer/dtd"} = $dtdfile;
    }
    $^H{"HTML::Writer/in_effect"} = 1;
}
sub unimport {
    my $package = shift;
    my $caller  = (caller)[0];
    # we might be called from import() to release current DTD
    $caller eq __PACKAGE__ and $caller = (caller(1))[0];
    for (keys %{$vocabulary->{$^H{"HTML::Writer/dtd"}}}) {
        no strict 'refs';
        delete ${$caller.'::'}{$_};
        if($savedcode->{$caller}->{$_}) {
            *{$caller.'::'.$_} = $savedcode->{$caller}->{$_};
        }
    }
    $^H{"HTML::Writer/in_effect"} = 0;
}
sub init {
    my $package = shift;
    $dtdfile = shift if $_[0];
    my $dtd;
    if($dtdfile =~ /^http:\/\//) {
        $dtd = get($dtdfile);
    } else {
        foreach my $p(@INC) {
            if (-f "$p/$dtdfile") {
                $dtd = read_file("$p/$dtdfile") or die "$!\n";
                last;
            }
        }
    }
    $dtd =~ /^\s+PUBLIC\s+"([^"]+)"/ms and $public = $1;
    $dtd =~ /^\s+SYSTEM\s+"([^"]+)"/ms and $system = $1;
    $dtd =~ s/.*=== Imported Names =+-->//s; # trap 'die' in XML::DTDParser
    $DTD = ParseDTD $dtd or die "$!";
    my $elems = [ map { uc($_) } keys %$DTD ];
    my %s;
    my $attrs = [
    grep { s/-/_/g; ! $s{$_}++ }
        map { keys %{$DTD->{$_}->{'attributes'}} } keys %$DTD
    ];
    define_vocabulary($dtdfile,$elems,$attrs);
    $loaded{$dtdfile}++;
} 

sub define_vocabulary {
    no strict "refs";
    my($dtdfile, $elems, $attrs) = @_;
    for (@$elems) {
        my $name = $_;
        my $sub = sub(&) { _elem($name, @_) };
        # *{$_} = $sub;
        $vocabulary->{$dtdfile}->{$_} = $sub;
    }
    for (@$attrs) {
        my $name = $_;
        my $sub = sub($) { _attr($name, @_) };
        # *{$_."_"} = $sub;
        $vocabulary->{$dtdfile}->{$_.'_'} = $sub;
    }
}

# root fragment
sub doc(&) {
    my ($content_fn) = @_;
    local $__frag = [undef,undef,undef];
    $content_fn->();
    $__frag->[2][0];
}

sub _elem {
    my ($elem_name, $content_fn) = @_;
    # an element is represented by the triple [name, attrs, children]
    my $elem = [$elem_name, undef, undef];
    my $ret =  do { local $__frag = $elem; $content_fn->(); };
    $elem->[2] = [$ret] if defined $ret and not $elem->[2];
    $__frag->[2] = [] unless $__frag->[2];
    push @{$__frag->[2]}, $elem;
    undef;
}

sub _attr {
    my ($attr_name, $val) = @_;
    $attr_name =~ s/_/-/g;
    my $parent = $__frag->[0];
    croak "Illegal attribute '$attr_name' in '$parent'"
        unless $DTD->{lc $parent}->{attributes}->{$attr_name};
    push @{$__frag->[1]}, [$attr_name, $val];
    undef;
}

sub t ($) { push @{$__frag->[2]}, @_ }

sub render_via_xml_writer {
    my $doc = shift;
    my $writer = XML::Writer->new(@_);  # extra args go to ->new()
    $writer->doctype( "HTML", $public, $system )
        if $public and $system;
    _render($writer,$doc);
    $writer->end();
    undef $__frag;
}

sub _render {
    my ($writer,$frag) = @_;
    my ($elem, $attrs, $children) = @$frag;
    
    $elem = lc($elem);
    $writer->startTag( $elem, map {@$_} @$attrs );
    for (@$children) {
        ref() ? _render($writer,$_) : $writer->characters($_);
    }
    $writer->endTag($elem);
}

sub render(&;$) {
    local $__frag = '';
    my $docfn  = shift;
    my $indent = shift;
    my $output = '';
    (defined $indent and $indent =~ /^\d+/) or ($indent = 2);
    render_via_xml_writer(
        doc( \&$docfn ),
        DATA_MODE => 1,
        UNSAFE => 1,
        DATA_INDENT => $indent,
        OUTPUT => \$output,
    );
    undef $__frag;
    undef $docfn;
    my $wantarray = wantarray;
    if(defined $wantarray) {
        return $wantarray == 0 ? $output : split /\n/, $output;
    }
    print $output;
}
our $AUTOLOAD;
sub AUTOLOAD {
    $AUTOLOAD =~ s/.*:://;
    my ($caller,$line,$hinthash) = (caller(1))[0,2,10];
    if ($hinthash->{"HTML::Writer/in_effect"}) {
        goto &{$vocabulary->{$hinthash->{"HTML::Writer/dtd"}}->{$AUTOLOAD}};
    } else {
        goto &{$savedcode->{$caller}->{$AUTOLOAD}};
    }
}
1;
__END__

=head1 NAME

HTML::Writer - write HTML documents in perl

=head1 SYNOPSIS

    package Test;
    my $foo  = "my \$foo";
    our $bar = "our \$bar";
    my $pack = __PACKAGE__;
    sub baz { "Test::baz" }

    package Page {
        use HTML::Writer qw(xhtml1-transitional.dtd);
        push local @ISA, $pack;
        render {
            HTML {
                HEAD {
                    TITLE { "foo bar"};
                };
                BODY {
                    class_ "ugly";
                    onload_ "javascript: mumble()";
                    DIV {
                        class_ "foo";
                        id_    "bar";
                        t      "If in doubt, mumble.";
                        IMG { src_ "foo.jpg" }; 
                    };
                    TABLE {
                        my $c;
                        for ($foo, $bar, Page->baz()) {
                            TR {
                                TD { $_ }; TD { $c++};
                            } 
                        } 
                    };
                    DIV { class_ "bar"; t "End of that." };
                } 
            };
        };
    };

=head1 DESCRIPTION

blah blah...

=head1 AUTHOR

    shmem@cpan.org

=head1 CREDITS

This module is based on an idea by Tom Moertel (tmoertel on PerlMonks).

=head1 COPYRIGHT

       Copyright 2017, shmem

       This library is free software; you can redistribute it and/or modify it
       under the same terms as Perl itself.

=cut
