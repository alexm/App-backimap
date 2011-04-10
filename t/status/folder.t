#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

my $class = 'App::backimap::Status::Folder';
my @attributes = qw( count unseen name );

plan tests => 1 + @attributes;

use_ok($class);

for my $attr (@attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}
