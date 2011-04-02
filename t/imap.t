#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

my $class = 'App::backimap::IMAP';
my @attributes = qw( uri host port secure user password path client );

plan tests => 1 + @attributes;

use_ok($class);

for my $attr (@attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}
