#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

my $class = 'App::backimap::Status';
my @attributes = qw( timestamp server user folder storage );
my @methods = qw( save );

plan tests => 1 + @attributes + 1;

use_ok($class);

for my $attr (@attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}

can_ok( $class, @methods );
