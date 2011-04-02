#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

my $class = 'App::backimap';
my @attributes = qw( status imap storage );
my @methods = qw( setup backup run usage );

plan tests => 1 + @attributes + 1;

use_ok($class);

for my $attr (@attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}

can_ok( $class, @methods );
