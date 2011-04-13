#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

my $class = 'App::backimap';
my @attributes = qw( uri exclude verbose dir init clean _status _imap _storage );
my @methods = qw( new_with_options is_excluded setup backup run );

plan tests => 2 + @attributes;

use_ok($class);

for my $attr (@attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}

can_ok( $class, 'new', @methods, grep !/^_/, @attributes );
