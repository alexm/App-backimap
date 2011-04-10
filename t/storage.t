#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

my $class = 'App::backimap::Storage';
my @attributes = qw( dir init clean author email _git  );
my @methods = qw( find list get put delete move commit reset pack unpack );

plan tests => 1 + @attributes + 1;

use_ok($class);

for my $attr (@attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}

can_ok( $class, @methods );
